import Foundation
import Combine
import ReviewCore

/// How the store learns whether cloud AI is allowed and which credential to send. Injected so tests never touch Keychain or user defaults.
struct CloudAccess: Sendable {
    var isEnabled: @Sendable () -> Bool
    var apiKey: @Sendable () throws -> String
    static let live = CloudAccess(isEnabled: { UserDefaults.standard.bool(forKey: "cloudAIEnabled") }, apiKey: { try AppCredentials.read() })
}

@MainActor final class WorkspaceStore: ObservableObject {
    @Published private(set) var projects: [ReviewProject] = []
    @Published var selectedProjectID: UUID?
    @Published private(set) var busy = false
    @Published private(set) var loading = true
    private var loadedOnce = false
    @Published private(set) var progress = ""
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published var hasUnsavedPlan = false
    @Published var hasUnsavedObservation = false
    var hasUnsavedChanges: Bool { hasUnsavedPlan || hasUnsavedObservation }
    @Published private(set) var activeResearch: Set<UUID> = []
    let repository: ProjectRepository
    let client: OpenAIClient
    let tableOCR = GLMTableClient()
    let localTableOCR = LocalTableClient()
    private let cloud: CloudAccess
    /// The foreground operation started by `perform`; exposed so tests can await completion.
    private(set) var operation: Task<Void, Never>?
    private var researchTasks: [UUID: Task<Void, Never>] = [:]
    private var saveTail: Task<Void, Never>?

    var current: ReviewProject? { projects.first { $0.id == selectedProjectID } }
    var extractionModel: String { UserDefaults.standard.string(forKey: "extractionModel") ?? "gpt-4.1" }
    var researchModel: String { UserDefaults.standard.string(forKey: "researchModel") ?? "o3" }
    var sourceCheckModel: String { UserDefaults.standard.string(forKey: "sourceCheckModel") ?? "gpt-4.1" }

    init(root: URL? = nil, client: OpenAIClient = OpenAIClient(), cloud: CloudAccess = .live) {
        self.client = client; self.cloud = cloud
        let args = ProcessInfo.processInfo.arguments
        let normal = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("EvidenceWorkbench/Reviews", isDirectory: true)
        repository = ProjectRepository(root: root ?? WorkspaceLocation.resolve(arguments: args, bundleURL: Bundle.main.bundleURL, identifier: Bundle.main.bundleIdentifier, isolated: Bundle.main.object(forInfoDictionaryKey: "EWIsolatedReview") as? Bool == true, configuredQA: Bundle.main.object(forInfoDictionaryKey: "EWValidationWorkspace") as? String, normal: normal))
    }

    func loadProjects() async {
        guard !loadedOnce else { return }
        loadedOnce = true; loading = true
        defer { loading = false }
        do {
            let listing = try await repository.list()
            projects = listing.projects; selectedProjectID = projects.first?.id
            let quarantined = projects.flatMap(\.observations).filter { $0.status == .edited && $0.verificationFingerprint == nil }.count
            if quarantined > 0 { notice = "Some saved rows need source review before verified export. Values are preserved; check the audit trail." }
            if !listing.failures.isEmpty {
                notice = "\(listing.failures.count) review folder(s) in \(repository.root.path) could not be opened and were left untouched: " + listing.failures.joined(separator: " · ")
            }
        } catch { errorMessage = "Review files could not be loaded: " + error.localizedDescription; loadedOnce = false }
    }

    func perform(_ label: String, action: @escaping @MainActor () async throws -> Void) {
        guard !busy, !loading else { return }
        busy = true; progress = label
        operation = Task {
            defer { busy = false; progress = ""; operation = nil }
            do { try await action() }
            catch is CancellationError { notice = "Cancelled. Completed saves remain; unfinished work was not marked complete." }
            catch { errorMessage = error.localizedDescription }
        }
    }
    func cancelOperation() { operation?.cancel() }

    func convertTable(documentID: UUID, selection: SourceSelection, completion: @escaping (SourceAsset) -> Void) {
        guard let project = current, let document = project.documents.first(where: { $0.id == documentID }), let region = selection.region else { return }
        perform("Transcribing selected table…") {
            let url = try await self.repository.documentURL(document, projectID: project.id)
            let png = try await RegionExport.image(url: url, pageNumber: selection.page, region: region)
            let image = try RegionExport.jpeg(png, page: selection.page)
            let response = try await self.transcribeSourceTable(image: image)
            guard !response.columns.isEmpty else { throw WorkbenchError.invalid("No readable table was returned for this box. Include the complete table, headers and footnotes, then try again.") }
            let table = EditableTable(title: response.title, columns: response.columns, rows: response.rows.map(\.cells), footnotes: response.footnotes, warnings: response.warnings, sourceFilename: document.filename, sourceSHA256: document.sha256, page: selection.page, region: region)
            try table.validate()
            let asset = SourceAsset(documentID: document.id, sourceSHA256: document.sha256, page: selection.page, kind: .table, label: "Boxed table \(table.id.uuidString.prefix(8))", title: table.title, region: region, exactCrop: true, table: table, origin: "Reviewer box")
            try await self.mutate(project.id) { latest in
                latest.assets = SourceAsset.merge(existing: latest.assets ?? [], incoming: [asset])
                latest.audit.append(.init(actor: latest.plan.reviewer, action: "Editable table prepared for review", detail: "\(document.filename), page \(selection.page), \(table.rows.count) rows × \(table.columns.count) columns. Saved in Tables & images, not applied to extracted observations."))
            }
            completion(asset)
        }
    }

    private func transcribeSourceTable(image: PageImage, title: String = "") async throws -> ModelTableReply {
        if UserDefaults.standard.bool(forKey: "localPaddleTables") {
            return try await localTableOCR.transcribe(image: image, title: title, endpoint: UserDefaults.standard.string(forKey: "localPaddleEndpoint") ?? "http://127.0.0.1:8766/table", token: KeychainStore.read(provider: "paddle"))
        }
        if UserDefaults.standard.bool(forKey: "huggingFaceTableConsent") {
            do { return try await tableOCR.transcribe(image: image, title: title, token: KeychainStore.read(provider: "huggingface")) }
            catch is CancellationError { throw CancellationError() }
            catch {
                guard UserDefaults.standard.bool(forKey: "tableOCRAllowOpenAIFallback") else { throw error }
                var result = try await client.transcribeTable(image: image, model: extractionModel, apiKey: credential(), targetTitle: title)
                result.warnings.append("GLM-OCR unavailable. This table was transcribed by the explicitly enabled OpenAI fallback, not GLM-OCR.")
                return result
            }
        }
        return try await client.transcribeTable(image: image, model: extractionModel, apiKey: credential(), targetTitle: title)
    }

    private func credential() throws -> String {
        guard cloud.isEnabled() else { throw WorkbenchError.invalid("Enable cloud AI in Settings to send selected document text or research questions to OpenAI. Offline planning, manual extraction and export work without it.") }
        let key = try cloud.apiKey()
        guard !key.isEmpty else { throw WorkbenchError.missingKey }
        return key
    }

    @discardableResult private func mutate(_ id: UUID, _ edit: @escaping @MainActor (inout ReviewProject) throws -> Void) async throws -> ReviewProject {
        let previous = saveTail
        let write = Task { @MainActor () throws -> ReviewProject in
            await previous?.value
            guard var project = self.projects.first(where: { $0.id == id }) else { throw WorkbenchError.invalid("The selected project is no longer open.") }
            try edit(&project)
            let saved = try await self.repository.save(project)
            if let index = self.projects.firstIndex(where: { $0.id == id }) { self.projects[index] = saved }
            return saved
        }
        saveTail = Task { _ = try? await write.value }
        return try await write.value
    }

    func newProject() {
        perform("Creating review…") {
            var project = ReviewProject(title: "New review \(self.projects.count + 1)")
            project.plan.reviewer = UserDefaults.standard.string(forKey: "reviewerName") ?? ""
            project.messages = [.init(role: "assistant", text: "Start with your question, a PROSPERO or other protocol, or a PICOTT. Describe custom variables here, or select Deep research for a sourced planning brief. Review and apply proposals, then approve the extraction plan before importing articles.")]
            let saved = try await self.repository.save(project)
            self.projects.insert(saved, at: 0); self.selectedProjectID = saved.id
        }
    }

    func savePlan(projectID: UUID, title: String, plan: ReviewPlan, approve: Bool) {
        perform(approve ? "Approving plan…" : "Saving plan…") {
            try await self.mutate(projectID) { project in
                guard project.plan.approvedAt == nil else { throw WorkbenchError.invalid("Create a documented amendment before changing an approved plan.") }
                guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WorkbenchError.invalid("Give this review a title.") }
                if approve, !plan.validationMessages.isEmpty { throw WorkbenchError.invalid(plan.validationMessages.joined(separator: "\n")) }
                var saved = plan; saved.version = project.plan.version
                saved.approvedAt = approve ? Date() : nil; saved.approvedBy = approve ? plan.reviewer : nil
                project.plan = saved; project.title = title
                project.audit.append(.init(actor: plan.reviewer.isEmpty ? "User" : plan.reviewer, action: approve ? "Extraction plan approved" : "Draft plan saved", detail: "Version \(saved.version); \(saved.variables.count) variables. Approval concerns the plan, not article-level facts."))
            }
            self.notice = approve ? "Plan approved. Article import is now available." : "Draft saved."
        }
    }

    func amendPlan(projectID: UUID, reason: String) {
        perform("Opening amendment…") {
            guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WorkbenchError.invalid("Describe why the prespecified plan is changing.") }
            try await self.mutate(projectID) { project in
                guard project.plan.approvedAt != nil else { return }
                project.planHistory.append(.init(date: Date(), reason: reason, plan: project.plan))
                project.plan.version += 1; project.plan.approvedAt = nil; project.plan.approvedBy = nil
                project.audit.append(.init(actor: project.plan.reviewer, action: "Plan amendment started", detail: reason + ". Existing observations retain their original plan version and are excluded from the current verified-only export until rechecked."))
            }
        }
    }

    func importDocuments(_ urls: [URL], protocolOnly: Bool) {
        guard let selected = current else { return }
        let id = selected.id
        perform(protocolOnly ? "Reading protocol…" : "Importing articles…") {
            if !protocolOnly, !selected.plan.readyForArticles { throw WorkbenchError.invalid("Approve the PICOTT and extraction plan before importing articles.") }
            for (index, url) in urls.enumerated() {
                try Task.checkCancellation()
                self.progress = "Reading \(index + 1)/\(urls.count): \(url.lastPathComponent) · local OCR for scanned pages"
                let loaded = try await DocumentLoader.load(url, ocr: true, allowImageOnlyPDF: !protocolOnly)
                try Task.checkCancellation()
                let installed = try await self.repository.installDocument(data: loaded.data, extension: url.pathExtension, projectID: id)
                let document = SourceDocument(filename: url.lastPathComponent, relativePath: installed.path, sha256: installed.hash, pages: loaded.pages, warnings: loaded.warnings)
                try await self.mutate(id) { project in
                    if !protocolOnly, !project.plan.readyForArticles { throw WorkbenchError.invalid("The extraction plan is no longer approved.") }
                    guard !(project.documents + project.protocols).contains(where: { $0.sha256 == installed.hash }) else { throw WorkbenchError.invalid("This exact document is already in the review: \(url.lastPathComponent).") }
                    if protocolOnly { project.protocols.append(document) } else { project.documents.append(document) }
                    project.audit.append(.init(actor: project.plan.reviewer, action: protocolOnly ? "Protocol imported" : "Article imported", detail: "\(document.filename); SHA-256 \(document.sha256); \(document.pages.count) pages. Peer-review status remains unconfirmed."))
                }
            }
            self.notice = "Imported \(urls.count) document(s). Source files and page text are saved with this review."
        }
    }

    func extract(documentID: UUID, automaticReview: Bool? = nil) {
        guard let project = current, let document = project.documents.first(where: { $0.id == documentID }) else { return }
        perform("Preparing extraction…") {
            let visual = UserDefaults.standard.object(forKey: "visualExtraction") as? Bool ?? true
            guard project.plan.readyForArticles, document.hasText || (visual && document.relativePath.lowercased().hasSuffix(".pdf")) else { throw WorkbenchError.invalid("Approve the plan and import a readable article. PDFs without text require visual extraction to be enabled.") }
            let sourceURL = try await self.repository.documentURL(document, projectID: project.id)
            let key = try self.credential(); let model = self.extractionModel
            let chunks = ReviewEngine.extractionChunks(document.pages).flatMap { chunk in
                stride(from: 0, to: chunk.count, by: 3).map { Array(chunk[$0..<min($0 + 3, chunk.count)]) }
            }
            let automatic = automaticReview ?? UserDefaults.standard.bool(forKey: "automaticReview")
            let variables = project.plan.variables
            var staged: [Observation] = []
            let batches = stride(from: 0, to: variables.count, by: 12).map { Array(variables[$0..<min($0 + 12, variables.count)]) }
            var completed = 0
            for pages in chunks {
                let images = visual && sourceURL.pathExtension.lowercased() == "pdf" ? try await PDFPageImages.render(url: sourceURL, pageNumbers: pages.map(\.number)) : []
                for fields in batches {
                    try Task.checkCancellation()
                    self.progress = "Extracting \(completed + 1)/\(chunks.count * batches.count) · \(document.filename)"
                    let result = try await self.client.extract(pages: pages, variables: fields, plan: project.plan, model: model, apiKey: key, pageImages: images)
                    // Absence in one chunk is not absence from the full report.
                    for row in result.observations where row.missingness != .notReported {
                        guard let field = fields.first(where: { $0.id == row.variable_id }) else { throw WorkbenchError.invalid("The model returned a field outside the requested batch.") }
                        let citation = row.quote.isEmpty ? [] : [EvidenceCitation(page: row.page, quote: row.quote)]
                        let observation = Observation(documentID: document.id, variableID: row.variable_id, value: row.value, missingness: row.missingness, context: .init(arm: row.arm, comparator: row.comparator, outcome: row.outcome, timepoint: row.timepoint, subgroup: row.subgroup, analysis: row.analysis), citations: citation, confidence: row.confidence, note: row.note, model: model, planVersion: project.plan.version)
                        staged.append(try ReviewEngine.reviewableSuggestion(observation, variable: field, document: document))
                    }
                    completed += 1
                }
            }
            try Task.checkCancellation()
            var consolidated = ReviewEngine.consolidate(staged)
            consolidated = try await self.checkedSuggestions(consolidated, document: document, project: project, sourceURL: sourceURL, key: key)
            let incomplete = document.pages.contains { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            consolidated += ReviewEngine.absenceSuggestions(variables: variables, consolidated: consolidated, existing: self.current?.observations ?? project.observations, documentID: document.id, pagesIncomplete: incomplete, model: model, planVersion: project.plan.version)
            if automatic {
                consolidated = consolidated.map { row in
                    guard let field = variables.first(where: { $0.id == row.variableID }) else { return row }
                    return AutomationPolicy.review(row, variable: field, document: document)
                }
            }
            let incoming = consolidated
            try await self.mutate(project.id) { latest in
                guard latest.plan.readyForArticles, latest.plan.version == project.plan.version else { throw WorkbenchError.invalid("The plan changed during extraction. The staged results were discarded.") }
                let merged = ReviewEngine.mergeSuggestions(existing: latest.observations, incoming: incoming, documentID: document.id, planVersion: project.plan.version)
                let accepted = merged.filter { row in incoming.contains { $0.id == row.id } }.count
                latest.observations = merged
                let supported = incoming.filter { $0.sourceCheck?.verdict == .supported }.count
                let contradicted = incoming.filter { $0.sourceCheck?.verdict == .contradicted }.count
                latest.audit.append(.init(actor: latest.plan.reviewer, action: "AI extraction staged for review", detail: "\(document.filename); \(accepted) suggestions saved; \(incoming.count - accepted) skipped to protect reviewed/edited/rejected rows; visual pages: \(visual); extraction model \(model), source-check model \(self.sourceCheckModel)\(model == self.sourceCheckModel ? " (same model as the extractor; agreement is correlated)" : ""), plan v\(project.plan.version). Separate source checks: \(supported) supported, \(contradicted) contradicted. Model support is not human verification."))
            }
            self.notice = automatic ? "Automatic review complete. AI-reviewed rows remain separate from human verification." : "Extraction saved as suggestions. Human verification is required."
            var assetWarning: String?
            let includeAssets = UserDefaults.standard.object(forKey: "extractAssets") as? Bool ?? true
            if includeAssets && visual && sourceURL.pathExtension.lowercased() == "pdf" {
                do {
                    try await self.prepareAssets(document: document, project: project, url: sourceURL, key: key)
                    self.notice = "Data suggestions and Tables & images saved. Check source-check disagreements and review each item before reuse."
                } catch is CancellationError { throw CancellationError() }
                catch { assetWarning = "Tables & images did not finish: " + error.localizedDescription; self.notice = assetWarning }
            }
            if automatic { try await self.exportAutomaticReview(projectID: project.id, documentID: document.id, warnings: assetWarning.map { [$0] } ?? []) }
        }
    }

    /// Runs the separate source-check pass. During a bulk extraction a failed batch is recorded as `unclear` so the run can
    /// finish; for a single reviewer-requested check (`tolerateFailures == false`) the error is thrown instead, because a
    /// failed request is not a verdict.
    private func checkedSuggestions(_ rows: [Observation], document: SourceDocument, project: ReviewProject, sourceURL: URL, key: String, tolerateFailures: Bool = true) async throws -> [Observation] {
        var result = rows
        let groups = Dictionary(grouping: rows.indices.filter { rows[$0].missingness == .reported }, by: { rows[$0].citations.first?.page ?? 0 })
        for page in groups.keys.sorted() {
            guard let indices = groups[page] else { continue }
            for start in stride(from: 0, to: indices.count, by: 8) {
                let selected = Array(indices[start..<min(start + 8, indices.count)])
                do {
                    try Task.checkCancellation()
                    guard page > 0 else { throw WorkbenchError.invalid("No cited source page was supplied.") }
                    let pages = document.pages.filter { abs($0.number - page) <= 1 }
                    let visual = UserDefaults.standard.object(forKey: "visualExtraction") as? Bool ?? true
                    let images = visual && sourceURL.pathExtension.lowercased() == "pdf" ? try await PDFPageImages.render(url: sourceURL, pageNumbers: pages.map(\.number)) : []
                    self.progress = "Checking source claims · \(document.filename) · page \(page)"
                    let checks = try await client.checkSources(observations: selected.map { result[$0] }, variables: project.plan.variables, pages: pages, images: images, model: sourceCheckModel, apiKey: key)
                    for index in selected {
                        guard let check = checks.checks.first(where: { $0.observation_id == result[index].id }) else { continue }
                        result[index].sourceCheck = .init(verdict: check.verdict, reason: check.reason, quote: check.source_quote, model: sourceCheckModel, claimFingerprint: SourceCheckPolicy.fingerprint(result[index]), sourceFingerprint: project.plan.variables.first(where: { $0.id == result[index].variableID }).map { SourceCheckPolicy.checkFingerprint(result[index], variable: $0, document: document) })
                    }
                } catch {
                    guard tolerateFailures else { throw error }
                    for index in selected {
                        result[index].sourceCheck = .init(verdict: .unclear, reason: error is CancellationError ? "Source checking cancelled." : "Source check could not complete: " + error.localizedDescription, model: sourceCheckModel, claimFingerprint: SourceCheckPolicy.fingerprint(result[index]), sourceFingerprint: project.plan.variables.first(where: { $0.id == result[index].variableID }).map { SourceCheckPolicy.checkFingerprint(result[index], variable: $0, document: document) })
                    }
                }
            }
        }
        return result
    }

    /// Records a fresh AI verdict on one saved claim. The verdict informs the reviewer: it never changes review status,
    /// reviewer, adjudication text or plan version. Verified-only export already excludes unresolved AI claims.
    func checkObservation(_ observation: Observation) {
        guard let project = current, let document = project.documents.first(where: { $0.id == observation.documentID }) else { return }
        perform("Checking the selected claim against its original source…") {
            let key = try self.credential(); let url = try await self.repository.documentURL(document, projectID: project.id)
            let checked = try await self.checkedSuggestions([observation], document: document, project: project, sourceURL: url, key: key, tolerateFailures: false)[0]
            guard let verdict = checked.sourceCheck else { throw WorkbenchError.invalid("The source checker returned no verdict for this claim.") }
            try await self.mutate(project.id) { latest in
                guard let index = latest.observations.firstIndex(where: { $0.id == observation.id }), SourceCheckPolicy.fingerprint(latest.observations[index]) == SourceCheckPolicy.fingerprint(observation) else { throw WorkbenchError.invalid("The claim changed while its source was checked. Check the saved value again.") }
                let previous = latest.observations[index]
                latest.observations[index].sourceCheck = verdict
                latest.observations[index].updatedAt = Date()
                latest.audit.append(.init(actor: latest.plan.reviewer, action: "Independent AI source check", detail: "\(observation.id): \(verdict.verdict.rawValue) by \(verdict.model). Review status \(previous.status.rawValue), plan v\(previous.planVersion) and reviewer adjudication (\(previous.sourceAdjudication == nil ? "none" : "retained")) unchanged. AI support is not human verification; unresolved claims stay out of the verified export."))
            }
        }
    }

    func findAssets(documentID: UUID) {
        guard let project = current, project.plan.readyForArticles, let document = project.documents.first(where: { $0.id == documentID }) else { return }
        perform("Finding tables and images…") {
            let url = try await self.repository.documentURL(document, projectID: project.id)
            guard url.pathExtension.lowercased() == "pdf" else { throw WorkbenchError.invalid("Automatic table/image discovery currently requires a PDF source.") }
            try await self.prepareAssets(document: document, project: project, url: url, key: self.credential())
            self.notice = "Tables & images updated. AI detections and transcriptions require review."
        }
    }

    private func prepareAssets(document: SourceDocument, project: ReviewProject, url: URL, key: String) async throws {
        let pages = document.pages.map(\.number)
        for start in stride(from: 0, to: pages.count, by: 3) {
            try Task.checkCancellation()
            let numbers = Array(pages[start..<min(start + 3, pages.count)])
            progress = "Finding tables and images · \(document.filename) · pages \(numbers.map(String.init).joined(separator: ", "))"
            let images = try await PDFPageImages.render(url: url, pageNumbers: numbers)
            let discovery = try await client.discoverAssets(images: images, model: extractionModel, apiKey: key)
            for item in discovery.assets {
                try Task.checkCancellation()
                var asset = SourceAsset(documentID: document.id, sourceSHA256: document.sha256, page: item.page, kind: item.kind, label: item.label, title: item.title, caption: item.caption, warnings: item.warnings)
                try asset.validate(document: document)
                let existing = current?.assets?.first { $0.sourceKey == asset.sourceKey }
                if existing?.reviewedAt != nil || existing?.origin == "Reviewer box" { continue }
                if item.kind == .table {
                    progress = "Transcribing \(item.label) · \(document.filename) · page \(item.page)"
                    do {
                        guard var image = images.first(where: { $0.page == item.page }) else { throw WorkbenchError.invalid("The table source image is unavailable.") }
                        if UserDefaults.standard.bool(forKey: "huggingFaceTableConsent") || UserDefaults.standard.bool(forKey: "localPaddleTables") {
                            asset.region = try TablePageCropper.region(url: url, pageNumber: item.page, label: item.label)
                            let png = try await RegionExport.image(url: url, pageNumber: item.page, region: asset.region)
                            image = try RegionExport.jpeg(png, page: item.page)
                            asset.warnings.append("Specialist OCR input is a provisional caption-bounded region, not a precise verified crop; inspect original headers and footnotes.")
                        }
                        let reply = try await transcribeSourceTable(image: image, title: item.label + ": " + item.title)
                        asset.table = .init(title: reply.title, columns: reply.columns, rows: reply.rows.map(\.cells), footnotes: reply.footnotes, warnings: reply.warnings, sourceFilename: document.filename, sourceSHA256: document.sha256, page: item.page, region: asset.region)
                        try asset.validate(document: document)
                    } catch is CancellationError { throw CancellationError() }
                    catch { asset.table = nil; asset.warnings.append("Table transcription did not complete: " + error.localizedDescription) }
                }
                let savedAsset = asset
                try await mutate(project.id) { latest in
                    guard (latest.assets ?? []).filter({ $0.documentID == document.id }).count < 400 || (latest.assets ?? []).contains(where: { $0.sourceKey == savedAsset.sourceKey }) else { throw WorkbenchError.invalid("This report reached the 400-asset limit; later items were not added.") }
                    latest.assets = SourceAsset.merge(existing: latest.assets ?? [], incoming: [savedAsset])
                    latest.audit.append(.init(actor: latest.plan.reviewer, action: "Source asset prepared", detail: "\(document.filename), page \(savedAsset.page), \(savedAsset.label). Full-page source, AI draft; no precise crop or scientific verification claimed."))
                }
            }
        }
    }

    /// Automatic mode prepares a complete, explicitly AI-labeled handoff without a save dialog or human verification claim.
    private func exportAutomaticReview(projectID: UUID, documentID: UUID, warnings: [String]) async throws {
        guard let project = projects.first(where: { $0.id == projectID }), let document = project.documents.first(where: { $0.id == documentID }) else { return }
        let source = try await repository.documentURL(document, projectID: project.id)
        let folder = try await repository.automationDirectory(projectID: project.id)
        var report = project; report.observations = project.observations.filter { $0.documentID == documentID }
        try Data(DatasetExporter.longCSV(report, verifiedOnly: false).utf8).write(to: folder.appendingPathComponent("all-observations.csv"), options: .atomic)
        try Data(DatasetExporter.longCSV(report, verifiedOnly: false, aiReviewedOnly: true).utf8).write(to: folder.appendingPathComponent("ai-reviewed.csv"), options: .atomic)
        var items: [[String: String]] = []
        for asset in project.assets ?? [] where asset.documentID == documentID && asset.excluded != true {
            try Task.checkCancellation()
            let name = asset.id.uuidString
            let image = try await RegionExport.image(url: source, pageNumber: asset.page, region: asset.exactCrop ? asset.region : nil)
            try image.write(to: folder.appendingPathComponent(name + ".png"), options: .atomic)
            if let table = asset.table {
                try Data(table.html.utf8).write(to: folder.appendingPathComponent(name + ".html"), options: .atomic)
                try Data(table.csv.utf8).write(to: folder.appendingPathComponent(name + ".csv"), options: .atomic)
            }
            items.append(["id":name,"label":asset.label,"page":String(asset.page),"preview":asset.exactCrop ? "reviewer crop" : "full page, not precise crop"])
        }
        let accepted = report.observations.filter { VerificationPolicy.exportable($0, project: report, automated: true) }.count
        let manifest: [String: Any] = ["mode":"automatic AI review, not human verification", "source":document.filename,"source_sha256":document.sha256,"plan_version":project.plan.version,"ai_reviewed":accepted,"total_observations":report.observations.count,"assets":items,"warnings":warnings,"limitations":"AI acceptance can be wrong. Unanchored image/OCR evidence and unresolved claims stay in all-observations.csv; full-page previews are not precise figure crops."]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted,.sortedKeys]).write(to: folder.appendingPathComponent("manifest.json"), options: .atomic)
        try await mutate(project.id) { $0.audit.append(.init(actor: "AI automation", action: "Automatic review exported", detail: folder.path + "; AI reviewed, not human verified.")) }
        notice = "Automatic output prepared: " + folder.path + ". AI-reviewed and unresolved rows are labeled separately." + (warnings.isEmpty ? "" : " Some assets did not finish; see manifest warnings.")
    }

    func saveAsset(_ asset: SourceAsset, reviewed: Bool = false) {
        guard let project = current, let document = project.documents.first(where: { $0.id == asset.documentID }) else { return }
        perform("Saving table/image…") {
            _ = try await self.repository.documentURL(document, projectID: project.id)
            try asset.validate(document: document)
            try await self.mutate(project.id) { latest in
                var value = asset
                if reviewed { value.reviewedAt = Date(); value.reviewedBy = latest.plan.reviewer }
                else { value.reviewedAt = nil; value.reviewedBy = nil }
                if let index = latest.assets?.firstIndex(where: { $0.id == asset.id }) { latest.assets?[index] = value }
                else { latest.assets = (latest.assets ?? []) + [value] }
                latest.audit.append(.init(actor: latest.plan.reviewer, action: reviewed ? "Source asset reviewed" : "Source asset saved", detail: "\(value.label), page \(value.page). This does not verify dataset observations."))
            }
            self.notice = "Table/image saved in Tables & images."
        }
    }

    func transcribeAsset(_ asset: SourceAsset) {
        guard let project = current, let document = project.documents.first(where: { $0.id == asset.documentID }) else { return }
        perform("Transcribing the selected source table…") {
            try asset.validate(document: document)
            let url = try await self.repository.documentURL(document, projectID: project.id)
            let region = (UserDefaults.standard.bool(forKey: "huggingFaceTableConsent") || UserDefaults.standard.bool(forKey: "localPaddleTables")) && !asset.exactCrop ? try TablePageCropper.region(url: url, pageNumber: asset.page, label: asset.label) : asset.region
            let png = try await RegionExport.image(url: url, pageNumber: asset.page, region: region)
            let reply = try await self.transcribeSourceTable(image: RegionExport.jpeg(png, page: asset.page), title: asset.label + ": " + asset.title)
            var updated = asset; updated.region = region
            updated.table = .init(title: reply.title, columns: reply.columns, rows: reply.rows.map(\.cells), footnotes: reply.footnotes, warnings: reply.warnings, sourceFilename: document.filename, sourceSHA256: document.sha256, page: asset.page, region: region)
            updated.reviewedAt = nil; updated.reviewedBy = nil
            try updated.validate(document: document)
            let result = updated
            try await self.mutate(project.id) { latest in
                guard let index = latest.assets?.firstIndex(where: { $0.id == asset.id }) else { throw WorkbenchError.invalid("This source asset is no longer saved.") }
                latest.assets?[index] = result
                latest.audit.append(.init(actor: latest.plan.reviewer, action: "Table transcription refreshed", detail: "\(asset.label), page \(asset.page), requires cell review."))
            }
            self.notice = "Editable table saved. Open it to review cells and export."
        }
    }

    func saveObservation(_ observation: Observation, verify: Bool) {
        guard let project = current else { return }
        perform(verify ? "Verifying observation…" : "Saving observation…") {
            if verify || observation.citations.contains(where: { $0.region != nil }) {
                guard let source = project.documents.first(where: { $0.id == observation.documentID }) else { throw WorkbenchError.invalid("The source report no longer exists.") }
                let sourceURL = try await self.repository.documentURL(source, projectID: project.id)
                guard !observation.citations.contains(where: { $0.region != nil }) || sourceURL.pathExtension.lowercased() == "pdf" else { throw WorkbenchError.invalid("Image regions require an original PDF source.") }
            }
            try await self.mutate(project.id) { latest in
                guard let variable = latest.plan.variables.first(where: { $0.id == observation.variableID }), let document = latest.documents.first(where: { $0.id == observation.documentID }) else { throw WorkbenchError.invalid("The variable or source report no longer exists.") }
                guard latest.plan.readyForArticles else { throw WorkbenchError.invalid("Approve the plan amendment before saving article data.") }
                try ReviewEngine.validateObservationValue(observation, variable: variable)
                let old = latest.observations.first { $0.id == observation.id }
                var edited = observation
                if let old, old.planVersion != latest.plan.version {
                    edited.sourceCheck = nil
                    if edited.sourceAdjudication == old.sourceAdjudication { edited.sourceAdjudication = nil }
                }
                if let old, old.value != observation.value || old.context != observation.context || old.missingness != observation.missingness {
                    // Explicitly reattached quotation in the editor may be kept, but must be checked again.
                    edited.status = .edited; edited.confidence = nil; edited.reviewer = ""
                }
                edited.planVersion = latest.plan.version; edited.updatedAt = Date()
                if verify { edited = try ReviewEngine.verify(edited, variable: variable, reviewer: latest.plan.reviewer, document: document) }
                else if edited.status != .rejected { edited.status = .edited; edited.reviewer = ""; edited.verificationFingerprint = nil }
                if let index = latest.observations.firstIndex(where: { $0.id == edited.id }) { latest.observations[index] = edited }
                else { latest.observations.append(edited) }
                let before = old.map { "Before: \($0.value) [\($0.missingness.rawValue), \($0.status.rawValue)], context: \($0.context.summary), citations: \($0.citations.map(\.quote).joined(separator: " | ")). " } ?? "New observation. "
                latest.audit.append(.init(actor: latest.plan.reviewer, action: verify ? "Observation verified" : "Observation edited", detail: "\(edited.id): \(variable.label). \(before)After: \(edited.value) [\(edited.missingness.rawValue), \(edited.status.rawValue)], context: \(edited.context.summary), citations: \(edited.citations.map(\.quote).joined(separator: " | ")), note: \(edited.note). Plan v\(edited.planVersion)."))
            }
            self.notice = verify ? "Observation verified and saved." : "Edited observation saved; verification is pending."
        }
    }

    func rejectObservation(_ id: UUID) {
        guard let project = current else { return }
        perform("Rejecting suggestion…") {
            try await self.mutate(project.id) { latest in
                guard let index = latest.observations.firstIndex(where: { $0.id == id }) else { return }
                latest.observations[index].status = .rejected; latest.observations[index].reviewer = latest.plan.reviewer; latest.observations[index].updatedAt = Date()
                latest.audit.append(.init(actor: latest.plan.reviewer, action: "Observation rejected", detail: id.uuidString))
            }
        }
    }

    func updateReport(_ document: SourceDocument) {
        guard let project = current else { return }
        perform("Saving report metadata…") {
            try await self.mutate(project.id) { latest in
                guard let index = latest.documents.firstIndex(where: { $0.id == document.id }) else { return }
                latest.documents[index].studyID = document.studyID; latest.documents[index].peerReviewStatus = document.peerReviewStatus
                latest.audit.append(.init(actor: latest.plan.reviewer, action: "Report linkage / peer-review status updated", detail: "\(document.filename): study \(document.studyID); \(document.peerReviewStatus). This is a reviewer declaration, not an automated publisher check."))
            }
        }
    }

    func askAgent(_ question: String, deepResearch: Bool) {
        guard let project = current, !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        perform(deepResearch ? "Starting sourced research…" : "Preparing planning suggestions…") {
            let key = try self.credential()
            let updated = try await self.mutate(project.id) { $0.messages.append(.init(role: "user", text: question)) }
            if deepResearch {
                guard updated.researchJob == nil else { throw WorkbenchError.invalid("This review already has a research job. Resume or cancel it first.") }
                let job: ResearchJob
                do { job = try await self.client.startResearch(project: updated, question: question, model: self.researchModel, apiKey: key) }
                catch {
                    // Leave the chat self-explanatory instead of an unanswered user turn.
                    _ = try? await self.mutate(project.id) { $0.messages.append(.init(role: "assistant", text: "Deep research could not start: \(error.localizedDescription) No job was created and no variables were proposed.")) }
                    throw error
                }
                do {
                    try await self.mutate(project.id) { latest in
                        latest.researchJob = job
                        latest.audit.append(.init(actor: latest.plan.reviewer, action: "Deep research started", detail: "Model \(job.model); response \(job.responseID). Research uses web search and OpenAI background storage."))
                    }
                } catch { try? await self.client.cancelResearch(job, apiKey: key); throw error }
                self.resumeResearch(projectID: project.id)
            } else {
                let reply = try await self.client.planReply(project: updated, question: question, model: self.extractionModel, apiKey: key)
                try await self.recordReply(reply, projectID: project.id, sources: [])
            }
        }
    }

    private func recordReply(_ reply: ModelAgentReply, projectID: UUID, sources: [ResearchSource]) async throws {
        try await mutate(projectID) { latest in
            latest.messages.append(.init(role: "assistant", text: reply.reply, sources: sources))
            let p = reply.picott
            let hasPICOTT = [p.population, p.intervention, p.comparator, p.outcomes, p.timing, p.studyTypes].contains { !$0.isEmpty }
            if !reply.variables.isEmpty || hasPICOTT {
                guard reply.variables.count <= 100, reply.variables.allSatisfy({ !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.definition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw WorkbenchError.invalid("The proposed variable list was invalid or too large.") }
                latest.proposals.append(.init(summary: reply.reply, variables: reply.variables.map(\.variable), picott: hasPICOTT ? p : nil, sources: sources))
            }
        }
    }

    func applyProposal(_ proposalID: UUID, variableIDs: Set<String>, applyPICOTT: Bool) {
        guard let project = current else { return }
        perform("Applying selected proposal…") {
            try await self.mutate(project.id) { latest in
                guard latest.plan.approvedAt == nil else { throw WorkbenchError.invalid("Create a documented amendment before applying changes to an approved plan.") }
                guard let proposal = latest.proposals.first(where: { $0.id == proposalID }) else { return }
                let existing = Set(latest.plan.variables.map { $0.label.lowercased() })
                var labels = existing
                for variable in proposal.variables where variableIDs.contains(variable.id) {
                    if labels.insert(variable.label.lowercased()).inserted { latest.plan.variables.append(variable) }
                }
                if applyPICOTT, let p = proposal.picott {
                    if !p.population.isEmpty { latest.plan.picott.population = p.population }
                    if !p.intervention.isEmpty { latest.plan.picott.intervention = p.intervention }
                    if !p.comparator.isEmpty { latest.plan.picott.comparator = p.comparator }
                    if !p.outcomes.isEmpty { latest.plan.picott.outcomes = p.outcomes }
                    if !p.timing.isEmpty { latest.plan.picott.timing = p.timing }
                    if !p.studyTypes.isEmpty { latest.plan.picott.studyTypes = p.studyTypes }
                }
                latest.proposals.removeAll { $0.id == proposalID }
                latest.audit.append(.init(actor: latest.plan.reviewer, action: "Agent proposal applied to draft", detail: "\(variableIDs.count) variables selected; PICOTT selected: \(applyPICOTT). Plan still requires approval."))
            }
        }
    }

    func dismissProposal(_ proposalID: UUID) {
        guard let id = current?.id else { return }
        perform("Dismissing proposal…") { try await self.mutate(id) { $0.proposals.removeAll { $0.id == proposalID }; $0.audit.append(.init(actor: $0.plan.reviewer, action: "Agent proposal dismissed", detail: proposalID.uuidString)) } }
    }

    func resumeResearch(projectID: UUID) {
        guard researchTasks[projectID] == nil, let job = projects.first(where: { $0.id == projectID })?.researchJob else { return }
        activeResearch.insert(projectID)
        researchTasks[projectID] = Task {
            defer { researchTasks[projectID] = nil; activeResearch.remove(projectID) }
            do {
                let key = try credential()
                for _ in 0..<360 {
                    try Task.checkCancellation()
                    let response = try await client.pollResearch(job, apiKey: key)
                    switch response.status {
                    case "completed":
                        guard !response.text.isEmpty else { throw WorkbenchError.invalid("The research job finished without a report.") }
                        let updated = try await mutate(projectID) { latest in
                            latest.messages.append(.init(role: "assistant", text: response.text, sources: response.sources)); latest.researchJob = nil
                            latest.audit.append(.init(actor: latest.plan.reviewer, action: "Deep research completed", detail: "\(job.responseID); \(response.sources.count) cited sources. Suggestions require review."))
                        }
                        let reply = try await client.planReply(project: updated, question: "Turn the completed research brief into proposed extraction variables. Preserve unresolved questions.", research: response.text, model: extractionModel, apiKey: key)
                        try await recordReply(reply, projectID: projectID, sources: response.sources)
                        notice = "Research brief saved. Review its sources and proposed fields."
                        return
                    case "failed", "cancelled", "incomplete":
                        try await mutate(projectID) { latest in
                            latest.researchJob = nil; latest.audit.append(.init(actor: latest.plan.reviewer, action: "Research ended without a complete report", detail: response.status ?? "unknown"))
                        }
                        throw WorkbenchError.invalid("Research ended with status \(response.status ?? "unknown"). No variables were applied.")
                    default: try await Task.sleep(nanoseconds: 5_000_000_000)
                    }
                }
                notice = "Research is still running. Polling paused after 30 minutes; use Resume to check again."
            } catch is CancellationError { /* Job remains persisted until server cancellation succeeds. */ }
            catch { errorMessage = error.localizedDescription + " If a research job remains listed, Resume checks it without starting a new one." }
        }
    }

    func cancelResearch(projectID: UUID) {
        guard let job = projects.first(where: { $0.id == projectID })?.researchJob else { return }
        researchTasks[projectID]?.cancel()
        perform("Cancelling cloud research…") {
            let key = try self.credential(); try await self.client.cancelResearch(job, apiKey: key)
            try await self.mutate(projectID) { latest in latest.researchJob = nil; latest.audit.append(.init(actor: latest.plan.reviewer, action: "Research cancellation acknowledged", detail: job.responseID)) }
        }
    }

    func exportCSV(to url: URL, verifiedOnly: Bool) {
        guard let project = current else { return }
        perform("Exporting dataset…") {
            for document in project.documents { _ = try await self.repository.documentURL(document, projectID: project.id) }
            let csv = DatasetExporter.longCSV(project, verifiedOnly: verifiedOnly)
            try Data(csv.utf8).write(to: url, options: .atomic)
            self.notice = verifiedOnly ? "Exported current-plan verified observations." : "Exported all observations with review status, provenance and plan version."
        }
    }
    func exportBackup(to url: URL) {
        guard let project = current else { return }
        perform("Backing up project and sources…") {
            try await self.repository.exportBackup(project: project, destination: url)
            self.notice = "Backup saved, including original documents, protocol, extraction plan, chat and audit history."
        }
    }
    func restoreBackup(from url: URL) {
        perform("Validating and restoring backup…") {
            let project = try await self.repository.importBackup(from: url)
            self.projects.insert(project, at: 0); self.selectedProjectID = project.id
            self.notice = "Restored as a separate review. Original source hashes were checked."
        }
    }
}
