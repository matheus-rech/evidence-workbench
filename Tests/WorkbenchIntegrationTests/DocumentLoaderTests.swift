import XCTest
import CoreGraphics
import CoreText
import PDFKit
@testable import EvidenceWorkbench
import ReviewCore

final class DocumentLoaderTests: XCTestCase {
    func fixture(text: String?) throws -> URL {
        let data = NSMutableData()
        let consumer = CGDataConsumer(data: data)!
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = CGContext(consumer: consumer, mediaBox: &box, nil)!
        context.beginPDFPage(nil)
        if let text {
            let attributes: [NSAttributedString.Key: Any] = [.init(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 14, nil)]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            context.textPosition = CGPoint(x: 50, y: 720); CTLineDraw(line, context)
        }
        context.endPDFPage(); context.closePDF()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        try (data as Data).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    @MainActor func testNativePDFTextAndPageNumberArePreserved() async throws {
        let url = try fixture(text: "Synthetic test: mean age 68.5 years; zero events.")
        let result = try await DocumentLoader.load(url, ocr: false)
        XCTAssertEqual(result.pages.count, 1); XCTAssertEqual(result.pages[0].number, 1)
        XCTAssertTrue(result.pages[0].text.contains("68.5")); XCTAssertFalse(result.pages[0].ocr)
    }
    @MainActor func testBlankPDFDoesNotFallBackToSampleStudy() async throws {
        let url = try fixture(text: nil)
        do { _ = try await DocumentLoader.load(url, ocr: false); XCTFail("Blank PDF must fail") }
        catch { XCTAssertTrue(error.localizedDescription.contains("No readable text")) }
    }
    @MainActor func testUTF8ProtocolCanBeReadBeforeAnyProjectExists() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try Data("Protocol: population, intervention, comparator, outcomes, timing and study design.".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let result = try await DocumentLoader.load(url, ocr: false)
        XCTAssertTrue(result.pages[0].text.hasPrefix("Protocol:"))
    }
    @MainActor func testImageOnlyArticlePreservesPageWithoutInventingText() async throws {
        let url = try fixture(text: nil)
        let loaded = try await DocumentLoader.load(url, ocr: false, allowImageOnlyPDF: true)
        XCTAssertEqual(loaded.pages.count, 1)
        XCTAssertTrue(loaded.pages[0].text.isEmpty)
        XCTAssertFalse(loaded.warnings.isEmpty)
    }
    @MainActor func testScannedPDFUsesLocalOCR() async throws {
        let original = try fixture(text: "Synthetic study mean age was 68.5 years.")
        let originalPDF = PDFDocument(url: original)!
        let image = originalPDF.page(at: 0)!.thumbnail(of: CGSize(width: 1224, height: 1584), for: .mediaBox)
        let scanned = PDFDocument(); scanned.insert(PDFPage(image: image)!, at: 0)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        try XCTUnwrap(scanned.dataRepresentation()).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue((scanned.page(at: 0)?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        let loaded: LoadedDocument
        do { loaded = try await DocumentLoader.load(url, ocr: true) }
        catch {
            if error.localizedDescription.contains("Failed to create CVPixelBuffer") {
                throw XCTSkip("Vision cannot allocate its required pixel buffer in this managed execution environment. OCR remains unvalidated here; the application reports this failure and blocks extraction.")
            }
            throw error
        }
        XCTAssertTrue(loaded.pages[0].ocr)
        XCTAssertTrue(loaded.pages[0].text.contains("68.5"))
    }
}
