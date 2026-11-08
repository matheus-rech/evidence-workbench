import PDFKit
import ReviewCore

enum PDFRegionGeometry {
    static func region(rect: CGRect, page: PDFPage) -> EvidenceRegion? {
        let crop = page.bounds(for: .cropBox)
        let clipped = rect.standardized.intersection(crop)
        guard crop.width > 0, crop.height > 0, !clipped.isNull, clipped.width >= 2, clipped.height >= 2 else { return nil }
        let result = EvidenceRegion(x: (clipped.minX - crop.minX) / crop.width, y: (clipped.minY - crop.minY) / crop.height, width: clipped.width / crop.width, height: clipped.height / crop.height)
        return result.isValid ? result : nil
    }
    static func rect(region: EvidenceRegion, page: PDFPage) -> CGRect? {
        guard region.isValid else { return nil }
        let crop = page.bounds(for: .cropBox)
        guard crop.width > 0, crop.height > 0 else { return nil }
        return CGRect(x: crop.minX + region.x * crop.width, y: crop.minY + region.y * crop.height, width: region.width * crop.width, height: region.height * crop.height)
    }
}
