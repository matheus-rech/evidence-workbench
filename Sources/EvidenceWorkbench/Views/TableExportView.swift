import SwiftUI
import ReviewCore

struct TableExportView: View {
    @Environment(\.dismiss) private var dismiss
    @State var table: EditableTable
    @State private var checked = false
    @State private var message = ""
    var sourceImage: Data?
    var onSave: ((EditableTable) -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Editable table").font(.title2.weight(.semibold)); Spacer(); Button("Close") { dismiss() } }
            TextField("Table title", text: $table.title).textFieldStyle(.roundedBorder)
            Text("AI transcription · compare every cell with the original. Editing preserves the PDF source reference; it does not verify extracted observations.").font(.caption).foregroundStyle(.secondary)
            HSplitView {
                if let sourceImage, let image = NSImage(data: sourceImage) {
                    ScrollView([.horizontal, .vertical]) { Image(nsImage: image).resizable().scaledToFit().frame(width: 500) }.frame(minWidth: 250, idealWidth: 380)
                }
                ScrollView([.horizontal, .vertical]) {
                    Grid(alignment: .leading, horizontalSpacing: 4, verticalSpacing: 4) {
                        GridRow { ForEach(table.columns.indices, id: \.self) { column in TextField("Header", text: $table.columns[column]).font(.caption.bold()).frame(width: 150) } }
                        ForEach(table.rows.indices, id: \.self) { row in
                            GridRow { ForEach(table.columns.indices, id: \.self) { column in TextField("Cell", text: $table.rows[row][column], axis: .vertical).lineLimit(1...4).frame(width: 150) } }
                        }
                    }.textFieldStyle(.roundedBorder).padding(4)
                }.frame(minWidth: 350)
            }
            ForEach(table.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
            if !table.footnotes.isEmpty { Text(table.footnotes.joined(separator: "\n")).font(.caption).textSelection(.enabled) }
            Text(table.provenance).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(3)
            Toggle("I checked the table values, headers, units, missing cells and footnotes against the original", isOn: $checked).font(.caption)
            HStack {
                if let onSave { Button("Save checked table") { onSave(table); dismiss() } }
                Button("Copy for Word / rich text") { if act({ try RegionExport.copyTable(table, rich: true) }) { message = "Copied editable HTML/RTF table and plain-text fallback." } }
                Button("Copy TSV") { if act({ try RegionExport.copyTable(table, rich: false) }) { message = "Copied tab-separated cells for spreadsheets and text editors." } }
                Menu("Export table") { ForEach(["rtf", "html", "tsv", "csv"], id: \.self) { format in Button(format.uppercased()) { act { try RegionExport.saveTable(table, format: format) } } } }
            }.disabled(!checked)
            if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary) }
        }.padding(20).frame(minWidth: 850, idealWidth: 1100, minHeight: 600, idealHeight: 750)
        .onChange(of: table) { _, _ in checked = false; message = "" }
    }
    @discardableResult private func act(_ action: () throws -> Void) -> Bool { do { try action(); return true } catch { message = error.localizedDescription; return false } }
}
