import SwiftUI
import ReviewCore

struct PlanEditorView: View {
    @ObservedObject var store: WorkspaceStore
    var project: ReviewProject
    @State private var draft = ReviewPlan()
    @State private var title = ""
    @State private var amendmentReason = ""
    @State private var initialized = false
    @State private var showCore = false
    @State private var showHistory = false
    private var locked: Bool { project.plan.approvedAt != nil }
    private var dirty: Bool { initialized && (draft != project.plan || title != project.title) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Design before extraction").font(.largeTitle.weight(.bold))
                    Text("Define the question, eligibility, data items and review methods before importing article reports. AI proposals only change the draft when you apply them.").foregroundStyle(.secondary)
                }
                protocolSection
                if locked { amendmentSection }
                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        FieldBlock(label: "Review title", placeholder: "Name this systematic review", text: $title)
                        FieldBlock(label: "Research question", placeholder: "What question will the review answer?", text: $draft.researchQuestion)
                        HStack {
                            Picker("Framework", selection: $draft.framework) { Text("Non-Cochrane").tag("Non-Cochrane"); Text("Cochrane").tag("Cochrane") }
                            Picker("Review type", selection: $draft.reviewType) { ForEach(["Intervention", "Observational / etiology", "Diagnostic accuracy", "Prognostic", "Qualitative", "Mixed methods", "Other"], id: \.self) { Text($0) } }
                        }
                        FieldBlock(label: "Registration / protocol reference", placeholder: "PROSPERO ID, OSF URL, DOI, or unregistered with explanation", text: $draft.registration)
                        FieldBlock(label: "Approving reviewer", placeholder: "Name or initials used in the audit trail", text: $draft.reviewer)
                    }.padding(8)
                } label: { Label("Review identity", systemImage: "person.text.rectangle") }
                .disabled(locked || store.busy)
                GroupBox {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 18) {
                        FieldBlock(label: "P · Population", placeholder: "Eligibility, setting, condition, demographics", text: $draft.picott.population)
                        FieldBlock(label: "I · Intervention / exposure", placeholder: "Intervention, exposure, index test or phenomenon", text: $draft.picott.intervention)
                        FieldBlock(label: "C · Comparator", placeholder: "Comparator / reference, or explicitly not applicable", text: $draft.picott.comparator)
                        FieldBlock(label: "O · Outcomes", placeholder: "Domains, definitions, instruments and direction", text: $draft.picott.outcomes)
                        FieldBlock(label: "T · Timing", placeholder: "Follow-up and eligible assessment windows", text: $draft.picott.timing)
                        FieldBlock(label: "T · Types of studies", placeholder: "Eligible designs and design-specific restrictions", text: $draft.picott.studyTypes)
                    }.padding(8)
                } label: { Label("PICOTT · required before article import", systemImage: "scope") }
                .disabled(locked || store.busy)
                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        FieldBlock(label: "Outcome / result selection rules", text: $draft.outcomeSelection)
                        FieldBlock(label: "Missing and unclear information", text: $draft.missingDataPolicy)
                        FieldBlock(label: "Reviewers, independence and disagreement resolution", placeholder: "Specify reviewers, independent extraction/checking and adjudication", text: $draft.extractionProcess)
                        FieldBlock(label: "Risk-of-bias tool and domains", placeholder: "Define an appropriate approach, such as RoB 2 or ROBINS-I, or justify not applicable", text: $draft.riskOfBiasTool)
                        FieldBlock(label: "Synthesis / meta-analysis plan", placeholder: "Define effect measures, analyses, time windows, multi-arm handling; or explain narrative synthesis", text: $draft.synthesisPlan)
                    }.padding(8)
                } label: { Label("Prespecified methods", systemImage: "checklist") }
                .disabled(locked || store.busy)
                variableSection
                methodologySection
                if !locked {
                    VStack(alignment: .leading, spacing: 10) {
                        if !draft.validationMessages.isEmpty {
                            ForEach(draft.validationMessages, id: \.self) { Text("• " + $0).font(.caption).foregroundStyle(.secondary) }
                        }
                        HStack {
                            Button("Save draft") { save(approve: false) }.keyboardShortcut("s").disabled(store.busy || !dirty)
                            Button("Discard unsaved changes") { reset() }.disabled(store.busy || !dirty)
                            Spacer()
                            Button("Approve plan & unlock articles") { save(approve: true) }.buttonStyle(.borderedProminent).disabled(store.busy || !draft.validationMessages.isEmpty || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        Text(dirty ? "Unsaved changes · save before asking the agent to use this draft." : "Draft saved locally. Approval freezes this version; later changes require a reasoned amendment.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !project.planHistory.isEmpty {
                    DisclosureGroup("Previous plan versions (\(project.planHistory.count))", isExpanded: $showHistory) {
                        ForEach(Array(project.planHistory.enumerated()), id: \.offset) { _, snapshot in
                            VStack(alignment: .leading) { Text("Version \(snapshot.plan.version) · \(snapshot.date.formatted())").font(.headline); Text(snapshot.reason); Text("\(snapshot.plan.variables.count) fields · \(snapshot.plan.approvedBy ?? "Unapproved")").foregroundStyle(.secondary) }.padding(.vertical, 8)
                        }
                    }
                }
            }.padding(26).frame(maxWidth: 1000, alignment: .leading).frame(maxWidth: .infinity)
        }
        .task(id: project.id) { reset(); initialized = true }
        .onChange(of: project.plan) { _, _ in reset() }
        .onChange(of: dirty) { _, value in store.hasUnsavedPlan = value }
    }

    private var protocolSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text("Import PROSPERO, OSF or another protocol to inform your plan.").foregroundStyle(.secondary); Spacer(); Button("Import protocol…") { FilePanels.importFiles(store, protocolOnly: true) }.disabled(store.busy) }
                ForEach(project.protocols) { protocolFile in
                    VStack(alignment: .leading, spacing: 3) { Label(protocolFile.filename, systemImage: "doc.text"); Text("\(protocolFile.pages.count) pages · available to the planning agent").font(.caption).foregroundStyle(.secondary) }
                }
                if !project.protocols.isEmpty { Text("Ask the agent: ‘Use my protocol to propose PICOTT and additional extraction fields.’ Save your current draft first.").font(.caption).foregroundStyle(.secondary) }
            }.padding(8)
        } label: { Label("Protocol sources", systemImage: "paperclip") }
    }
    private var amendmentSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label("Version \(project.plan.version) approved by \(project.plan.approvedBy ?? "reviewer")", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                Text("This plan is frozen. An amendment preserves its previous version and requires existing observations to be rechecked for the new version.").font(.caption).foregroundStyle(.secondary)
                HStack { TextField("Reason for amendment", text: $amendmentReason); Button("Create amendment") { store.amendPlan(projectID: project.id, reason: amendmentReason) }.disabled(amendmentReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.busy) }
            }.padding(8)
        }
    }
    private var variableSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Text("Core fields cover bibliographic data, PICOTT, demographics, design, results, harms, funding and supporting evidence for bias assessment. Keep their definitions relevant to your question; missingness remains explicit.").font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("Core extraction fields (\(draft.variables.filter(\.core).count))", isExpanded: $showCore) {
                    ForEach($draft.variables) { $field in
                        if field.core { VariableEditor(field: $field, removable: false) {} }
                    }
                }
                Divider()
                if !CoreFields.supplementalResults.allSatisfy({ recommended in draft.variables.contains { $0.id == recommended.id } }) {
                    Button("Add percentage and rate outcome fields") {
                        draft.variables += CoreFields.supplementalResults.filter { recommended in !draft.variables.contains { $0.id == recommended.id } }
                    }
                    Text("Binary outcomes may be reported as percentages or rates without means or SDs. Add these fields through an amendment to an approved plan.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach($draft.variables) { $field in
                    if !field.core { VariableEditor(field: $field, removable: true) { draft.variables.removeAll { $0.id == field.id } } }
                }
                Button { draft.variables.append(.init(label: "", definition: "")) } label: { Label("Add custom variable", systemImage: "plus.circle") }
                Text("Describe multiple variables in the agent box, or request a sourced deep-research brief. Every proposed field remains reviewable before it enters the plan.").font(.caption).foregroundStyle(.secondary)
            }.padding(8)
        } label: { Label("Extraction dictionary · \(draft.variables.count) fields", systemImage: "character.book.closed") }
        .disabled(locked || store.busy)
    }
    private var methodologySection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Methodological references").font(.caption.weight(.semibold))
            HStack {
                Link("PRISMA 2020", destination: URL(string: "https://www.prisma-statement.org/prisma-2020-checklist")!)
                Link("Cochrane · collecting data", destination: URL(string: "https://www.cochrane.org/authors/handbooks-and-manuals/handbook/current/chapter-05")!)
            }.font(.caption)
            Text("Defaults are informed by this guidance. Selecting a framework does not certify compliance. Eligibility, independent review, risk-of-bias judgments, certainty assessment and statistical synthesis remain review-team responsibilities.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func reset() { draft = project.plan; title = project.title; store.hasUnsavedPlan = false }
    private func save(approve: Bool) { store.savePlan(projectID: project.id, title: title, plan: draft, approve: approve) }
}

struct VariableEditor: View {
    @Binding var field: VariableDefinition
    var removable: Bool
    var remove: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Variable name", text: $field.label).font(.headline)
                if removable { Button(role: .destructive, action: remove) { Image(systemName: "trash") }.buttonStyle(.borderless) }
            }
            TextField("Operational definition: what to extract, from which group, scale and time point", text: $field.definition, axis: .vertical).lineLimit(2...6)
            HStack {
                Picker("Type", selection: $field.type) { ForEach(FieldType.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                Picker("Level", selection: $field.scope) { ForEach(FieldScope.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                TextField("Unit", text: $field.unit).frame(maxWidth: 130)
            }.font(.caption)
        }.textFieldStyle(.roundedBorder).padding(12).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8)).padding(.vertical, 4)
    }
}
