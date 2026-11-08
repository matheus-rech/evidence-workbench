import XCTest
@testable import ReviewCore

/// Project files written by earlier builds lack keys that later builds added with default values.
/// Synthesized Decodable requires every key, so these defaults must be applied explicitly on decode.
final class LegacyDecodingTests: XCTestCase {
    private let documentID = UUID()
    private var legacyProject: String {
        """
        {"id":"\(UUID().uuidString)","title":"Early review","schemaVersion":1,
         "plan":{"researchQuestion":"Q","picott":{"population":"Adults","intervention":"X","comparator":"Y","outcomes":"Z","timing":"T"},
                 "variables":[{"id":"title","label":"Article title","definition":"Full title."}],"reviewer":"QA"},
         "documents":[{"id":"\(documentID.uuidString)","filename":"a.pdf","relativePath":"documents/abc.pdf","sha256":"abc","pages":[{"number":1,"text":"Mean 68.5"}]}],
         "observations":[{"id":"\(UUID().uuidString)","documentID":"\(documentID.uuidString)","variableID":"title","value":"Study","citations":[{"page":1,"quote":"Mean 68.5"}]}],
         "messages":[{"id":"\(UUID().uuidString)","role":"assistant","text":"Welcome"}],
         "proposals":[{"id":"\(UUID().uuidString)","summary":"S","variables":[]}]}
        """
    }
    func testProjectWithoutLaterKeysDecodesWithDefaults() throws {
        let project = try JSONDecoder().decode(ReviewProject.self, from: Data(legacyProject.utf8))
        XCTAssertEqual(project.title, "Early review")
        XCTAssertEqual(project.revision, 0)
        XCTAssertEqual(project.plan.version, 1)
        XCTAssertEqual(project.plan.framework, "Non-Cochrane")
        XCTAssertEqual(project.plan.picott.studyTypes, "")
        XCTAssertNil(project.plan.approvedAt)
        XCTAssertEqual(project.plan.variables.first?.type, .text)
        XCTAssertEqual(project.plan.variables.first?.unit, "")
        XCTAssertTrue(project.planHistory.isEmpty); XCTAssertTrue(project.protocols.isEmpty); XCTAssertTrue(project.audit.isEmpty)
        XCTAssertNil(project.assets); XCTAssertNil(project.researchJob)
        let document = try XCTUnwrap(project.documents.first)
        XCTAssertEqual(document.peerReviewStatus, "Unconfirmed"); XCTAssertTrue(document.warnings.isEmpty)
        XCTAssertFalse(document.pages[0].ocr)
        let row = try XCTUnwrap(project.observations.first)
        XCTAssertEqual(row.missingness, .reported); XCTAssertEqual(row.status, .suggested); XCTAssertEqual(row.planVersion, 1)
        XCTAssertEqual(row.model, ""); XCTAssertEqual(row.reviewer, ""); XCTAssertEqual(row.note, ""); XCTAssertNil(row.confidence)
        XCTAssertEqual(row.context, ObservationContext()); XCTAssertFalse(row.citations[0].exactMatch)
        XCTAssertTrue(project.messages[0].sources.isEmpty); XCTAssertTrue(project.proposals[0].sources.isEmpty); XCTAssertNil(project.proposals[0].picott)
    }
    func testDecodingStillRequiresIdentityKeys() {
        XCTAssertThrowsError(try JSONDecoder().decode(Observation.self, from: Data("{\"value\":\"1\"}".utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(SourceDocument.self, from: Data("{\"filename\":\"a.pdf\"}".utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(VariableDefinition.self, from: Data("{\"id\":\"x\"}".utf8)))
    }
    func testCurrentEncodingRoundTripsThroughTheLenientDecoder() throws {
        var project = ReviewProject(title: "Round trip"); project.plan.approvedAt = Date(timeIntervalSince1970: 1_700_000_000); project.plan.version = 3
        project.messages = [.init(role: "user", text: "hi", sources: [.init(title: "T", url: "https://example.org")])]
        project.assets = []
        let decoded = try JSONDecoder().decode(ReviewProject.self, from: JSONEncoder().encode(project))
        XCTAssertEqual(decoded, project)
    }
}
