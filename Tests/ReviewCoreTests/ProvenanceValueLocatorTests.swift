import XCTest
@testable import ReviewCore

final class ProvenanceValueLocatorTests: XCTestCase {
    func testNumericEmphasisDoesNotSelectAnotherNumber() {
        let quote = "15 -5 5.2 1,500 5e3; value 5%; repeat 5 (SD)."
        let ranges = ProvenanceValueLocator.ranges(value: "5", quote: quote, numeric: true)
        XCTAssertEqual(ranges.count, 2)
        XCTAssertEqual(ranges.map { (quote as NSString).substring(with: $0) }, ["5", "5"])
    }
    func testDecimalAndUnicodeUseCorrectUTF16Offsets() {
        let quote = "🧠 Baseline: 74.61 (13.63); post: 73.73 (14.7)."
        let ranges = ProvenanceValueLocator.ranges(value: "74.61", quote: quote, numeric: true)
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual((quote as NSString).substring(with: ranges[0]), "74.61")
        XCTAssertTrue(ProvenanceValueLocator.ranges(value: "74.6", quote: quote, numeric: true).isEmpty)
        XCTAssertTrue(ProvenanceValueLocator.ranges(value: "", quote: quote, numeric: false).isEmpty)
    }
}
