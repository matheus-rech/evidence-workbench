import XCTest
@testable import ReviewCore

final class QuoteLocatorTests: XCTestCase {
    func testWhitespaceMatchesMapBackToOriginalCharacters() throws {
        let text = "Heading\nMean age\n  was\t68.5 years. End."
        let range = try XCTUnwrap(QuoteLocator.resolve(in: text, quote: "Mean age was 68.5 years."))
        XCTAssertEqual((text as NSString).substring(with: range), "Mean age\n  was\t68.5 years.")
    }
    func testUnicodeLigaturesAndSurrogatesKeepExactOffsets() throws {
        let text = "😀 These ﬁndings include 68.5."
        let range = try XCTUnwrap(QuoteLocator.resolve(in: text, quote: "findings include 68.5."))
        XCTAssertEqual((text as NSString).substring(with: range), "ﬁndings include 68.5.")
    }
    func testRepeatedQuotesRequireSelectedOccurrence() throws {
        let text = "50 patients; another 50 patients."
        let matches = QuoteLocator.matches(in: text, quote: "50 patients")
        XCTAssertEqual(matches.count, 2)
        XCTAssertNil(QuoteLocator.resolve(in: text, quote: "50 patients"))
        XCTAssertEqual(QuoteLocator.resolve(in: text, quote: "50 patients", start: matches[1].location, length: matches[1].length), matches[1])
    }
    func testInvalidSavedAnchorDoesNotJumpElsewhere() {
        XCTAssertNil(QuoteLocator.resolve(in: "68.5 years", quote: "68.5", start: 2, length: 4))
        XCTAssertNil(QuoteLocator.resolve(in: "68.5 years", quote: "68.5", start: Int.max, length: 4))
    }
    func testNoPartialNumericOrPunctuationGuessing() {
        XCTAssertNil(QuoteLocator.resolve(in: "68.5", quote: "6.85"))
        XCTAssertNil(QuoteLocator.resolve(in: "1.2", quote: "12"))
        XCTAssertNil(QuoteLocator.resolve(in: "95% CI 1–2", quote: "95% CI 1-2"))
    }
    func testAmbiguousEvidenceCannotBeVerifiedWithoutAnchor() throws {
        let doc = SourceDocument(filename: "test.pdf", relativePath: "documents/test.pdf", sha256: "test", pages: [.init(number: 1, text: "50 patients and 50 patients")])
        let field = VariableDefinition(id: "n", label: "N", definition: "Sample", type: .integer)
        var row = Observation(documentID: doc.id, variableID: "n", value: "50", citations: [.init(page: 1, quote: "50 patients")])
        XCTAssertThrowsError(try ReviewEngine.verify(row, variable: field, reviewer: "A", document: doc))
        let match = QuoteLocator.matches(in: doc.pages[0].text, quote: "50 patients")[1]
        row.citations[0].startUTF16 = match.location; row.citations[0].lengthUTF16 = match.length
        XCTAssertEqual(try ReviewEngine.verify(row, variable: field, reviewer: "A", document: doc).citations[0].startUTF16, match.location)
    }
    func testOlderCitationsDecodeWithoutOffsets() throws {
        let citation = try JSONDecoder().decode(EvidenceCitation.self, from: Data("{\"page\":1,\"quote\":\"Test\",\"exactMatch\":true}".utf8))
        XCTAssertNil(citation.startUTF16)
    }
}
