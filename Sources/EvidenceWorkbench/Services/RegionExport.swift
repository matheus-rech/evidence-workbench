import AppKit
import PDFKit
import UniformTypeIdentifiers
import ReviewCore

enum RegionExport {
    static func image(url: URL, pageNumber: Int, region: EvidenceRegion?) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            guard pageNumber > 0, let pdf = PDFDocument(url: url), let original = pdf.page(at: pageNumber - 1), let page = original.copy() as? PDFPage else { throw WorkbenchError.invalid("The selected PDF page is unavailable.") }
            if let region {
                guard let rect = PDFRegionGeometry.rect(region: region, page: page) else { throw WorkbenchError.invalid("The image region is invalid.") }
                page.setBounds(rect, for: .cropBox)
            }
            let image = page.thumbnail(of: NSSize(width: 1800, height: 1800), for: .cropBox)
            guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]), png.count <= 20_000_000 else { throw WorkbenchError.invalid("The selected image could not be rendered within the export limit.") }
            return png
        }.value
    }
    static func jpeg(_ png: Data, page: Int) throws -> PageImage {
        guard let bitmap = NSBitmapImageRep(data: png), let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]), jpeg.count <= 4_000_000 else { throw WorkbenchError.invalid("The table image could not be prepared for AI.") }
        return PageImage(page: page, dataURL: "data:image/jpeg;base64," + jpeg.base64EncodedString())
    }
    @MainActor static func copyImage(_ png: Data) throws {
        guard let image = NSImage(data: png), let tiff = image.tiffRepresentation else { throw WorkbenchError.invalid("Could not copy this image.") }
        let item = NSPasteboardItem(); item.setData(png, forType: .png); item.setData(tiff, forType: .tiff)
        NSPasteboard.general.clearContents(); guard NSPasteboard.general.writeObjects([item]) else { throw WorkbenchError.invalid("The image could not be written to the clipboard.") }
    }
    @MainActor static func savePNG(_ png: Data, name: String) throws {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = name
        if panel.runModal() == .OK, let url = panel.url { try png.write(to: url, options: .atomic) }
    }
    @MainActor static func copyTable(_ table: EditableTable, rich: Bool) throws {
        try table.validate()
        let item = NSPasteboardItem(); item.setString(table.tsv, forType: .string)
        if rich { item.setString(table.html, forType: .html); item.setData(Data(table.rtf.utf8), forType: .rtf) }
        NSPasteboard.general.clearContents(); guard NSPasteboard.general.writeObjects([item]) else { throw WorkbenchError.invalid("The table could not be written to the clipboard.") }
    }
    @MainActor static func saveTable(_ table: EditableTable, format: String) throws {
        try table.validate()
        let content: String; let type: UTType
        switch format {
        case "rtf": content = table.rtf; type = .rtf
        case "html": content = table.html; type = .html
        case "tsv": content = table.tsv; type = UTType(filenameExtension: "tsv") ?? .plainText
        default: content = table.csv; type = .commaSeparatedText
        }
        let panel = NSSavePanel(); panel.allowedContentTypes = [type]; panel.nameFieldStringValue = "table_page_\(table.page).\(format)"
        if panel.runModal() == .OK, let url = panel.url { try Data(content.utf8).write(to: url, options: .atomic) }
    }
}
