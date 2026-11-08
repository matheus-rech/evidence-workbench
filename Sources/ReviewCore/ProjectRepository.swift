import Foundation
import CryptoKit
import Darwin

public actor ProjectRepository {
    public let root: URL
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    public init(root: URL) {
        self.root = root
        self.encoder = JSONEncoder(); self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    /// Readable reviews plus one line per review directory that could not be opened.
    public struct Listing: Sendable {
        public var projects: [ReviewProject]
        public var failures: [String]
        public init(projects: [ReviewProject], failures: [String]) { self.projects = projects; self.failures = failures }
    }

    /// One unreadable review directory must not hide the others; it is reported by name instead.
    public func list() throws -> Listing {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var projects: [ReviewProject] = []; var failures: [String] = []
        for directory in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) where UUID(uuidString: directory.lastPathComponent) != nil {
            do { projects.append(try loadFile(directory.appendingPathComponent("project.json"))) }
            catch { failures.append("\(directory.lastPathComponent): \(error.localizedDescription)") }
        }
        return Listing(projects: projects.sorted { $0.updatedAt > $1.updatedAt }, failures: failures.sorted())
    }

    public func directory(for id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }

    public func save(_ project: ReviewProject) throws -> ReviewProject {
        let directory = directory(for: project.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lockURL = directory.appendingPathComponent("write.lock")
        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw WorkbenchError.invalid("Could not acquire the project write lock.") }
        defer { _ = flock(descriptor, LOCK_UN); Darwin.close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw WorkbenchError.invalid("Project write lock failed.") }
        let url = directory.appendingPathComponent("project.json")
        if FileManager.default.fileExists(atPath: url.path) {
            guard try loadFile(url).revision == project.revision else { throw WorkbenchError.conflict }
        } else if project.revision != 0 { throw WorkbenchError.conflict }
        var saved = project; saved.updatedAt = Date(); saved.revision += 1
        let bytes = try encoder.encode(saved)
        try bytes.write(to: url, options: .atomic)
        return saved
    }

    public func installDocument(data: Data, extension suffix: String, projectID: UUID) throws -> (path: String, hash: String) {
        guard data.count <= 100 * 1024 * 1024 else { throw WorkbenchError.invalid("Each document must be smaller than 100 MB.") }
        // Keep in step with DocumentLoader: a type that cannot be loaded must not be installed.
        guard ["pdf", "txt", "md", "docx"].contains(suffix.lowercased()) else { throw WorkbenchError.invalid("Unsupported document type. Import PDF, DOCX, UTF-8 TXT or Markdown.") }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let relative = "documents/\(hash).\(suffix.lowercased())"
        let url = directory(for: projectID).appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) { try data.write(to: url, options: .atomic) }
        return (relative, hash)
    }

    public func documentURL(_ document: SourceDocument, projectID: UUID) throws -> URL {
        let base = directory(for: projectID).resolvingSymlinksInPath()
        guard !document.relativePath.hasPrefix("/"), !document.relativePath.split(separator: "/").contains("..") else { throw WorkbenchError.invalid("Invalid document path.") }
        let url = base.appendingPathComponent(document.relativePath).resolvingSymlinksInPath()
        guard url.path.hasPrefix(base.path + "/documents/") else { throw WorkbenchError.invalid("Document path escapes the project.") }
        let bytes = try Data(contentsOf: url)
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        guard hash == document.sha256 else { throw WorkbenchError.invalid("The source file changed: its SHA-256 hash no longer matches.") }
        return url
    }

    public func exportBackup(project: ReviewProject, destination: URL) throws {
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw WorkbenchError.invalid("Choose a new backup folder name.") }
        let source = directory(for: project.id)
        guard !destination.standardizedFileURL.path.hasPrefix(source.standardizedFileURL.path + "/") else { throw WorkbenchError.invalid("Choose a backup location outside the project folder.") }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    public func importBackup(from folder: URL) throws -> ReviewProject {
        var project = try loadFile(folder.appendingPathComponent("project.json"))
        let source = folder.resolvingSymlinksInPath()
        var documents: [(SourceDocument, Data)] = []
        for document in project.documents + project.protocols {
            guard document.relativePath.hasPrefix("documents/"), !document.relativePath.split(separator: "/").contains("..") else { throw WorkbenchError.invalid("Unsafe backup attachment path.") }
            let url = source.appendingPathComponent(document.relativePath).resolvingSymlinksInPath()
            guard url.path.hasPrefix(source.path + "/documents/") else { throw WorkbenchError.invalid("Backup attachment escapes its folder.") }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 100 * 1024 * 1024 else { throw WorkbenchError.invalid("Backup attachment exceeds 100 MB.") }
            let bytes = try Data(contentsOf: url)
            let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            guard hash == document.sha256 else { throw WorkbenchError.invalid("Backup contains a changed or missing source document.") }
            documents.append((document, bytes))
        }
        project.id = UUID(); project.revision = 0; project.researchJob = nil
        for (document, bytes) in documents {
            let installed = try installDocument(data: bytes, extension: URL(fileURLWithPath: document.relativePath).pathExtension, projectID: project.id)
            if let index = project.documents.firstIndex(where: { $0.id == document.id }) { project.documents[index].relativePath = installed.path }
            if let index = project.protocols.firstIndex(where: { $0.id == document.id }) { project.protocols[index].relativePath = installed.path }
        }
        project.audit.append(.init(actor: "User", action: "Backup restored as new project", detail: "Original source hashes verified; active cloud job not resumed automatically."))
        return try save(project)
    }

    private func loadFile(_ url: URL) throws -> ReviewProject {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 100 * 1024 * 1024 else { throw WorkbenchError.invalid("Project JSON exceeds the supported size.") }
        let project = try decoder.decode(ReviewProject.self, from: Data(contentsOf: url))
        guard project.schemaVersion == 1 else { throw WorkbenchError.invalid("Unsupported project version. Update the app before opening this project.") }
        guard Set(project.documents.map(\.id)).count == project.documents.count, Set(project.plan.variables.map(\.id)).count == project.plan.variables.count else { throw WorkbenchError.invalid("The project contains duplicate document or field identifiers.") }
        guard (project.assets?.count ?? 0) <= 10_000, Set((project.assets ?? []).map(\.id)).count == (project.assets?.count ?? 0) else { throw WorkbenchError.invalid("The source collection is too large or contains duplicate identifiers.") }
        for asset in project.assets ?? [] {
            guard let document = project.documents.first(where: { $0.id == asset.documentID }) else { throw WorkbenchError.invalid("A source asset references a missing report.") }
            try asset.validate(document: document)
        }
        return project
    }
}
