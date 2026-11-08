import PDFKit
import ReviewCore

enum PDFSourceAnchor {
    static func selection(document: PDFDocument, pageNumber: Int, quote: String, start: Int? = nil, length: Int? = nil) -> PDFSelection? {
        guard pageNumber > 0, let page = document.page(at: pageNumber - 1), let text = page.string,
              let range = QuoteLocator.resolve(in: text, quote: quote, start: start, length: length),
              let selection = page.selection(for: range), let selected = selection.string,
              QuoteLocator.normalized(selected) == QuoteLocator.normalized(quote) else { return nil }
        return selection
    }
}
