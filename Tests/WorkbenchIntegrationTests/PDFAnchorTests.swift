import XCTest
import PDFKit
import ReviewCore
@testable import EvidenceWorkbench

final class PDFAnchorTests: XCTestCase {
    func pdf() throws -> PDFDocument {
        let url = try DocumentLoaderTests().fixture(text: "Mean age was 68.5 years; 50 patients and 50 patients.")
        defer { try? FileManager.default.removeItem(at: url) }
        return try XCTUnwrap(PDFDocument(data: Data(contentsOf: url)))
    }
    func testNativeSelectionIsOnRequestedPage() throws {
        let pdf = try pdf(); let second = try XCTUnwrap(pdf.page(at: 0)?.copy() as? PDFPage); pdf.insert(second, at: 1)
        let selection = try XCTUnwrap(PDFSourceAnchor.selection(document: pdf, pageNumber: 2, quote: "Mean age was 68.5 years;"))
        XCTAssertEqual(selection.pages.count, 1); XCTAssertTrue(selection.pages[0] === second)
    }
    func testNoHighlightForWrongPageOrMissingText() throws {
        let pdf = try pdf()
        XCTAssertNil(PDFSourceAnchor.selection(document: pdf, pageNumber: 99, quote: "Mean age"))
        XCTAssertNil(PDFSourceAnchor.selection(document: pdf, pageNumber: 1, quote: "99 years"))
    }
    func testNativeRepeatedTextDoesNotSelectFirstOccurrence() throws {
        let pdf = try pdf(); let page = try XCTUnwrap(pdf.page(at: 0))
        XCTAssertNil(PDFSourceAnchor.selection(document: pdf, pageNumber: 1, quote: "50 patients"))
        let ranges = QuoteLocator.matches(in: page.string ?? "", quote: "50 patients")
        let second = try XCTUnwrap(ranges.last)
        let selection = try XCTUnwrap(PDFSourceAnchor.selection(document: pdf, pageNumber: 1, quote: "50 patients", start: second.location, length: second.length))
        XCTAssertEqual(selection.range(at: 0, on: page), second)
    }
    func testCroppedRotatedPageSelectionRemainsInPageCoordinates() throws {
        let pdf = try pdf(); let page = try XCTUnwrap(pdf.page(at: 0))
        page.setBounds(CGRect(x: 20, y: 20, width: 572, height: 752), for: .cropBox)
        for rotation in [0, 90, 180, 270] {
            page.rotation = rotation
            let selection = try XCTUnwrap(PDFSourceAnchor.selection(document: pdf, pageNumber: 1, quote: "Mean age was 68.5 years;"))
            let bounds = selection.bounds(for: page)
            XCTAssertTrue(bounds.width > 0 && bounds.height > 0)
            XCTAssertTrue(page.bounds(for: .cropBox).intersects(bounds))
        }
    }
    func testVisualPageBatchRetainsPhysicalPageNumbers() async throws {
        let fixture = try DocumentLoaderTests().fixture(text: "Synthetic page image")
        defer { try? FileManager.default.removeItem(at: fixture) }
        let images = try await PDFPageImages.render(url: fixture, pageNumbers: [1, 1])
        XCTAssertEqual(images.count, 1); XCTAssertEqual(images[0].page, 1)
        XCTAssertTrue(images[0].dataURL.hasPrefix("data:image/jpeg;base64,"))
    }
    func testRegionGeometrySurvivesCropRotationAndCoordinateRoundTrip() throws {
        let page = try XCTUnwrap(try pdf().page(at: 0))
        page.setBounds(CGRect(x: 20, y: 30, width: 500, height: 700), for: .cropBox)
        for rotation in [0, 90, 180, 270] {
            page.rotation = rotation
            let rect = CGRect(x: 120, y: 240, width: 100, height: 35)
            let region = try XCTUnwrap(PDFRegionGeometry.region(rect: rect, page: page))
            XCTAssertEqual(region.x, 0.2, accuracy: 0.00001)
            XCTAssertEqual(region.y, 0.3, accuracy: 0.00001)
            XCTAssertEqual(try XCTUnwrap(PDFRegionGeometry.rect(region: region, page: page)), rect)
        }
        XCTAssertNil(PDFRegionGeometry.region(rect: CGRect(x: -100, y: -100, width: 5, height: 5), page: page))
        XCTAssertNil(PDFRegionGeometry.rect(region: .init(x: 2, y: 0, width: 1, height: 1), page: page))
    }
}
