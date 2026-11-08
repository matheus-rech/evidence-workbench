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
         "proposals":[{"id":"\(UUID().uuidString)","summary":"S","variables":[]}],
         "assets":[{"id":"\(UUID().uuidString)","documentID":"\(documentID.uuidString)","sourceSHA256":"abc","page":1,"kind":"table","label":"Table 1","title":"Baseline","region":{"x":0,"y":0,"width":1,"height":1}}]}
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
        XCTAssertNil(project.researchJob)
        let asset = try XCTUnwrap(project.assets?.first)
        XCTAssertEqual(asset.origin, "AI discovery"); XCTAssertTrue(asset.warnings.isEmpty); XCTAssertEqual(asset.caption, ""); XCTAssertFalse(asset.exactCrop); XCTAssertNil(asset.table)
        let document = try XCTUnwrap(project.documents.first)
        XCTAssertEqual(document.peerReviewStatus, "Unconfirmed"); XCTAssertTrue(document.warnings.isEmpty)
        XCTAssertFalse(document.pages[0].ocr)
        let row = try XCTUnwrap(project.observations.first)
        XCTAssertEqual(row.missingness, .reported); XCTAssertEqual(row.status, .suggested); XCTAssertEqual(row.planVersion, 1)
        XCTAssertEqual(row.model, ""); XCTAssertEqual(row.reviewer, ""); XCTAssertEqual(row.note, ""); XCTAssertNil(row.confidence)
        XCTAssertEqual(row.context, ObservationContext()); XCTAssertFalse(row.citations[0].exactMatch)
        XCTAssertTrue(project.messages[0].sources.isEmpty); XCTAssertTrue(project.proposals[0].sources.isEmpty); XCTAssertNil(project.proposals[0].picott)
    }
    func testRecordsWithoutTheirOwnIDAreRefused() throws {
        // A missing id must fail rather than mint a new one: a review whose id changes on every load is saved to a new
        // folder (revision 0) or can never be saved (revision >= 1), and an observation or asset loses its identity.
        let doc = UUID().uuidString
        let project = "{\"title\":\"No id\",\"schemaVersion\":1,\"revision\":0}"
        let observation = "{\"documentID\":\"\(doc)\",\"variableID\":\"title\",\"value\":\"x\"}"
        let asset = "{\"documentID\":\"\(doc)\",\"sourceSHA256\":\"abc\",\"page\":1,\"kind\":\"table\",\"label\":\"Table 1\"}"
        XCTAssertThrowsError(try JSONDecoder().decode(ReviewProject.self, from: Data(project.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(Observation.self, from: Data(observation.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(SourceAsset.self, from: Data(asset.utf8)))
        // The same records with an id still decode, so the refusal is caused by the missing id alone.
        let id = UUID().uuidString
        XCTAssertNoThrow(try JSONDecoder().decode(ReviewProject.self, from: Data(project.replacingOccurrences(of: "{", with: "{\"id\":\"\(id)\",").utf8)))
        XCTAssertNoThrow(try JSONDecoder().decode(Observation.self, from: Data(observation.replacingOccurrences(of: "{", with: "{\"id\":\"\(id)\",").utf8)))
        XCTAssertNoThrow(try JSONDecoder().decode(SourceAsset.self, from: Data(asset.replacingOccurrences(of: "{", with: "{\"id\":\"\(id)\",").utf8)))
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
