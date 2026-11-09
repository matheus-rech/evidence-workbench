import XCTest
@testable import ReviewCore
final class GLMTableTests: XCTestCase {
    func testHTMLTableKeepsBlankCellsAndHeaderHierarchy() throws {
        let table = try GLMTableParser.parse("<table><tr><td rowspan=\"2\">Measure</td><td colspan=\"2\">Baseline</td></tr><tr><td>Control</td><td>Intervention</td></tr><tr><td>N</td><td>235</td><td>496</td></tr><tr><td>P</td><td></td><td>0.08</td></tr></table>", title: "Table 1")
        XCTAssertEqual(table.columns,["Measure","Baseline / Control","Baseline / Intervention"])
        XCTAssertEqual(table.rows.map(\.cells),[["N","235","496"],["P","","0.08"]])
    }
    func testUnsafeOrRaggedHTMLNeverBecomesACompleteTable() {
        for html in ["<script>alert(1)</script><table><tr><td>x</td></tr></table>","<table><tr><td>A</td><td>B</td></tr><tr><td>1</td></tr></table>","<table><tr><td colspan=\"9000\">x</td></tr></table>"] {
            XCTAssertThrowsError(try GLMTableParser.parse(html,title:"T"))
        }
    }
    func testMultipleAndTruncatedTablesAreRejected() {
        let one="<table><tr><td>A</td></tr><tr><td>1</td></tr></table>"
        XCTAssertThrowsError(try GLMTableParser.parse(one+one,title:"T"))
        XCTAssertThrowsError(try GLMTableParser.parse(one.replacingOccurrences(of:"</table>",with:""),title:"T"))
        XCTAssertThrowsError(try GLMTableClient.completedText(Data("event: complete\ndata: [\"[ERROR] quota exceeded\"]\n".utf8)))
    }
    func testSingleColumnAndFullWidthNotesAreNotConfused() throws {
        let one=try GLMTableParser.parse("<table><tr><td>A</td></tr><tr><td>1</td></tr><tr><td>2</td></tr></table>",title:"T")
        XCTAssertEqual(one.rows.count,2)
        let notes=try GLMTableParser.parse("<table><tr><td>A</td><td>B</td></tr><tr><td>1</td><td>1</td></tr><tr><td colspan='2'>Note</td></tr></table>",title:"T")
        XCTAssertEqual(notes.rows.map(\.cells),[["1","1"]]);XCTAssertEqual(notes.footnotes,["Note"])
    }
    func testCompleteEventRequiredAndRemoteErrorIsNotATable() throws {
        XCTAssertEqual(try GLMTableClient.completedText(Data("event: generating\ndata: [\"partial\"]\n\nevent: complete\ndata: [\"<table>done</table>\"]\n\n".utf8)),"<table>done</table>")
        XCTAssertThrowsError(try GLMTableClient.completedText(Data("event: error\ndata: [\"quota exceeded\"]\n\n".utf8)))
        XCTAssertThrowsError(try GLMTableClient.completedText(Data("event: generating\ndata: [\"partial\"]\n\n".utf8)))
    }
}
