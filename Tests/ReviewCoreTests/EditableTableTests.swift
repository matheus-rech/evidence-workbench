import XCTest
@testable import ReviewCore

final class EditableTableTests: XCTestCase {
    func table() -> EditableTable { .init(title: "Study <table>", columns: ["Group", "N", "Value"], rows: [["Control", "235", "74.61 ± 13.63"], ["Intervention", "496", "72.13 ± 12.46"]], footnotes: ["Values as printed."], sourceFilename: "trial.pdf", sourceSHA256: "fixture", page: 7, region: .init(x: 0.1, y: 0.2, width: 0.8, height: 0.2)) }
    func testTableFormatsRetainCellsAndEscapeContent() throws {
        let t = table(); try t.validate()
        XCTAssertTrue(t.html.contains("<table>")); XCTAssertTrue(t.html.contains("Study &lt;table&gt;"))
        XCTAssertTrue(t.html.contains("74.61 ± 13.63")); XCTAssertTrue(t.html.contains("PDF page 7"))
        XCTAssertEqual(t.tsv.components(separatedBy: "\n")[1], "Control\t235\t74.61 ± 13.63")
        XCTAssertTrue(t.csv.contains("\"235\"")); XCTAssertTrue(t.rtf.contains("\\trowd")); XCTAssertTrue(t.rtf.contains("\\u177?"))
    }
    func testRaggedRowsAndBadCoordinatesFailBeforeExport() throws {
        var t = table(); t.rows[0].removeLast(); XCTAssertThrowsError(try t.validate())
        t = table(); t.region.x = 2; XCTAssertThrowsError(try t.validate())
    }
    func testSpreadsheetCopyNeutralizesFormulasWithoutChangingNegativeNumbers() {
        var t = table(); t.rows = [["=HYPERLINK(\"bad\")", "-4", "a\tb\nc"]]
        XCTAssertTrue(t.tsv.contains("'=HYPERLINK")); XCTAssertTrue(t.tsv.contains("\t-4\t")); XCTAssertTrue(t.tsv.contains("a b c"))
    }
    func testLegacyPlansDoNotRequireSilentAmendmentAndNewPlansHaveRates() {
        let p = ReviewPlan()
        XCTAssertTrue(p.variables.contains { $0.id == "outcome_proportion" })
        XCTAssertTrue(p.variables.contains { $0.id == "outcome_rate" })
        XCTAssertFalse(CoreFields.requiredIDs.contains("outcome_proportion"))
    }
}
