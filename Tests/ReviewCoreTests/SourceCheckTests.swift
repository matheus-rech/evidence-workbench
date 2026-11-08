import XCTest
@testable import ReviewCore

final class SourceCheckTests: XCTestCase {
    func testAIQuoteMatchCannotSubstituteForUnresolvedSourceCheck() throws {
        let document = SourceDocument(filename: "trial.pdf", relativePath: "trial.pdf", sha256: "fixture", pages: [.init(number: 1, text: "Control age 74.61 years.")])
        let field = try XCTUnwrap(CoreFields.defaults.first { $0.id == "age_mean" })
        var row = Observation(documentID: document.id, variableID: field.id, value: "74.61", citations: [.init(page: 1, quote: "Control age 74.61 years.")], model: "extractor")
        XCTAssertThrowsError(try ReviewEngine.verify(row, variable: field, reviewer: "QA", document: document))
        row.sourceCheck = .init(verdict: .supported, reason: "Value, unit and control group match", model: "checker", claimFingerprint: SourceCheckPolicy.fingerprint(row))
        XCTAssertNoThrow(try ReviewEngine.verify(row, variable: field, reviewer: "QA", document: document))
        row.context.arm = "Intervention"
        XCTAssertFalse(SourceCheckPolicy.supported(row))
        XCTAssertThrowsError(try ReviewEngine.verify(row, variable: field, reviewer: "QA", document: document))
    }
    func testContradictionNeedsExplicitAdjudicationAndStillNeedsSource() throws {
        let document = SourceDocument(filename: "trial.pdf", relativePath: "trial.pdf", sha256: "fixture", pages: [.init(number: 1, text: "Control age 74.61 years.")])
        let field = try XCTUnwrap(CoreFields.defaults.first { $0.id == "age_mean" })
        var row = Observation(documentID: document.id, variableID: field.id, value: "74.61", citations: [.init(page: 1, quote: "Control age 74.61 years.")], model: "extractor")
        row.sourceCheck = .init(verdict: .contradicted, reason: "Potential wrong group", model: "checker", claimFingerprint: SourceCheckPolicy.fingerprint(row))
        XCTAssertThrowsError(try ReviewEngine.verify(row, variable: field, reviewer: "QA", document: document))
        row.sourceAdjudication = "Reviewer checked the control column in original Table 1; model confused the header."
        XCTAssertNoThrow(try ReviewEngine.verify(row, variable: field, reviewer: "QA", document: document))
        row.citations[0].quote = "missing quote"
        XCTAssertThrowsError(try ReviewEngine.verify(row, variable: field, reviewer: "QA", document: document))
    }
    func testVerifiedExportExcludesUnresolvedLegacyAIClaims() {
        var project = ReviewProject(); let document = SourceDocument(filename: "trial.pdf", relativePath: "trial.pdf", sha256: "fixture", pages: [.init(number: 1, text: "Age 74.61")]); project.documents = [document]
        var row = Observation(documentID: document.id, variableID: "age_mean", value: "74.61", status: .verified, model: "extractor")
        project.observations = [row]
        XCTAssertEqual(DatasetExporter.longCSV(project, verifiedOnly: true).components(separatedBy: "\r\n").count, 2)
        row.sourceAdjudication = "Checked original source manually"; project.observations = [row]
        XCTAssertTrue(DatasetExporter.longCSV(project, verifiedOnly: true).contains("74.61"))
    }
}
