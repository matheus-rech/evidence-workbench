import XCTest
@testable import ReviewCore

final class RepositoryTests: XCTestCase {
    func testExternalPilotWorkspaceLoadsWhenRequested() async throws {
        guard let path = ProcessInfo.processInfo.environment["EW_VALIDATION_PROJECT_ROOT"] else { return }
        let projects = try await ProjectRepository(root: URL(fileURLWithPath: path)).list()
        XCTAssertFalse(projects.isEmpty)
        XCTAssertEqual(projects.first?.plan.version, 2)
    }
    func tempRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("EvidenceWorkbenchTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    func testAtomicSaveAndReload() async throws {
        let repository = ProjectRepository(root: try tempRoot())
        let saved = try await repository.save(ReviewProject(title: "Test review"))
        XCTAssertEqual(saved.revision, 1)
        let loaded = try await repository.list()
        XCTAssertEqual(loaded.first?.id, saved.id); XCTAssertEqual(loaded.first?.title, "Test review")
    }
    func testStaleWriterCannotOverwriteNewerRevision() async throws {
        let root = try tempRoot(); let a = ProjectRepository(root: root); let b = ProjectRepository(root: root)
        let original = try await a.save(ReviewProject())
        var first = original; first.title = "First writer"
        _ = try await a.save(first)
        var stale = original; stale.title = "Stale writer"
        do { _ = try await b.save(stale); XCTFail("Stale write should fail") } catch { XCTAssertTrue(error is WorkbenchError) }
        let reloaded = try await a.list(); XCTAssertEqual(reloaded.first?.title, "First writer")
    }
    func testSourceHashDetectsTamperingAndPathTraversal() async throws {
        let repository = ProjectRepository(root: try tempRoot()); let project = try await repository.save(ReviewProject())
        let installed = try await repository.installDocument(data: Data("source".utf8), extension: "txt", projectID: project.id)
        var document = SourceDocument(filename: "source.txt", relativePath: installed.path, sha256: installed.hash, pages: [.init(number: 1, text: "source")])
        let url = try await repository.documentURL(document, projectID: project.id)
        try Data("changed".utf8).write(to: url)
        do { _ = try await repository.documentURL(document, projectID: project.id); XCTFail("Changed source should fail") } catch {}
        document.relativePath = "../secrets.txt"
        do { _ = try await repository.documentURL(document, projectID: project.id); XCTFail("Traversal should fail") } catch {}
    }
    func testBackupRestoresSourcesAsSeparateProject() async throws {
        let root = try tempRoot(); let repository = ProjectRepository(root: root.appendingPathComponent("reviews"))
        var project = try await repository.save(ReviewProject(title: "Original"))
        let bytes = Data("Full original source".utf8)
        let installed = try await repository.installDocument(data: bytes, extension: "txt", projectID: project.id)
        let doc = SourceDocument(filename: "article.txt", relativePath: installed.path, sha256: installed.hash, pages: [.init(number: 1, text: "Full original source")])
        project.documents = [doc]; project = try await repository.save(project)
        let destination = root.appendingPathComponent("backup.reviewbundle")
        try await repository.exportBackup(project: project, destination: destination)
        let restored = try await repository.importBackup(from: destination)
        XCTAssertNotEqual(restored.id, project.id); XCTAssertEqual(restored.documents.first?.studyID, doc.studyID)
        let restoredURL = try await repository.documentURL(restored.documents[0], projectID: restored.id)
        XCTAssertEqual(try Data(contentsOf: restoredURL), bytes)
    }
    func testBackupDoesNotOverwriteExistingFolder() async throws {
        let root = try tempRoot(); let repository = ProjectRepository(root: root.appendingPathComponent("reviews"))
        let project = try await repository.save(ReviewProject())
        do { try await repository.exportBackup(project: project, destination: root); XCTFail("Should not overwrite") } catch {}
    }
}
