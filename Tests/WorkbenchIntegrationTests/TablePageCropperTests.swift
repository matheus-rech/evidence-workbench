import XCTest
import ReviewCore
@testable import EvidenceWorkbench
final class TablePageCropperTests:XCTestCase {
    func testLiveCaptionCropsWhenRequested() async throws {
        let env=ProcessInfo.processInfo.environment
        guard let root=env["EW_CROP_SOURCE_ROOT"], let out=env["EW_CROP_OUTPUT"] else { throw XCTSkip("Live crop diagnosis is opt-in.") }
        try FileManager.default.createDirectory(atPath:out,withIntermediateDirectories:true)
        for (name,page,label) in [("Arts_2017",7,"Table 2"),("Karlsson_2018",10,"Table 2")] {
            let region=try TablePageCropper.region(url:URL(fileURLWithPath:root).appendingPathComponent(name+".pdf"),pageNumber:page,label:label)
            let png=try await RegionExport.image(url:URL(fileURLWithPath:root).appendingPathComponent(name+".pdf"),pageNumber:page,region:region)
            try png.write(to:URL(fileURLWithPath:out).appendingPathComponent(name+".png"))
            let client=GLMTableClient(transport:RecordingTableTransport(output:URL(fileURLWithPath:out).appendingPathComponent(name+".sse")))
            let reply=try await client.transcribe(image:RegionExport.jpeg(png,page:page),title:label)
            XCTAssertFalse(reply.rows.isEmpty)
        }
    }
    func testActualPilotCaptionsProduceDistinctBoundedInputsWhenRequested() throws {
        guard let path=ProcessInfo.processInfo.environment["EW_ARTS_PDF"] else { throw XCTSkip("Real primary-paper caption check is opt-in.") }
        let url=URL(fileURLWithPath:path)
        let first=try TablePageCropper.region(url:url,pageNumber:7,label:"Table 1")
        let second=try TablePageCropper.region(url:url,pageNumber:7,label:"Table 2")
        XCTAssertTrue(first.isValid);XCTAssertTrue(second.isValid);XCTAssertGreaterThan(first.y,second.y)
        XCTAssertThrowsError(try TablePageCropper.region(url:url,pageNumber:7,label:"Table 999"))
    }
}

private struct RecordingTableTransport:ResponsesTransport {
    let output:URL
    func send(_ request:URLRequest) async throws -> (Data,Int,String?) {
        let response=try await URLSessionTransport().send(request)
        if request.httpMethod != "POST" { try response.0.write(to:output) }
        return response
    }
}
