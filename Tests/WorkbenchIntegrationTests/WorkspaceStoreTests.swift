import XCTest
import ReviewCore
@testable import EvidenceWorkbench

/// Returns one fixed HTTP response for every request.
struct ScriptedTransport: ResponsesTransport {
    var status: Int
    var body: String
    func send(_ request: URLRequest) async throws -> (Data, Int, String?) { (Data(body.utf8), status, nil) }
}

@MainActor
final class WorkspaceStoreTests: XCTestCase {
    private func tempRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("WorkspaceStoreTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func approvedPlan(version: Int) -> ReviewPlan {
        var plan = ReviewPlan()
        plan.researchQuestion = "Does the intervention change the outcome?"
        plan.picott.population = "Adults"; plan.picott.intervention = "Treatment"; plan.picott.comparator = "Usual care"
        plan.picott.outcomes = "Outcome"; plan.picott.timing = "12 months"; plan.picott.studyTypes = "Randomized trials"
        plan.reviewer = "QA"; plan.extractionProcess = "Single reviewer pilot"; plan.riskOfBiasTool = "RoB 2"; plan.synthesisPlan = "Narrative"
        plan.approvedAt = Date(); plan.approvedBy = "QA"; plan.version = version
        return plan
    }
    private func envelope(checks: [[String: Any]]) throws -> String {
        let text = String(data: try JSONSerialization.data(withJSONObject: ["checks": checks]), encoding: .utf8)!
        let object: [String: Any] = ["id": "resp_test", "status": "completed", "output": [["type": "message", "content": [["type": "output_text", "text": text]]]]]
        return String(data: try JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
    }
    private func verdict(_ value: String, for id: UUID) throws -> ScriptedTransport {
        ScriptedTransport(status: 200, body: try envelope(checks: [["observation_id": id.uuidString, "verdict": value, "reason": "Checker reason", "source_quote": "74.61"]]))
    }
    /// A saved review with one text report and one verified, adjudicated AI observation on plan version `observationVersion`.
    private func seededStore(observationID: UUID, transport: any ResponsesTransport, planVersion: Int = 1, observationVersion: Int = 1) async throws -> (WorkspaceStore, Observation) {
        let root = try tempRoot(); let repository = ProjectRepository(root: root)
        var project = ReviewProject(title: "Store test"); project.plan = approvedPlan(version: planVersion)
        let text = "Control age 74.61 years."
        let installed = try await repository.installDocument(data: Data(text.utf8), extension: "txt", projectID: project.id)
        let document = SourceDocument(filename: "trial.txt", relativePath: installed.path, sha256: installed.hash, pages: [.init(number: 1, text: text)])
        project.documents = [document]
        var row = Observation(id: observationID, documentID: document.id, variableID: "age_mean", value: "74.61", citations: [.init(page: 1, quote: text, exactMatch: true)], status: .verified, reviewer: "QA", model: "extractor", planVersion: observationVersion)
        row.sourceAdjudication = "Reviewer checked the control column of Table 1."
        project.observations = [row]
        _ = try await repository.save(project)
        let store = WorkspaceStore(root: root, client: OpenAIClient(transport: transport), cloud: CloudAccess(isEnabled: { true }, apiKey: { "test-not-a-real-key" }))
        await store.loadProjects()
        XCTAssertEqual(store.current?.id, project.id)
        return (store, row)
    }

    func testFailedRecheckLeavesVerificationAdjudicationAndVerdictUntouched() async throws {
        let id = UUID()
        let (store, row) = try await seededStore(observationID: id, transport: ScriptedTransport(status: 500, body: "server error"))
        store.checkObservation(row)
        await store.operation?.value
        let saved = try XCTUnwrap(store.current?.observations.first { $0.id == id })
        XCTAssertEqual(saved.status, .verified)
        XCTAssertEqual(saved.reviewer, "QA")
        XCTAssertEqual(saved.sourceAdjudication, row.sourceAdjudication)
        XCTAssertNil(saved.sourceCheck, "A failed request is not a verdict and must not be recorded as one.")
        XCTAssertNotNil(store.errorMessage, "The failure must be reported to the reviewer.")
    }

    func testContradictedRecheckRecordsVerdictWithoutRevokingHumanDecision() async throws {
        let id = UUID()
        let (store, row) = try await seededStore(observationID: id, transport: try verdict("contradicted", for: id))
        store.checkObservation(row)
        await store.operation?.value
        let saved = try XCTUnwrap(store.current?.observations.first { $0.id == id })
        XCTAssertEqual(saved.sourceCheck?.verdict, .contradicted)
        XCTAssertEqual(saved.status, .verified)
        XCTAssertEqual(saved.reviewer, "QA")
        XCTAssertEqual(saved.sourceAdjudication, row.sourceAdjudication)
        XCTAssertNil(store.errorMessage)
    }

    func testSupportedRecheckDoesNotMoveObservationToCurrentPlanVersion() async throws {
        let id = UUID()
        let (store, row) = try await seededStore(observationID: id, transport: try verdict("supported", for: id), planVersion: 2, observationVersion: 1)
        store.checkObservation(row)
        await store.operation?.value
        let saved = try XCTUnwrap(store.current?.observations.first { $0.id == id })
        XCTAssertEqual(saved.sourceCheck?.verdict, .supported)
        XCTAssertEqual(saved.planVersion, 1, "Only a reviewer save may move an observation to a new plan version.")
        let csv = DatasetExporter.longCSV(try XCTUnwrap(store.current), verifiedOnly: true)
        XCTAssertFalse(csv.contains("74.61"), "An AI verdict must not admit an earlier-plan row into the current verified export.")
    }

    func testFailedResearchStartLeavesAnExplanatoryAssistantMessage() async throws {
        let (store, _) = try await seededStore(observationID: UUID(), transport: ScriptedTransport(status: 500, body: "server error"))
        store.askAgent("Which outcome instruments matter?", deepResearch: true)
        await store.operation?.value
        let messages = try XCTUnwrap(store.current?.messages)
        XCTAssertEqual(messages.last?.role, "assistant")
        XCTAssertTrue(messages.last?.text.contains("could not start") == true, "The chat must record why the research did not start.")
        XCTAssertNil(store.current?.researchJob)
    }
}
