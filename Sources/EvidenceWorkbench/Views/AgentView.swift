import SwiftUI
import ReviewCore

struct AgentView: View {
    @ObservedObject var store: WorkspaceStore
    var project: ReviewProject
    @State private var prompt = ""
    @State private var research = false
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "sparkle.magnifyingglass").foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) { Text("Review planning agent").font(.headline); Text("Protocol → definitions → evidence").font(.caption).foregroundStyle(.secondary) }
                Spacer()
            }.padding(16)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(project.messages) { message in
                            VStack(alignment: .leading, spacing: 7) {
                                HStack { Text(message.role == "user" ? "YOU" : "PLANNING AGENT").font(.caption2.weight(.bold)).foregroundStyle(message.role == "user" ? Color.secondary : Color.accentColor); Spacer(); Text(message.date, style: .time).font(.caption2).foregroundStyle(.tertiary) }
                                Text(message.text).textSelection(.enabled).font(.callout)
                                if !message.sources.isEmpty {
                                    DisclosureGroup("Sources (\(message.sources.count))") {
                                        ForEach(Array(message.sources.enumerated()), id: \.offset) { _, source in
                                            if let url = URL(string: source.url), ["https", "http"].contains(url.scheme ?? "") { Link(source.title, destination: url).font(.caption).lineLimit(3).padding(.vertical, 3) }
                                        }
                                    }.font(.caption)
                                }
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(message.role == "user" ? Color.accentColor.opacity(0.07) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10)).id(message.id)
                        }
                        ForEach(project.proposals) { proposal in
                            ProposalCard(store: store, proposal: proposal, locked: project.plan.approvedAt != nil).id(proposal.id)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(14)
                }.onChange(of: project.messages.count) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
            if let job = project.researchJob {
                VStack(alignment: .leading, spacing: 8) {
                    HStack { if store.activeResearch.contains(project.id) { ProgressView().controlSize(.small) }; Text("Research job · \(job.startedAt, style: .time)").font(.caption.weight(.semibold)) }
                    Text("The background job is saved. Closing the app pauses local polling; Resume checks the same job.").font(.caption2).foregroundStyle(.secondary)
                    HStack {
                        Button("Resume") { store.resumeResearch(projectID: project.id) }.disabled(store.activeResearch.contains(project.id) || store.busy)
                        Button("Cancel research", role: .destructive) { store.cancelResearch(projectID: project.id) }.disabled(store.busy)
                    }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                if store.hasUnsavedPlan { Label("Save the draft before sending or applying suggestions.", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange) }
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $prompt).font(.body).scrollContentBackground(.hidden).frame(minHeight: 85, maxHeight: 125)
                    if prompt.isEmpty { Text("Describe variables, enter PICOTT, ask about your protocol, or request research…").foregroundStyle(.tertiary).padding(.horizontal, 5).padding(.vertical, 8).allowsHitTesting(false) }
                }.padding(5).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                Toggle(isOn: $research) { Label("Deep research · cited web sources", systemImage: "globe") }.toggleStyle(.checkbox).font(.caption)
                HStack {
                    Button { FilePanels.importFiles(store, protocolOnly: true) } label: { Image(systemName: "paperclip") }.help("Attach a protocol").disabled(store.busy)
                    Spacer()
                    Button(research ? "Start research" : "Send to OpenAI") {
                        let text = prompt; prompt = ""; store.askAgent(text, deepResearch: research)
                    }.buttonStyle(.borderedProminent).disabled(store.busy || store.hasUnsavedPlan || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (research && project.researchJob != nil))
                }
                Text(research ? "Uses API billing, web search and server-side background storage. Findings become proposals for your review." : "Sends the saved plan, protocols and recent chat to OpenAI. API key and cloud permission are configured in Settings.").font(.caption2).foregroundStyle(.secondary)
            }.padding(14)
        }
    }
}

private struct ProposalCard: View {
    @ObservedObject var store: WorkspaceStore
    var proposal: AgentProposal
    var locked: Bool
    @State private var selected: Set<String> = []
    @State private var includePICOTT = false
    @State private var expanded = true
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Proposed plan changes", systemImage: "square.and.pencil").font(.headline)
            Text("\(proposal.variables.count) custom fields\(proposal.picott == nil ? "" : " + PICOTT changes"). Choose what enters the draft.").font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Review proposal", isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 12) {
                    if let p = proposal.picott {
                        Toggle("Apply proposed PICOTT", isOn: $includePICOTT).font(.callout)
                        ForEach(Array([("Population", p.population), ("Intervention", p.intervention), ("Comparator", p.comparator), ("Outcomes", p.outcomes), ("Timing", p.timing), ("Study types", p.studyTypes)].enumerated()), id: \.offset) { _, entry in
                            if !entry.1.isEmpty { Text("\(entry.0): \(entry.1)").font(.caption).textSelection(.enabled) }
                        }
                    }
                    ForEach(proposal.variables) { variable in
                        Toggle(isOn: Binding(get: { selected.contains(variable.id) }, set: { if $0 { selected.insert(variable.id) } else { selected.remove(variable.id) } })) {
                            VStack(alignment: .leading, spacing: 3) { Text(variable.label).font(.callout.weight(.medium)); Text(variable.definition).font(.caption).foregroundStyle(.secondary); Text("\(variable.scope.rawValue) · \(variable.type.rawValue) · \(variable.unit)").font(.caption2).foregroundStyle(.tertiary) }
                        }
                    }
                }.padding(.top, 8)
            }
            if locked { Text("Open a documented plan amendment to apply these changes.").font(.caption).foregroundStyle(.orange) }
            HStack {
                Button("Dismiss") { store.dismissProposal(proposal.id) }.disabled(store.busy)
                Spacer()
                Button("Apply selected") { store.applyProposal(proposal.id, variableIDs: selected, applyPICOTT: includePICOTT) }.disabled(store.busy || store.hasUnsavedPlan || locked || (selected.isEmpty && !includePICOTT))
            }
        }.padding(12).background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor.opacity(0.25)))
        .task { selected = Set(proposal.variables.map(\.id)) }
    }
}
