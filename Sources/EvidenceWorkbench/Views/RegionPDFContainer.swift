import AppKit
import PDFKit
import ReviewCore

/// The transparent overlay receives drags only while the explicit region tool is active.
final class RegionPDFContainer: NSView {
    let pdf = PDFView()
    let overlay = PDFRegionOverlay()
    private var box: PDFAnnotation?
    private weak var boxPage: PDFPage?
    override init(frame: NSRect) {
        super.init(frame: frame)
        pdf.autoScales = true; pdf.displayMode = .singlePageContinuous; pdf.displayDirection = .vertical
        for child in [pdf, overlay] { child.translatesAutoresizingMaskIntoConstraints = false; addSubview(child); NSLayoutConstraint.activate([child.leadingAnchor.constraint(equalTo: leadingAnchor), child.trailingAnchor.constraint(equalTo: trailingAnchor), child.topAnchor.constraint(equalTo: topAnchor), child.bottomAnchor.constraint(equalTo: bottomAnchor)]) }
        overlay.host = self
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    func clearBox() { if let box { boxPage?.removeAnnotation(box) }; box = nil; boxPage = nil }
    func showBox(_ rect: CGRect, page: PDFPage) {
        clearBox()
        let annotation = PDFAnnotation(bounds: rect, forType: .square, withProperties: nil)
        annotation.color = .systemBlue; annotation.interiorColor = .clear
        let border = PDFBorder(); border.lineWidth = 2; annotation.border = border
        page.addAnnotation(annotation); box = annotation; boxPage = page
    }
}

final class PDFRegionOverlay: NSView {
    weak var host: RegionPDFContainer?
    var enabled = false { didSet { if !enabled { start = nil; sourcePage = nil } } }
    var onSelect: ((SourceSelection) -> Void)?
    private var start: CGPoint?
    private weak var sourcePage: PDFPage?
    override func hitTest(_ point: NSPoint) -> NSView? { enabled && bounds.contains(point) ? self : nil }
    override func resetCursorRects() { if enabled { addCursorRect(bounds, cursor: .crosshair) } }
    override func mouseDown(with event: NSEvent) {
        guard let host else { return }
        let location = host.pdf.convert(event.locationInWindow, from: nil)
        guard let page = host.pdf.page(for: location, nearest: false) else { return }
        start = host.pdf.convert(location, to: page); sourcePage = page; host.clearBox()
    }
    private func selection(_ event: NSEvent) -> (PDFPage, CGRect)? {
        guard let host, let start, let page = sourcePage else { return nil }
        let location = host.pdf.convert(event.locationInWindow, from: nil)
        guard host.pdf.page(for: location, nearest: false) === page else { return nil }
        let end = host.pdf.convert(location, to: page)
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y)).intersection(page.bounds(for: .cropBox))
        return (page, rect)
    }
    override func mouseDragged(with event: NSEvent) { if let (page, rect) = selection(event) { host?.showBox(rect, page: page) } }
    override func mouseUp(with event: NSEvent) {
        defer { start = nil; sourcePage = nil }
        guard let host, let document = host.pdf.document, let (page, rect) = selection(event), let region = PDFRegionGeometry.region(rect: rect, page: page) else { host?.clearBox(); return }
        host.showBox(rect, page: page)
        onSelect?(.init(page: document.index(for: page) + 1, quote: "", region: region))
    }
}
