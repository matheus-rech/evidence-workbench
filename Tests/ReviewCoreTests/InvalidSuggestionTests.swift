import XCTest
@testable import ReviewCore

final class InvalidSuggestionTests: XCTestCase {
    func testRateOrPercentageCannotBeVerifiedAsContinuousMean() throws {
        let document = SourceDocument(filename: "trial.pdf", relativePath: "trial.pdf", sha256: "fixture", pages: [.init(number: 1, text: "Incidence was 49 per 1,000 patients.")])
        let field = try XCTUnwrap(CoreFields.defaults.first { $0.id == "outcome_mean" })
        let row = Observation(documentID: document.id, variableID: field.id, value: "49", context: .init(outcome: "Stroke incidence"), citations: [.init(page: 1, quote: "Incidence was 49 per 1,000 patients.")], note: "per 1,000 patients")
        let flagged = try ReviewEngine.reviewableSuggestion(row, variable: field, document: document)
        XCTAssertEqual(flagged.missingness, .unclear)
        XCTAssertTrue(flagged.note.contains("Raw value: 49"))
        XCTAssertThrowsError(try ReviewEngine.verify(row, variable: field, reviewer: "QA", document: document))
        var legitimate = row; legitimate.note = "Continuous symptom score"; legitimate.context.outcome = "Symptom score"; legitimate.value = "4.9"
        XCTAssertNoThrow(try ReviewEngine.validateObservationValue(legitimate, variable: field))
    }
    func testMalformedIntegerDoesNotDiscardValidRowsOrBecomeANumber() throws {
        let document = SourceDocument(filename: "report.pdf", relativePath: "report.pdf", sha256: "fixture", pages: [.init(number: 1, text: "There were 14,134 patients at baseline and 42 clinics.")])
        let field = try XCTUnwrap(CoreFields.defaults.first { $0.id == "n" })
        let malformed = Observation(documentID: document.id, variableID: "n", value: "14,134", citations: [.init(page: 1, quote: "14,134 patients")], confidence: 98)
        let valid = Observation(documentID: document.id, variableID: "n", value: "42", citations: [.init(page: 1, quote: "42 clinics")])
        let rows = try [malformed, valid].map { try ReviewEngine.reviewableSuggestion($0, variable: field, document: document) }
        XCTAssertEqual(rows[0].missingness, .unclear); XCTAssertEqual(rows[0].value, "")
        XCTAssertTrue(rows[0].note.contains("14,134")); XCTAssertNil(rows[0].confidence)
        XCTAssertEqual(rows[0].status, .suggested)
        XCTAssertEqual(rows[1].value, "42"); XCTAssertEqual(rows[1].missingness, .reported)
        // This validates syntax only. Correct participant-versus-cluster interpretation still needs checking.
    }
    func testWrongSourceStillFailsAndInvalidPageIsNotRetained() throws {
        let document = SourceDocument(filename: "report.pdf", relativePath: "report.pdf", sha256: "fixture", pages: [.init(number: 1, text: "42")])
        let field = try XCTUnwrap(CoreFields.defaults.first { $0.id == "n" })
        var row = Observation(documentID: UUID(), variableID: "n", value: "42")
        XCTAssertThrowsError(try ReviewEngine.reviewableSuggestion(row, variable: field, document: document))
        row.documentID = document.id; row.citations = [.init(page: 99, quote: "42")]
        let flagged = try ReviewEngine.reviewableSuggestion(row, variable: field, document: document)
        XCTAssertEqual(flagged.missingness, .unclear); XCTAssertTrue(flagged.citations.isEmpty)
    }
}
