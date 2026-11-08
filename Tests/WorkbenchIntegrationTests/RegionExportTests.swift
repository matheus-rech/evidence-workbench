import XCTest
import AppKit
import PDFKit
import ReviewCore
@testable import EvidenceWorkbench

final class RegionExportTests: XCTestCase {
    func testPNGRegionCropAndPageExportHaveRealPixels() async throws {
        let url = try DocumentLoaderTests().fixture(text: "Region export fixture")
        defer { try? FileManager.default.removeItem(at: url) }
        let png = try await RegionExport.image(url: url, pageNumber: 1, region: .init(x: 0.1, y: 0.4, width: 0.7, height: 0.1))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: png))
        XCTAssertGreaterThan(bitmap.pixelsWide, bitmap.pixelsHigh)
        XCTAssertEqual(Array(png.prefix(8)), [137,80,78,71,13,10,26,10])
        let whole = try await RegionExport.image(url: url, pageNumber: 1, region: nil)
        XCTAssertNotEqual(png, whole)
        let jpeg = try RegionExport.jpeg(png, page: 1); XCTAssertTrue(jpeg.dataURL.hasPrefix("data:image/jpeg;base64,"))
    }
    func testRTFContainsAnEditableNativeTable() throws {
        let t = EditableTable(title: "Editable", columns: ["Group", "N"], rows: [["Control", "235"], ["Intervention", "496"]], sourceFilename: "trial.pdf", sourceSHA256: "fixture", page: 7, region: .init(x: 0.1, y: 0.2, width: 0.8, height: 0.2))
        let rich = try NSAttributedString(data: Data(t.rtf.utf8), options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        XCTAssertTrue(rich.string.contains("235")); XCTAssertTrue(rich.string.contains("496"))
        var blocks = 0
        rich.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: rich.length)) { value, _, _ in
            if let paragraph = value as? NSParagraphStyle { blocks += paragraph.textBlocks.filter { $0 is NSTextTableBlock }.count }
        }
        XCTAssertGreaterThan(blocks, 0)
    }
}
