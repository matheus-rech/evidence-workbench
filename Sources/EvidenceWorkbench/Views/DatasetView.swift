import SwiftUI
import ReviewCore

struct DatasetView: View {
    @ObservedObject var store: WorkspaceStore
    var project: ReviewProject
    @State private var query = ""
    @State private var verifiedOnly = false
    @State private var currentOnly = true
    private var rows: [Observation] {
        project.observations.filter { row in
            (!verifiedOnly || row.status == .verified) && (!currentOnly || row.planVersion == project.plan.version) && (query.isEmpty || [row.value, row.context.summary, label(row)].joined(separator: " ").localizedCaseInsensitiveContains(query))
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Evidence dataset").font(.largeTitle.weight(.bold))
                Text("One observation per variable and context. Report IDs remain distinct; study IDs link publications that describe the same underlying study.").foregroundStyle(.secondary)
            }
            HStack(spacing: 18) {
                metric("Studies", count: Set(project.documents.map(\.studyID)).count)
                metric("Reports", count: project.documents.count)
                metric("Verified · current plan", count: project.observations.filter { $0.status == .verified && $0.planVersion == project.plan.version }.count)
                metric("Pending review", count: project.observations.filter { [.suggested, .edited].contains($0.status) }.count)
            }.padding(16).frame(maxWidth: .infinity).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            HStack {
                TextField("Search variable, value or context", text: $query).textFieldStyle(.roundedBorder)
                Toggle("Verified", isOn: $verifiedOnly).toggleStyle(.checkbox)
                Toggle("Current plan", isOn: $currentOnly).toggleStyle(.checkbox)
            }
            List {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(label(row)).font(.headline)
                                Text(project.documents.first { $0.id == row.documentID }?.filename ?? "Missing source").font(.caption).foregroundStyle(.secondary)
                            }.frame(width: 200, alignment: .leading)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.missingness == .reported ? row.value : row.missingness.rawValue).textSelection(.enabled)
                                if !row.context.summary.isEmpty { Text(row.context.summary).font(.caption).foregroundStyle(.secondary) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .trailing, spacing: 4) { Text(row.status.rawValue).font(.caption.weight(.medium)).foregroundStyle(row.status == .verified ? .green : .secondary); Text("Plan v\(row.planVersion)").font(.caption2).foregroundStyle(.secondary) }
                        }
                        if let citation = row.citations.first { Text("p. \(citation.page): “\(citation.quote)”").font(.caption).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled) }
                    }.padding(.vertical, 7)
                }
            }.overlay { if rows.isEmpty { ContentUnavailableView("No matching observations", systemImage: "tablecells", description: Text("Import articles after plan approval, then extract or enter evidence manually.")) } }
            Text("Verified exports contain only the current plan version. Before meta-analysis, select a consistent outcome, effect measure, analysis population and time point; resolve overlapping reports and dependent comparisons. No statistical pooling is performed by this app.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Export all + provenance…") { FilePanels.exportCSV(store, verifiedOnly: false) }
                Button("Back up full review…") { FilePanels.backup(store) }
                Spacer()
                Button("Export verified…") { FilePanels.exportCSV(store, verifiedOnly: true) }.buttonStyle(.borderedProminent)
            }.disabled(store.busy)
        }.padding(24)
    }
    private func label(_ row: Observation) -> String { project.plan.variables.first { $0.id == row.variableID }?.label ?? "Archived field · \(row.variableID)" }
    private func metric(_ title: String, count: Int) -> some View { VStack(alignment: .leading, spacing: 4) { Text("\(count)").font(.title.weight(.semibold)); Text(title).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading) }
}
