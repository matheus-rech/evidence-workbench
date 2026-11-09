import Foundation
import PDFKit
import ReviewCore

/// A provisional, caption-bounded input for table OCR. Never asserts a precise data/figure box.
enum TablePageCropper {
    static func region(url: URL, pageNumber: Int, label: String) throws -> EvidenceRegion {
        guard let pdf = PDFDocument(url: url), pageNumber > 0, let page = pdf.page(at: pageNumber - 1), let text = page.string else { throw WorkbenchError.invalid("Specialist table OCR needs a readable caption or a reviewer-drawn crop. No source box was guessed.") }
        let wantedPattern = try NSRegularExpression(pattern: "(?i)table\\s+(\\d+)")
        guard let wanted = wantedPattern.firstMatch(in: label, range: NSRange(location: 0, length: (label as NSString).length)) else { throw WorkbenchError.invalid("Draw a precise box for an unlabeled table before specialist OCR.") }
        let number = (label as NSString).substring(with: wanted.range(at: 1))
        let captions = try NSRegularExpression(pattern: "(?im)^table\\s+(\\d+)\\.")
        let found = captions.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
        let matches = found.filter { (text as NSString).substring(with: $0.range(at: 1)) == number }
        guard matches.count == 1, let caption = page.selection(for: matches[0].range), !caption.bounds(for: page).isEmpty else { throw WorkbenchError.invalid("The table caption is missing or repeated. Draw a precise source box; no first occurrence was substituted.") }
        let bounds = page.bounds(for: .cropBox), top = min(bounds.maxY, caption.bounds(for: page).maxY + 8)
        let lowerCaptions = found.compactMap { page.selection(for: $0.range)?.bounds(for: page) }.filter { $0.maxY < caption.bounds(for: page).minY }
        let bottom = lowerCaptions.map(\.maxY).max().map { min(top, $0 + 6) } ?? bounds.minY
        let rect = CGRect(x: bounds.minX, y: bottom, width: bounds.width, height: top - bottom)
        guard let region = PDFRegionGeometry.region(rect: rect, page: page) else { throw WorkbenchError.invalid("The caption-bounded table region is invalid.") }
        return region
    }
}
