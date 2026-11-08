import XCTest
@testable import ReviewCore
final class AutomationTests: XCTestCase {
    func testAutomaticReviewExportsAsAIAndNeverAsHuman() throws {
        let doc = SourceDocument(filename: "trial.txt", relativePath: "documents/trial.txt", sha256: "sha", pages: [.init(number: 1, text: "Control mean age 74.61 years at baseline")])
        let field = try XCTUnwrap(CoreFields.defaults.first { $0.id == "age_mean" })
        var row = Observation(documentID: doc.id, variableID: field.id, value: "74.61", context: .init(arm: "Control", timepoint: "Baseline"), citations: [.init(page: 1, quote: doc.pages[0].text)], model: "extractor")
        row.sourceCheck = .init(verdict: .supported, reason: "Source matches", model: "checker", claimFingerprint: SourceCheckPolicy.fingerprint(row), sourceFingerprint: SourceCheckPolicy.checkFingerprint(row, variable: field, document: doc))
        let accepted = AutomationPolicy.review(row, variable: field, document: doc)
        XCTAssertEqual(accepted.status,.aiReviewed)
        var project = ReviewProject();project.documents = [doc];project.observations = [accepted]
        XCTAssertTrue(DatasetExporter.longCSV(project, verifiedOnly: false, aiReviewedOnly: true).contains("74.61"))
        XCTAssertFalse(DatasetExporter.longCSV(project, verifiedOnly: true).contains("74.61"))
        var changed = doc; changed.sha256 = "different"
        XCTAssertFalse(AutomationPolicy.isAcceptable(accepted,variable:field,document:changed))
    }
    func testWrongImageNumberCannotBecomeAIReviewed() throws {
        let doc = SourceDocument(filename: "trial.pdf", relativePath: "documents/trial.pdf", sha256: "sha", pages: [.init(number: 8, text: "Total AF patients: 8292")])
        let field = try XCTUnwrap(CoreFields.defaults.first { $0.id == "n" })
        var row = Observation(documentID: doc.id, variableID: field.id, value: "9292", citations: [.init(page: 8,quote:"Total AF patients: 9292")], model: "extractor")
        row.sourceCheck = .init(verdict:.supported,reason:"False agreement",model:"checker",claimFingerprint:SourceCheckPolicy.fingerprint(row),sourceFingerprint:SourceCheckPolicy.checkFingerprint(row,variable:field,document:doc))
        XCTAssertEqual(AutomationPolicy.review(row,variable:field,document:doc).status,.suggested)
        row.citations = [.init(page:8,quote:"Total AF patients: 8292")]
        row.sourceCheck = .init(verdict:.supported,reason:"False agreement",model:"checker",claimFingerprint:SourceCheckPolicy.fingerprint(row),sourceFingerprint:SourceCheckPolicy.checkFingerprint(row,variable:field,document:doc))
        XCTAssertEqual(AutomationPolicy.review(row,variable:field,document:doc).status,.suggested)
    }
    func testChangedDefinitionInvalidatesAIBinding() throws {
        let doc = SourceDocument(filename:"t",relativePath:"documents/t.txt",sha256:"s",pages:[.init(number:1,text:"Age 74.61")]);var f = try XCTUnwrap(CoreFields.defaults.first { $0.id == "age_mean" })
        var row = Observation(documentID:doc.id,variableID:f.id,value:"74.61",citations:[.init(page:1,quote:"Age 74.61")],model:"m")
        row.sourceCheck = .init(verdict:.supported,reason:"x",model:"m",claimFingerprint:SourceCheckPolicy.fingerprint(row),sourceFingerprint:SourceCheckPolicy.checkFingerprint(row,variable:f,document:doc))
        f.unit = "months";XCTAssertFalse(SourceCheckPolicy.supported(row,variable:f,document:doc))
    }
}
