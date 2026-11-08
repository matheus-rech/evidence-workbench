import SwiftUI
import ReviewCore

struct AssetsView: View {
    @ObservedObject var store: WorkspaceStore
    var project: ReviewProject
    @State private var selectedID: UUID?
    @State private var reportID: UUID?
    @State private var kind = "All"
    @State private var query = ""
    @State private var showExcluded = false
    private var items: [SourceAsset] {
        (project.assets ?? []).filter { item in
            (reportID == nil || item.documentID == reportID) && (kind == "All" || item.kind.rawValue == kind) && (showExcluded || item.excluded != true) && (query.isEmpty || (item.label + " " + item.title).localizedCaseInsensitiveContains(query))
        }.sorted { a, b in a.documentID == b.documentID ? a.page < b.page : a.documentID.uuidString < b.documentID.uuidString }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tables & images").font(.title2.bold())
            Text("Article AI extraction fills this collection. Tables are editable drafts; figures retain original source pages until you draw a precise crop. Review before reuse.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Picker("Report", selection: $reportID) {
                    Text("All reports").tag(UUID?.none)
                    ForEach(project.documents) { Text($0.filename).tag(Optional($0.id)) }
                }
                Picker("Kind", selection: $kind) { Text("All").tag("All"); Text("Tables").tag("table"); Text("Images / figures").tag("figure") }.frame(maxWidth: 230)
                TextField("Find table or image", text: $query).textFieldStyle(.roundedBorder)
            }
            HStack {
                Menu("Find tables & images") {
                    ForEach(project.documents.filter { $0.relativePath.lowercased().hasSuffix(".pdf") }) { document in Button(document.filename) { store.findAssets(documentID: document.id) } }
                }.disabled(store.busy || !project.plan.readyForArticles || project.documents.isEmpty)
                Toggle("Show rejected detections", isOn: $showExcluded).font(.caption)
                Spacer(); Text("\(items.count) items").font(.caption)
            }
            HSplitView {
                List(items, selection: $selectedID) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        Label(item.label, systemImage: item.kind == .table ? "tablecells" : "photo").font(.headline)
                        Text(item.title).font(.caption).lineLimit(3)
                        Text("\(project.documents.first { $0.id == item.documentID }?.filename ?? "Missing source") · PDF page \(item.page)").font(.caption2).foregroundStyle(.secondary)
                        Text(item.excluded == true ? "Rejected detection" : (item.reviewedAt == nil ? "Needs review" : "Reviewer checked")).font(.caption2).foregroundStyle(item.reviewedAt == nil ? .orange : .green)
                    }.padding(.vertical, 5).tag(item.id)
                }.frame(minWidth: 220, idealWidth: 280, maxWidth: 330)
                if let selected = items.first(where: { $0.id == selectedID }) ?? items.first,
                   let document = project.documents.first(where: { $0.id == selected.documentID }) {
                    AssetDetailView(store: store, project: project, document: document, asset: selected).id(selected.id)
                } else {
                    ContentUnavailableView("Your source collection", systemImage: "photo.on.rectangle.angled", description: Text("Extract an article with AI, find assets for an existing report, or save a drawn region from the PDF reader.")).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }.padding(20)
    }
}

private struct AssetDetailView: View {
    @ObservedObject var store: WorkspaceStore
    var project: ReviewProject
    var document: SourceDocument
    var asset: SourceAsset
    @State private var image: Data?
    @State private var imageError = ""
    @State private var showTable = false
    @State private var showSource = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(asset.title.isEmpty ? asset.label : asset.title).font(.headline)
            Label(asset.exactCrop ? "Reviewer-drawn crop" : "Full-page source preview · precise crop not yet drawn", systemImage: "viewfinder").font(.caption).foregroundStyle(.secondary)
            if let image, let nsImage = NSImage(data: image) {
                ScrollView([.horizontal, .vertical]) { Image(nsImage: nsImage).resizable().scaledToFit().frame(maxWidth: 720) }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !imageError.isEmpty { Text(imageError).foregroundStyle(.orange) }
            else { ProgressView("Loading original source…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            if !asset.caption.isEmpty { Text(asset.caption).font(.caption).lineLimit(5).textSelection(.enabled) }
            ForEach(Array(asset.warnings.enumerated()), id: \.offset) { _, warning in Text(warning).font(.caption).foregroundStyle(.orange).lineLimit(3) }
            Text("\(document.filename) · physical PDF page \(asset.page) · SHA-256 \(asset.sourceSHA256)").font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
            HStack {
                Button("Open source / refine crop") { showSource = true }
                Button("Copy image") { act { if let image { try RegionExport.copyImage(image) } } }.disabled(image == nil)
                Button("Export PNG…") { act { if let image { try RegionExport.savePNG(image, name: "\(asset.kind.rawValue)_page_\(asset.page).png") } } }.disabled(image == nil)
            }
            HStack {
                if asset.table != nil { Button("Open editable table") { showTable = true } }
                else if asset.kind == .table { Button("Transcribe table") { store.transcribeAsset(asset) } }
                Button("Mark item checked") { store.saveAsset(asset, reviewed: true) }
                Button(asset.excluded == true ? "Restore detection" : "Reject detection") { var value = asset; value.excluded = asset.excluded != true; store.saveAsset(value, reviewed: true) }
            }.disabled(store.busy)
            Text("Checking a source item does not verify any dataset observation or establish extraction completeness.").font(.caption2).foregroundStyle(.secondary)
        }.padding(14)
        .task(id: "\(asset.id)-\(asset.region)-\(asset.sourceSHA256)") {
            image = nil; imageError = ""
            do { let url = try await store.repository.documentURL(document, projectID: project.id); image = try await RegionExport.image(url: url, pageNumber: asset.page, region: asset.exactCrop ? asset.region : nil) }
            catch { imageError = error.localizedDescription }
        }
        .sheet(isPresented: $showTable) {
            if let table = asset.table { TableExportView(table: table, sourceImage: image, onSave: { edited in var value = asset; value.table = edited; value.title = edited.title; store.saveAsset(value, reviewed: true) }) }
        }
        .sheet(isPresented: $showSource) { AssetSourceView(store: store, project: project, document: document, asset: asset) }
    }
    private func act(_ action: () throws -> Void) { do { try action() } catch { store.errorMessage = error.localizedDescription } }
}

private struct AssetSourceView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: WorkspaceStore
    var project: ReviewProject
    var document: SourceDocument
    var asset: SourceAsset
    @State private var url: URL?
    @State private var selection: SourceSelection?
    @State private var initialFocus: SourceSelection?
    var body: some View {
        VStack {
            HStack {
                Text("Original source · \(asset.label)").font(.headline)
                Spacer()
                Button("Save precise crop") {
                    guard let selection, let region = selection.region else { return }
                    var value = asset; value.region = region; value.page = selection.page; value.exactCrop = true; value.table = nil; value.origin = "Reviewer box"
                    value.warnings.append("Crop changed; regenerate and check any editable table against this crop.")
                    store.saveAsset(value); dismiss()
                }.disabled(selection?.region == nil || store.busy)
                Button("Close") { dismiss() }
            }.padding(12)
            SourceReader(store: store, document: document, url: url, focus: initialFocus) { selection = $0 }
        }.frame(minWidth: 850, minHeight: 650)
        .task { do { initialFocus = .init(page: asset.page, quote: "", region: asset.exactCrop ? asset.region : nil); url = try await store.repository.documentURL(document, projectID: project.id) } catch { store.errorMessage = error.localizedDescription } }
    }
}
