import AppKit
import PDFKit
import ReviewCore

enum PDFPageImages {
    static func render(url: URL, pageNumbers: [Int]) async throws -> [PageImage] {
        try await Task.detached(priority: .userInitiated) {
            guard let document = PDFDocument(url: url) else { throw WorkbenchError.invalid("The PDF could not be opened for visual analysis.") }
            let numbers = Array(Set(pageNumbers)).sorted()
            guard numbers.count <= 3 else { throw WorkbenchError.invalid("Visual batches are limited to three pages.") }
            return try numbers.map { number in
                try Task.checkCancellation()
                guard number > 0, let page = document.page(at: number - 1) else { throw WorkbenchError.invalid("Visual analysis requested a page outside this PDF.") }
                let image = page.thumbnail(of: NSSize(width: 1600, height: 1600), for: .cropBox)
                guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]), jpeg.count <= 4_000_000 else { throw WorkbenchError.invalid("A page image could not be encoded within the visual batch limit.") }
                return PageImage(page: number, dataURL: "data:image/jpeg;base64," + jpeg.base64EncodedString())
            }
        }.value
    }
}
