import XCTest
@testable import ReviewCore
final class PaddleTableTests:XCTestCase {
    func testSpansAndCaptionAndFootnoteArePreserved() throws {
        let input="<fcel>Table 2. Results<lcel><lcel><nl><fcel>Measure<fcel>2016<lcel><nl><ucel><fcel>Control<fcel>CDS<nl><fcel>N<fcel>4187<fcel>5186<nl><fcel>*Footnote<lcel><lcel><nl>"
        let table=try PaddleTableParser.parse(input,title:"Table 2")
        XCTAssertEqual(table.columns,["Measure","2016 / Control","2016 / CDS"])
        XCTAssertEqual(table.rows.map(\.cells),[["N","4187","5186"]]);XCTAssertEqual(table.footnotes,["*Footnote"])
    }
    func testRaggedOrUnanchoredSpansAreRejected() {
        for input in ["<fcel>A<fcel>B<nl><fcel>1<nl>","<ucel><fcel>B<nl><fcel>1<fcel>2<nl>","<fcel>A<fcel>B<nl><fcel>1<ecel>unexpected<nl>"] {
            XCTAssertThrowsError(try PaddleTableParser.parse(input,title:"T"))
        }
    }
    func testMeasuredRawOutputsThroughProductionParser() throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("benchmarks/ocr-pilot/remote-results.json")
        guard FileManager.default.fileExists(atPath:root.path) else { throw XCTSkip("Frozen pilot responses not installed.") }
        let rows=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:root)) as? [[String:Any]])
        for row in rows where row["engine"] as? String == "paddleocr-vl-1.6" && (row["sample"] as? String ?? "").hasSuffix("table") {
            let table=try PaddleTableParser.parse(try XCTUnwrap(row["text"] as? String),title:row["sample"] as? String ?? "")
            XCTAssertFalse(table.rows.isEmpty);XCTAssertTrue(table.rows.allSatisfy{$0.cells.count == table.columns.count})
            if row["sample"] as? String == "Arts_2017-p7-table" { XCTAssertEqual(table.rows.count,6);XCTAssertEqual(table.rows[0].cells,["N","235","496","","259","522",""]) }
            if row["sample"] as? String == "Karlsson_2018-p10-table" { XCTAssertEqual(table.rows.count,3);XCTAssertTrue(table.columns[1].contains("Control"));XCTAssertFalse(table.footnotes.isEmpty) }
        }
    }
    func testLocalClientUsesPinnedPaddleResponse() async throws {
        let payload:[String:String] = ["text":"<fcel>Measure<fcel>Control<nl><fcel>N<fcel>235<nl>","model_revision":"132c45f52c0a26ed5a6b2f6bd8e3985794cc27dd"]
        let transport=PaddleReplyTransport(data:try JSONSerialization.data(withJSONObject:payload))
        let table=try await LocalTableClient(transport:transport).transcribe(image:PageImage(page:1,dataURL:"data:image/jpeg;base64,AA=="),title:"T",endpoint:"http://127.0.0.1:8766/table")
        XCTAssertEqual(table.rows.map(\.cells),[["N","235"]]);XCTAssertTrue(table.warnings[0].contains("PaddleOCR"))
        let request=await transport.sent
        XCTAssertEqual(request?.url?.path,"/table");XCTAssertEqual(request?.httpMethod,"POST")
        let body=try JSONSerialization.jsonObject(with:XCTUnwrap(request?.httpBody)) as? [String:String]
        XCTAssertEqual(body?["image"],"data:image/jpeg;base64,AA==")
    }
    func testLocalClientRejectsRemoteEndpointBeforeAnyRequest() async {
        do { _ = try await LocalTableClient().transcribe(image:PageImage(page:1,dataURL:"data:image/jpeg;base64,AA=="),title:"T",endpoint:"http://example.com/table");XCTFail("Remote request accepted") } catch { XCTAssertTrue(error.localizedDescription.contains("loopback")) }
    }
}

private actor PaddleReplyTransport:ResponsesTransport {
    let data:Data;var sent:URLRequest?
    init(data:Data){self.data=data}
    func send(_ request:URLRequest) async throws -> (Data,Int,String?) {sent=request;return(data,200,nil)}
}
