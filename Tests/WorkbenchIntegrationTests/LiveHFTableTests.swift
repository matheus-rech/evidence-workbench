import XCTest
import ReviewCore
final class LiveHFTableTests:XCTestCase {
    func testLivePublicArtsTableThroughIntegratedClient() async throws {
        guard let path=ProcessInfo.processInfo.environment["EW_HF_TABLE_IMAGE"],let output=ProcessInfo.processInfo.environment["EW_HF_TABLE_REPORT"] else { throw XCTSkip("Public live HF table test is opt-in.") }
        let data=try Data(contentsOf:URL(fileURLWithPath:path));let image=PageImage(page:7,dataURL:"data:image/jpeg;base64,"+data.base64EncodedString())
        let start=Date();let reply=try await GLMTableClient().transcribe(image:image,title:"Arts Table 1")
        XCTAssertEqual(reply.columns.count,7);XCTAssertEqual(reply.rows.count,6)
        XCTAssertEqual(reply.rows[0].cells,["N","235","496","","259","522",""])
        XCTAssertTrue(reply.rows[1].cells[1].contains("74.61"));XCTAssertTrue(reply.rows[1].cells[5].contains("72.79"))
        let record:[String:Any] = ["elapsed_seconds":Date().timeIntervalSince(start),"columns":reply.columns,"rows":reply.rows.map(\.cells),"warnings":reply.warnings]
        try JSONSerialization.data(withJSONObject:record,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:output))
    }
}
