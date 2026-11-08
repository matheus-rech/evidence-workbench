import SwiftUI
import PDFKit
import ReviewCore

struct SourceSelection: Equatable {
    var page: Int
    var quote: String
    var startUTF16: Int? = nil
    var lengthUTF16: Int? = nil
    var region: EvidenceRegion? = nil
    var requestID = UUID()
}

struct SourceReader: View {
    @ObservedObject var store: WorkspaceStore
    var document: SourceDocument
    var url: URL?
    var focus: SourceSelection?
    var onSelect: (SourceSelection) -> Void
    @State private var showText = false
    @State private var sourceStatus = ""
    @State private var drawRegion = false
    @State private var selectedArea: SourceSelection?
    @State private var convertedAsset: SourceAsset?
    @State private var tableImage: Data?
    @State private var imagePage = 1
    @State private var navigation: SourceSelection?
    private var activeFocus: SourceSelection? { navigation ?? focus }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Source report", systemImage: "doc.richtext").font(.callout.weight(.semibold))
                Spacer()
                if url?.pathExtension.lowercased() == "pdf", !showText {
                    Toggle("Draw data box", isOn: $drawRegion).toggleStyle(.button).controlSize(.small)
                }
                Toggle("Page text", isOn: $showText).toggleStyle(.switch).controlSize(.small)
            }.padding(12)
            if url?.pathExtension.lowercased() == "pdf" {
                HStack {
                    Stepper("Page \(imagePage)", value: Binding(get: { imagePage }, set: { imagePage = $0; navigation = .init(page: $0, quote: "") }), in: 1...max(document.pages.count, 1)).font(.caption)
                    Spacer()
                    Menu("Copy / export") {
                        Button("Copy page image") { exportImage(region: nil, copy: true) }
                        Button("Export page PNG…") { exportImage(region: nil, copy: false) }
                        Divider()
                        Button("Copy boxed image") { exportImage(region: selectedArea, copy: true) }.disabled(selectedArea?.region == nil)
                        Button("Export boxed PNG…") { exportImage(region: selectedArea, copy: false) }.disabled(selectedArea?.region == nil)
                        Button("Save boxed image to Tables & images") {
                            guard let area = selectedArea, let region = area.region else { return }
                            store.saveAsset(.init(documentID: document.id, sourceSHA256: document.sha256, page: area.page, kind: .figure, label: "Reviewer crop \(UUID().uuidString.prefix(8))", title: "Boxed image · \(document.filename) · page \(area.page)", region: region, exactCrop: true, origin: "Reviewer box"))
                        }.disabled(selectedArea?.region == nil)
                        Button("Convert boxed table to editable text…") {
                            guard let area = selectedArea, let url else { return }
                            Task {
                                do { tableImage = try await RegionExport.image(url: url, pageNumber: area.page, region: area.region) }
                                catch { store.errorMessage = error.localizedDescription; return }
                                store.convertTable(documentID: document.id, selection: area) { convertedAsset = $0 }
                            }
                        }.disabled(selectedArea?.region == nil)
                    }.font(.caption).disabled(store.busy)
                }.padding(.horizontal, 12).padding(.bottom, 8)
            }
            Divider()
            if let url, url.pathExtension.lowercased() == "pdf", !showText {
                NativePDFView(url: url, focus: navigation ?? focus, drawRegion: drawRegion, onSelect: { area in selectedArea = area; imagePage = area.page; onSelect(area) }) { sourceStatus = $0 }
            } else if url != nil {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 24) {
                            ForEach(document.pages, id: \.number) { page in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("PAGE \(page.number)\(page.ocr ? " · OCR TRANSCRIPTION" : "")").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                                    if let focus = activeFocus, focus.page == page.number, focus.region != nil {
                                        Label("Image-region evidence: inspect the saved box in the PDF view. This transcription is not an exact native-text match.", systemImage: "viewfinder").font(.caption).foregroundStyle(.blue)
                                    }
                                    Text(highlighted(page)).font(.system(.body, design: .serif)).textSelection(.enabled).lineSpacing(5).frame(maxWidth: .infinity, alignment: .leading)
                                    if page.text.isEmpty { Text("No extractable text. Inspect the original page.").foregroundStyle(.orange) }
                                }.padding(18).id(page.number)
                            }
                        }
                    }.task(id: activeFocus?.requestID) { if let target = activeFocus { proxy.scrollTo(target.page, anchor: .top) } }
                }
            } else {
                ContentUnavailableView("Loading source…", systemImage: "doc")
            }
            if !sourceStatus.isEmpty { Text(sourceStatus).font(.caption).foregroundStyle(.secondary).padding(10) }
            Divider()
            Text(drawRegion && !showText ? "Drag a box around one data cell or figure region on a single page. Attach it to the selected observation, transcribe the data and check its units, group and time point." : "Select PDF text for an exact quote, or use Draw data box in the PDF view for image evidence. Boxes are stored with the observation; the original PDF is not modified.").font(.caption2).foregroundStyle(.secondary).padding(10)
        }
        .sheet(item: $convertedAsset) { asset in
            if let table = asset.table {
                // Edits made here persist to the same Tables & images entry that convertTable created.
                TableExportView(table: table, sourceImage: tableImage, onSave: { edited in var value = asset; value.table = edited; value.title = edited.title; store.saveAsset(value, reviewed: true) })
            }
        }
        .onChange(of: focus) { _, value in
            navigation = nil; selectedArea = value?.region == nil ? nil : value
            if let value { imagePage = value.page }
            if showText { updateTextStatus() }
        }
        .onChange(of: showText) { _, value in if value { updateTextStatus() } }
        .onChange(of: navigation) { _, value in
            if value != nil { selectedArea = nil }
            if showText { updateTextStatus() }
        }
    }
    private func updateTextStatus() {
        guard let target = activeFocus else { sourceStatus = "Select an observation to highlight its supporting passage."; return }
        guard let page = document.pages.first(where: { $0.number == target.page }) else { sourceStatus = "Source page is unavailable."; return }
        if target.region != nil { sourceStatus = "Image-region evidence on page \(target.page). Switch off Page text to inspect the saved box." }
        else if target.quote.isEmpty { sourceStatus = "Page \(target.page). No quotation selected." }
        else if QuoteLocator.resolve(in: page.text, quote: target.quote, start: target.startUTF16, length: target.lengthUTF16) != nil {
            sourceStatus = "Matched the exact supporting passage on page \(target.page)\(page.ocr ? " in the OCR transcription; check the original image" : "")."
        } else { sourceStatus = "The quotation is missing or ambiguous on page \(target.page). No guessed text highlight was drawn." }
    }
    private func exportImage(region selection: SourceSelection?, copy: Bool) {
        guard let projectID = store.current?.id else { return }
        let page = selection?.page ?? imagePage
        Task {
            do {
                let url = try await store.repository.documentURL(document, projectID: projectID)
                let png = try await RegionExport.image(url: url, pageNumber: page, region: selection?.region)
                if copy { try RegionExport.copyImage(png); sourceStatus = "Copied \(selection == nil ? "page" : "boxed region") \(page) as an image." }
                else { try RegionExport.savePNG(png, name: "\(selection == nil ? "page" : "region")_\(page).png") }
            } catch { store.errorMessage = error.localizedDescription }
        }
    }
    private func highlighted(_ page: DocumentPage) -> AttributedString {
        var text = AttributedString(page.text)
        if let focus = activeFocus, focus.region == nil, focus.page == page.number,
           let nsRange = QuoteLocator.resolve(in: page.text, quote: focus.quote, start: focus.startUTF16, length: focus.lengthUTF16),
           let range = Range(nsRange, in: page.text) {
            var mark = AttributedString(String(page.text[range])); mark.backgroundColor = .yellow.opacity(0.35)
            text = AttributedString(String(page.text[..<range.lowerBound])) + mark + AttributedString(String(page.text[range.upperBound...]))
        }
        return text
    }
}

struct NativePDFView: NSViewRepresentable {
    var url: URL
    var focus: SourceSelection?
    var drawRegion: Bool
    var onSelect: (SourceSelection) -> Void
    var onStatus: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }
    func makeNSView(context: Context) -> RegionPDFContainer {
        let host = RegionPDFContainer(frame: .zero)
        let view = host.pdf
        context.coordinator.observer = NotificationCenter.default.addObserver(forName: .PDFViewSelectionChanged, object: view, queue: .main) { [weak view, weak coordinator = context.coordinator] _ in
            guard let view, let document = view.document, let selection = view.currentSelection, selection.pages.count == 1, let page = selection.pages.first, let quote = selection.string, !quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let range = selection.range(at: 0, on: page)
            coordinator?.onSelect(.init(page: document.index(for: page) + 1, quote: quote, startUTF16: range.location, lengthUTF16: range.length))
        }
        return host
    }
    func updateNSView(_ host: RegionPDFContainer, context: Context) {
        let view = host.pdf
        context.coordinator.onSelect = onSelect
        host.overlay.enabled = drawRegion
        host.overlay.onSelect = onSelect
        host.window?.invalidateCursorRects(for: host.overlay)
        if context.coordinator.url != url {
            host.clearBox()
            view.document = PDFDocument(url: url); context.coordinator.url = url; context.coordinator.lastFocus = nil
        }
        if focus == nil, context.coordinator.lastFocus != nil {
            context.coordinator.lastFocus = nil; view.highlightedSelections = []; view.clearSelection(); host.clearBox()
            DispatchQueue.main.async { onStatus("") }
        }
        if let focus, context.coordinator.lastFocus != focus, let pdf = view.document {
            context.coordinator.lastFocus = focus
            view.highlightedSelections = []
            view.clearSelection(); host.clearBox()
            guard focus.page > 0, let page = pdf.page(at: focus.page - 1) else {
                DispatchQueue.main.async { onStatus("Source page is unavailable. No highlight was drawn.") }; return
            }
            view.go(to: page)
            if focus.region == nil, focus.quote.isEmpty {
                DispatchQueue.main.async { onStatus("PDF page \(focus.page). Draw a region or select text to attach evidence.") }
                return
            }
            if let region = focus.region {
                guard let rect = PDFRegionGeometry.rect(region: region, page: page) else { DispatchQueue.main.async { onStatus("Invalid source region. No box was drawn.") }; return }
                host.showBox(rect, page: page)
                reveal(rect, on: page, in: view)
                DispatchQueue.main.async { onStatus("Opened the reviewer-drawn data box on PDF page \(focus.page). The box locates evidence; verify the value and context separately.") }
                return
            }
            if let selection = PDFSourceAnchor.selection(document: pdf, pageNumber: focus.page, quote: focus.quote, start: focus.startUTF16, length: focus.lengthUTF16) {
                selection.color = .systemYellow
                view.highlightedSelections = [selection]
                reveal(selection.bounds(for: page), on: page, in: view)
                DispatchQueue.main.async { onStatus("Matched the exact supporting text on PDF page \(focus.page).") }
            } else {
                DispatchQueue.main.async { onStatus("Opened PDF page \(focus.page), but the quote is missing, repeated, or has no PDF text layer. No guessed highlight was drawn. For repeated text, select the intended occurrence; for OCR, inspect Page text.") }
            }
        }
    }

    private func reveal(_ rect: CGRect, on page: PDFPage, in view: PDFView) {
        // Defer until PDFKit has laid out the target page; scrolling before layout can hide the matched row.
        DispatchQueue.main.async {
            view.layoutSubtreeIfNeeded()
            view.go(to: rect.insetBy(dx: -18, dy: -60), on: page)
        }
    }
    static func dismantleNSView(_ nsView: RegionPDFContainer, coordinator: Coordinator) {
        if let observer = coordinator.observer { NotificationCenter.default.removeObserver(observer) }
        nsView.clearBox(); nsView.overlay.onSelect = nil; nsView.pdf.document = nil
    }
    final class Coordinator {
        var url: URL?
        var observer: NSObjectProtocol?
        var lastFocus: SourceSelection?
        var onSelect: (SourceSelection) -> Void
        init(onSelect: @escaping (SourceSelection) -> Void) { self.onSelect = onSelect }
    }
}
