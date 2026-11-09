import XCTest
import ReviewCore
@testable import EvidenceWorkbench

@MainActor final class AuditFixTests: XCTestCase {
    func testTextVerificationRejectsChangedOriginal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = ProjectRepository(root: root)
        var project = ReviewProject(); var plan = ReviewPlan()
        plan.researchQuestion = "Question"; plan.picott.population = "Adults"; plan.picott.intervention = "Drug"; plan.picott.comparator = "Control"; plan.picott.outcomes = "Age"; plan.picott.timing = "Baseline"; plan.picott.studyTypes = "RCT"
        plan.reviewer = "Audit"; plan.extractionProcess = "Manual"; plan.riskOfBiasTool = "RoB 2"; plan.synthesisPlan = "Narrative"; plan.approvedAt = Date(); project.plan = plan
        let installed = try await repository.installDocument(data: Data("Age 74.61".utf8), extension: "txt", projectID: project.id)
        let doc = SourceDocument(filename: "trial.txt", relativePath: installed.path, sha256: installed.hash, pages: [.init(number: 1, text: "Age 74.61")]); project.documents = [doc]
        let row = Observation(documentID: doc.id, variableID: "age_mean", value: "74.61", citations: [.init(page: 1, quote: "Age 74.61")]); project.observations = [row]
        _ = try await repository.save(project)
        let url = try await repository.documentURL(doc, projectID: project.id); try Data("Age 99.99".utf8).write(to: url)
        let store = WorkspaceStore(root: root, cloud: .init(isEnabled: { false }, apiKey: { "unused" }))
        await store.loadProjects(); store.saveObservation(row, verify: true); await store.operation?.value
        XCTAssertNotNil(store.errorMessage); XCTAssertNotEqual(store.current?.observations.first?.status, .verified)
        let target = root.appendingPathComponent("export.csv"); store.exportCSV(to: target, verifiedOnly: true); await store.operation?.value
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }
    func testFingerprintChangesWithDocumentAndPlanVersion() {
        var row = Observation(documentID: UUID(), variableID: "age_mean", value: "74.61")
        let original = SourceCheckPolicy.fingerprint(row); row.documentID = UUID()
        XCTAssertNotEqual(original, SourceCheckPolicy.fingerprint(row))
        let changed = SourceCheckPolicy.fingerprint(row); row.planVersion += 1
        XCTAssertNotEqual(changed, SourceCheckPolicy.fingerprint(row))
    }
    func testVerifiedExportRefusesPersistedStatusWithoutEvidence() {
        var project = ReviewProject(); let doc = SourceDocument(filename: "trial.txt", relativePath: "documents/trial.txt", sha256: "fixture", pages: [.init(number: 1, text: "Age 74.61")]); project.documents = [doc]
        project.observations = [Observation(documentID: doc.id, variableID: "age_mean", value: "999", status: .verified)]
        XCTAssertFalse(DatasetExporter.longCSV(project, verifiedOnly: true).contains("\"999\""))
    }
    func testAICheckerSupportAloneNeverResolvesClaim() throws {
        let doc = SourceDocument(filename: "trial.txt", relativePath: "documents/trial.txt", sha256: "fixture", pages: [.init(number: 1, text: "Control age 74.61")])
        let field = try XCTUnwrap(CoreFields.defaults.first { $0.id == "age_mean" })
        var row = Observation(documentID: doc.id, variableID: field.id, value: "74.61", citations: [.init(page: 1, quote: "Control age 74.61")], model: "extractor")
        row.sourceCheck = .init(verdict: .supported, reason: "Same-model agreement", model: "extractor", claimFingerprint: SourceCheckPolicy.fingerprint(row))
        XCTAssertFalse(SourceCheckPolicy.resolved(row))
        XCTAssertThrowsError(try ReviewEngine.verify(row, variable: field, reviewer: "Audit", document: doc))
        row.sourceAdjudication = "Checked original control column, units and baseline time point."
        let checked = try ReviewEngine.verify(row, variable: field, reviewer: "Audit", document: doc)
        var project = ReviewProject(); project.documents = [doc]; project.observations = [checked]
        XCTAssertTrue(DatasetExporter.longCSV(project, verifiedOnly: true).contains("74.61"))
    }
}
