import AppKit
import PDFKit
import Vision
import ReviewCore

struct LoadedDocument: Sendable {
    var data: Data
    var pages: [DocumentPage]
    var warnings: [String]
}

enum DocumentLoader {
    /// Reading up to 100 MB and parsing DOCX/PDF happens off the main actor; the security scope stays open until the read finishes.
    @MainActor static func load(_ url: URL, ocr: Bool, allowImageOnlyPDF: Bool = false) async throws -> LoadedDocument {
        let accessible = url.startAccessingSecurityScopedResource()
        defer { if accessible { url.stopAccessingSecurityScopedResource() } }
        let task = Task.detached(priority: .userInitiated) { try read(url, ocr: ocr, allowImageOnly: allowImageOnlyPDF) }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    private static func read(_ url: URL, ocr: Bool, allowImageOnly: Bool) throws -> LoadedDocument {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 100 * 1024 * 1024 else { throw WorkbenchError.invalid("Choose a document smaller than 100 MB.") }
        let data = try Data(contentsOf: url)
        let suffix = url.pathExtension.lowercased()
        if suffix == "pdf" { return try readPDF(data, ocr: ocr, allowImageOnly: allowImageOnly) }
        let text: String
        if suffix == "docx" {
            let attributed = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: nil)
            text = attributed.string
        } else if ["txt", "md"].contains(suffix), let string = String(data: data, encoding: .utf8) {
            text = string
        } else { throw WorkbenchError.invalid("Supported formats: PDF, DOCX, and UTF-8 TXT/Markdown.") }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WorkbenchError.invalid("This document has no readable text.") }
        guard text.count <= 2_000_000 else { throw WorkbenchError.invalid("Document text exceeds two million characters; split it into smaller reports.") }
        return LoadedDocument(data: data, pages: [.init(number: 1, text: text)], warnings: ["Non-PDF document: source locations refer to the imported text as page 1."])
    }

    private static func readPDF(_ data: Data, ocr: Bool, allowImageOnly: Bool) throws -> LoadedDocument {
        guard let document = PDFDocument(data: data), !document.isLocked else { throw WorkbenchError.invalid("The PDF is unreadable or password-protected. Import an unlocked copy.") }
        guard (1...400).contains(document.pageCount) else { throw WorkbenchError.invalid("Import PDFs with 1–400 pages; split longer reports into linked documents.") }
        var pages: [DocumentPage] = []; var warnings: [String] = []; var totalCharacters = 0
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { throw WorkbenchError.invalid("PDF page \(index + 1) could not be loaded.") }
            var text = page.string ?? ""; var usedOCR = false
            if text.trimmingCharacters(in: .whitespacesAndNewlines).count < 15, ocr {
                do { text = try recognize(page); usedOCR = true }
                catch { warnings.append("OCR failed on page \(index + 1): \(error.localizedDescription). Inspect this page manually.") }
            }
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { warnings.append("Page \(index + 1) has no extractable text. Missing fields may be unclear rather than absent.") }
            if usedOCR { warnings.append("Page \(index + 1) uses OCR. Quotes match the transcription, which may contain recognition errors; inspect the original page.") }
            totalCharacters += text.count
            guard totalCharacters <= 2_000_000 else { throw WorkbenchError.invalid("Document text exceeds two million characters; split it into linked reports.") }
            pages.append(.init(number: index + 1, text: text, ocr: usedOCR))
        }
        if !pages.contains(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            guard allowImageOnly else { throw WorkbenchError.invalid("No readable text was found, including OCR. " + warnings.joined(separator: " ")) }
            warnings.append("No readable page text was found. Original page images are available; visual AI must be enabled for extraction. Image findings require a drawn region and visual review, not a native-text match.")
        }
        return LoadedDocument(data: data, pages: pages, warnings: warnings)
    }

    private static func recognize(_ page: PDFPage) throws -> String {
        guard let cgPage = page.pageRef else { throw WorkbenchError.invalid("Could not rasterize the page for OCR.") }
        let bounds = cgPage.getBoxRect(.cropBox)
        guard bounds.width > 0, bounds.height > 0 else { throw WorkbenchError.invalid("PDF page has invalid dimensions.") }
        let scale = min(2.5, 1800 / max(bounds.width, bounds.height))
        let width = max(1, Int(bounds.width * scale)); let height = max(1, Int(bounds.height * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw WorkbenchError.invalid("Could not allocate the OCR page image.") }
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.concatenate(cgPage.getDrawingTransform(.cropBox, rect: CGRect(x: 0, y: 0, width: width, height: height), rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(cgPage)
        guard let image = context.makeImage() else { throw WorkbenchError.invalid("Could not render the OCR page.") }
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.usesLanguageCorrection = true; request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}
