import SwiftUI
import ReviewCore

struct ArticlesView: View {
    @ObservedObject var store: WorkspaceStore
    var project: ReviewProject
    @State private var selectedDocumentID: UUID?
    private var selected: SourceDocument? { project.documents.first { $0.id == selectedDocumentID } ?? project.documents.first }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Article reports & extraction").font(.title2.weight(.semibold))
                    Text("Link reports from the same study. Preserve arms, outcomes and time points.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { FilePanels.importFiles(store, protocolOnly: false) } label: { Label("Import articles", systemImage: "plus") }.buttonStyle(.borderedProminent).disabled(!project.plan.readyForArticles || store.busy)
            }.padding(20)
            if !project.plan.readyForArticles {
                Label("Approve the extraction plan before importing articles or changing extracted data.", systemImage: "lock.fill").font(.callout).foregroundStyle(.orange).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.07))
            }
            if let selected {
                HStack {
                    Picker("Report", selection: Binding(get: { selected.id }, set: { id in
                        guard !store.hasUnsavedObservation else { store.errorMessage = "Save or discard observation edits before switching reports."; return }
                        selectedDocumentID = id
                    })) {
                        ForEach(project.documents) { document in Text(document.filename).tag(document.id) }
                    }.disabled(store.busy)
                    Spacer()
                    Text("\(selected.pages.count) pages").font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal, 20).padding(.bottom, 12)
                Divider()
                ArticleWorkspace(store: store, project: project, document: selected).id(selected.id)
            } else {
                Spacer()
                ContentUnavailableView {
                    Label(project.plan.readyForArticles ? "Ready for your first report" : "Your plan comes first", systemImage: project.plan.readyForArticles ? "doc.badge.plus" : "list.clipboard")
                } description: { Text(project.plan.readyForArticles ? "Import a peer-reviewed article. Original sources are copied into the review; nothing is sent to AI until you request extraction." : "Complete PICOTT, define the extraction dictionary and approve the plan in Protocol & plan.") }
                Spacer()
            }
        }
    }
}

private struct ArticleWorkspace: View {
    @ObservedObject var store: WorkspaceStore
    var project: ReviewProject
    var document: SourceDocument
    @AppStorage("extractAssets") private var extractAssets = true
    @State private var sourceURL: URL?
    @State private var focus: SourceSelection?
    @State private var selection: SourceSelection?
    @State private var reportMetadata: SourceDocument
    @State private var query = ""
    @State private var statusFilter = "All"
    @State private var showEarlierPlans = false
    @State private var observationID: UUID?
    @State private var newObservation: Observation?
    @State private var showNewObservation = false
    @State private var chosenVariable = "title"

    init(store: WorkspaceStore, project: ReviewProject, document: SourceDocument) {
        self.store = store; self.project = project; self.document = document
        _reportMetadata = State(initialValue: document)
    }
    private var observations: [Observation] {
        project.observations.filter { row in
            row.documentID == document.id && (showEarlierPlans || row.planVersion == project.plan.version) && (statusFilter == "All" || row.status.rawValue == statusFilter) && (query.isEmpty || [project.plan.variables.first { $0.id == row.variableID }?.label ?? row.variableID, row.value, row.context.summary].joined(separator: " ").localizedCaseInsensitiveContains(query))
        }
    }
    private var selectedObservation: Observation? { newObservation ?? project.observations.first { $0.id == observationID } }
    private var studies: [SourceDocument] {
        var seen: Set<UUID> = []
        return project.documents.filter { seen.insert($0.studyID).inserted }
    }
    var body: some View {
        VStack(spacing: 0) {
            DisclosureGroup("Report identity · \(document.peerReviewStatus) · study \(document.studyID.uuidString.prefix(8))") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Picker("Peer-review status", selection: $reportMetadata.peerReviewStatus) {
                            ForEach(["Unconfirmed", "Reviewer confirmed", "Not peer reviewed"], id: \.self) { Text($0) }
                        }
                        Picker("Underlying study", selection: $reportMetadata.studyID) {
                            ForEach(studies) { report in Text("\(report.studyID.uuidString.prefix(8)) · \(report.filename)").tag(report.studyID) }
                            if !studies.contains(where: { $0.studyID == reportMetadata.studyID }) { Text("New separate study").tag(reportMetadata.studyID) }
                        }
                    }
                    HStack {
                        Button("Separate into a new study") { reportMetadata.studyID = UUID() }
                        Button("Save linkage / status") { store.updateReport(reportMetadata) }.disabled(store.busy)
                    }
                    Text("SHA-256: \(document.sha256)").font(.caption2.monospaced()).textSelection(.enabled).foregroundStyle(.secondary)
                    Text("Linking reports prevents treating each publication as an independent study. Conflicting estimates remain separate for adjudication; the app does not pool them automatically.").font(.caption).foregroundStyle(.secondary)
                    ForEach(document.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                }.padding(.top, 10)
            }.padding(12).font(.caption)
            Divider()
            HSplitView {
                SourceReader(store: store, document: document, url: sourceURL, focus: focus) { selection = $0 }.frame(minWidth: 270, maxWidth: .infinity)
                VStack(spacing: 0) {
                    HStack {
                        Text("Observations").font(.headline)
                        Spacer()
                        Button { showNewObservation = true } label: { Image(systemName: "plus") }.help("Add a manual observation").disabled(store.busy || store.hasUnsavedObservation || !project.plan.readyForArticles)
                        Button("Extract with AI") { store.extract(documentID: document.id) }.buttonStyle(.borderedProminent).disabled(store.busy || store.hasUnsavedObservation || !project.plan.readyForArticles)
                    }.padding(12)
                    Text("AI sends this report’s text and, when enabled, page images to OpenAI and preserves edited, verified and rejected rows. Scores are model estimates, not calibrated probabilities.").font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.bottom, 8)
                    Toggle("Also populate Tables & images", isOn: $extractAssets).font(.caption).padding(.horizontal, 12).padding(.bottom, 8).disabled(store.busy)
                    if !project.plan.variables.contains(where: { $0.id == "outcome_proportion" }) {
                        Text("This plan has no dedicated percentage/rate outcome fields. Missing outcome mean or SD does not mean no outcomes were reported. Amend the plan to add percentage/rate fields when relevant.").font(.caption).foregroundStyle(.orange).padding(.horizontal, 12).padding(.bottom, 8)
                    }
                    HStack {
                        TextField("Find variable, value or context", text: $query).textFieldStyle(.roundedBorder)
                        Picker("Status", selection: $statusFilter) { Text("All").tag("All"); ForEach(ObservationStatus.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) } }.labelsHidden().frame(width: 105)
                    }.padding(.horizontal, 12).padding(.bottom, 8)
                    if project.observations.contains(where: { $0.documentID == document.id && $0.planVersion != project.plan.version }) {
                        Toggle("Show earlier plan observations (require rechecking)", isOn: $showEarlierPlans).font(.caption).padding(.horizontal, 12).padding(.bottom, 8)
                    }
                    List(selection: Binding(get: { observationID }, set: { id in
                        guard !store.hasUnsavedObservation else { store.errorMessage = "Save or discard observation edits before selecting another row."; return }
                        observationID = id
                    })) {
                        ForEach(observations) { observation in ObservationRow(observation: observation, label: project.plan.variables.first { $0.id == observation.variableID }?.label ?? observation.variableID).tag(observation.id) }
                    }.frame(minHeight: 130, idealHeight: 210, maxHeight: 260)
                    .onChange(of: observationID) { _, id in
                        newObservation = nil
                        if let row = project.observations.first(where: { $0.id == id }), let citation = row.citations.first {
                            focus = .init(page: citation.page, quote: citation.quote, startUTF16: citation.startUTF16, lengthUTF16: citation.lengthUTF16, region: citation.region)
                        } else { focus = nil }
                    }
                    Divider()
                    if let observation = selectedObservation, let variable = project.plan.variables.first(where: { $0.id == observation.variableID }) {
                        ObservationEditor(store: store, document: document, observation: observation, variable: variable, sourceSelection: selection, currentPlanVersion: project.plan.version, showSource: { focus = $0 }).id("\(observation.id)-\(observation.updatedAt.timeIntervalSince1970)")
                    } else {
                        ContentUnavailableView("Select an observation", systemImage: "text.magnifyingglass", description: Text("Extract suggestions or add a manual observation, then inspect its value and exact source quotation.")).frame(maxHeight: .infinity)
                    }
                }.frame(minWidth: 330, idealWidth: 390, maxWidth: 580)
            }
        }
        .task(id: document.id) { do { sourceURL = try await store.repository.documentURL(document, projectID: project.id) } catch { store.errorMessage = error.localizedDescription } }
        .onChange(of: project.observations) { _, _ in
            if let pending = newObservation, project.observations.contains(where: { $0.id == pending.id }) { observationID = pending.id; newObservation = nil }
        }
        .sheet(isPresented: $showNewObservation) {
            VStack(alignment: .leading, spacing: 16) {
                Text("New manual observation").font(.title2.weight(.semibold))
                Picker("Variable", selection: $chosenVariable) { ForEach(project.plan.variables) { Text($0.label).tag($0.id) } }
                Text("Add a separate observation for each arm, outcome, time point, subgroup or analysis. Attach an exact source quote before verification.").foregroundStyle(.secondary)
                HStack { Button("Cancel") { showNewObservation = false }; Spacer(); Button("Create observation") { newObservation = Observation(documentID: document.id, variableID: chosenVariable, status: .edited, planVersion: project.plan.version); observationID = nil; showNewObservation = false }.buttonStyle(.borderedProminent) }
            }.padding(24).frame(width: 440)
        }
    }
}

struct ObservationRow: View {
    var observation: Observation
    var label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(label).font(.callout.weight(.semibold)); Spacer(); Text(observation.status.rawValue).font(.caption2).foregroundStyle(observation.status == .verified ? .green : .secondary) }
            Text(observation.missingness == .reported ? observation.value : observation.missingness.rawValue).lineLimit(2).font(.callout)
            if !observation.context.summary.isEmpty { Text(observation.context.summary).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
            if !observation.model.isEmpty && observation.missingness == .reported {
                Text(SourceCheckPolicy.supported(observation) ? "AI source support · human review required" : "Source check: \(observation.sourceCheck?.verdict.rawValue ?? "pending")").font(.caption2).foregroundStyle(SourceCheckPolicy.supported(observation) ? Color.secondary : Color.orange)
            }
        }.padding(.vertical, 3)
    }
}
