import SwiftUI
import ReviewCore

enum WorkspacePage: String, CaseIterable, Identifiable {
    case plan = "Protocol & plan", articles = "Articles & extraction", assets = "Tables & images", dataset = "Evidence dataset", audit = "Audit trail"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .plan: return "list.clipboard"; case .articles: return "doc.text.magnifyingglass"; case .assets: return "photo.on.rectangle.angled"; case .dataset: return "tablecells"; case .audit: return "clock.arrow.circlepath" }
    }
}

struct ContentView: View {
    @ObservedObject var store: WorkspaceStore
    @State private var page: WorkspacePage = .plan
    @State private var showAgent = true
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 16) {
                Label("Evidence Workbench", systemImage: "books.vertical.fill").font(.headline).padding(.horizontal, 14).padding(.top, 12)
                if Bundle.main.bundleIdentifier?.hasSuffix(".QA") == true { Text("QA TEST COPY · separate review files").font(.caption.bold()).foregroundStyle(.orange).padding(.horizontal, 14) }
                VStack(alignment: .leading, spacing: 8) {
                    Text("REVIEW WORKSPACE").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    Picker("Review", selection: projectSelection) {
                        Text("Choose a review").tag(UUID?.none)
                        ForEach(store.projects) { project in Text(project.title).tag(Optional(project.id)) }
                    }.labelsHidden()
                    Button(action: store.newProject) { Label("New review", systemImage: "plus") }.disabled(store.busy || store.loading || store.hasUnsavedChanges)
                }.padding(.horizontal, 14)
                List(selection: pageSelection) {
                    Section("Workflow") {
                        ForEach(WorkspacePage.allCases) { destination in Label(destination.rawValue, systemImage: destination.symbol).tag(destination) }
                    }
                }.listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 10) {
                    Label("Local sources. Traceable evidence.", systemImage: "externaldrive.badge.checkmark").font(.caption).foregroundStyle(.secondary)
                    SettingsLink { Label("AI & preferences", systemImage: "gearshape") }
                    Button("Restore backup…") { FilePanels.restore(store) }.disabled(store.busy || store.hasUnsavedChanges)
                }.buttonStyle(.plain).padding(14)
            }.navigationSplitViewColumnWidth(min: 220, ideal: 235, max: 280)
        } detail: {
            if store.loading {
                VStack(spacing: 12) { ProgressView(); Text("Loading saved review files…") }
            } else if let project = store.current {
                VStack(spacing: 0) {
                    reviewHeader(project)
                    Divider()
                    HSplitView {
                        Group {
                            switch page {
                            case .plan: PlanEditorView(store: store, project: project)
                            case .articles: ArticlesView(store: store, project: project)
                            case .assets: AssetsView(store: store, project: project)
                            case .dataset: DatasetView(store: store, project: project)
                            case .audit: AuditView(project: project)
                            }
                        }.frame(minWidth: 530, maxWidth: .infinity, maxHeight: .infinity)
                        if showAgent { AgentView(store: store, project: project).frame(minWidth: 290, idealWidth: 340, maxWidth: 450) }
                    }
                    if store.busy {
                        Divider()
                        HStack(spacing: 12) {
                            ProgressView().controlSize(.small)
                            Text(store.progress).font(.callout).lineLimit(2)
                            Spacer()
                            Button("Cancel", action: store.cancelOperation)
                        }.padding(10).background(.bar)
                    }
                    if let notice = store.notice {
                        Divider()
                        HStack { Image(systemName: "info.circle"); Text(notice).font(.caption); Spacer(); Button { store.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }.padding(10)
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("Build an extraction plan first", systemImage: "books.vertical")
                } description: {
                    Text("Start any systematic review with a research question, a protocol and a defined PICOTT. Your articles and evidence stay together in a reproducible workspace.")
                } actions: {
                    Button("Create review", action: store.newProject).buttonStyle(.borderedProminent).disabled(store.busy)
                }
            }
        }
        .toolbar {
            ToolbarItem { Button { showAgent.toggle() } label: { Label("Planning agent", systemImage: "bubble.left.and.bubble.right") }.help("Show or hide the protocol and research assistant") }
        }
        .task { await store.loadProjects() }
        .alert("Action could not be completed", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }

    private var projectSelection: Binding<UUID?> {
        Binding(get: { store.selectedProjectID }, set: { id in
            guard !store.busy else { return }
            guard !store.hasUnsavedChanges else { store.errorMessage = "Save or discard your draft edits before switching reviews."; return }
            store.selectedProjectID = id; page = .plan
        })
    }
    private var pageSelection: Binding<WorkspacePage?> {
        Binding(get: { page }, set: { value in
            guard let value, !store.busy else { return }
            guard !store.hasUnsavedChanges || value == page else { store.errorMessage = "Save or discard your edits before leaving the editor."; return }
            page = value
        })
    }
    private func reviewHeader(_ project: ReviewProject) -> some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(project.title).font(.title2.weight(.semibold)).lineLimit(1)
                Text("\(project.plan.framework) · \(project.plan.reviewType) · Plan v\(project.plan.version)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            statusPill(project.plan.readyForArticles ? "Plan approved" : "Define & approve plan", symbol: project.plan.readyForArticles ? "checkmark.seal.fill" : "pencil.and.outline", color: project.plan.readyForArticles ? .green : .orange)
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(project.documents.count) reports · \(Set(project.documents.map(\.studyID)).count) studies").font(.callout)
                Text("\(project.observations.filter { $0.status == .verified && $0.planVersion == project.plan.version && SourceCheckPolicy.resolved($0) }.count) verified observations ready to export").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.horizontal, 24).padding(.vertical, 18)
    }
}

func statusPill(_ title: String, symbol: String, color: Color) -> some View {
    Label(title, systemImage: symbol).font(.caption.weight(.medium)).foregroundStyle(color).padding(.horizontal, 10).padding(.vertical, 6).background(color.opacity(0.10), in: Capsule())
}

struct FieldBlock: View {
    var label: String
    var placeholder = ""
    @Binding var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.callout.weight(.semibold))
            TextField(placeholder, text: $text, axis: .vertical).lineLimit(2...5).textFieldStyle(.roundedBorder)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
