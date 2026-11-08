import SwiftUI
import ReviewCore

struct ObservationEditor: View {
    @ObservedObject var store: WorkspaceStore
    var document: SourceDocument
    var observation: Observation
    var variable: VariableDefinition
    var sourceSelection: SourceSelection?
    var currentPlanVersion: Int
    var showSource: (SourceSelection) -> Void
    @State private var draft: Observation
    @State private var quote: String
    @State private var page: Int
    @State private var showContext = false
    @State private var chosenAnchor: SourceSelection?
    @State private var visuallyChecked = false
    @State private var editQuote = false
    init(store: WorkspaceStore, document: SourceDocument, observation: Observation, variable: VariableDefinition, sourceSelection: SourceSelection?, currentPlanVersion: Int, showSource: @escaping (SourceSelection) -> Void) {
        self.store = store; self.document = document; self.observation = observation; self.variable = variable; self.sourceSelection = sourceSelection; self.currentPlanVersion = currentPlanVersion; self.showSource = showSource
        _draft = State(initialValue: observation); _quote = State(initialValue: observation.citations.first?.quote ?? ""); _page = State(initialValue: observation.citations.first?.page ?? 1)
        _visuallyChecked = State(initialValue: observation.citations.first?.visuallyVerified == true)
    }
    private var quoteMatches: Bool {
        guard let source = document.pages.first(where: { $0.number == page }), !quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return QuoteLocator.resolve(in: source.text, quote: quote, start: activeAnchor?.startUTF16, length: activeAnchor?.lengthUTF16) != nil
    }
    private var valueError: String? {
        do { try ReviewEngine.validateObservationValue(draft, variable: variable); return nil }
        catch { return error.localizedDescription }
    }
    private var activeAnchor: SourceSelection? {
        if let chosenAnchor, chosenAnchor.page == page, chosenAnchor.quote == quote { return chosenAnchor }
        if let citation = draft.citations.first, citation.page == page, citation.quote == quote {
            return .init(page: page, quote: quote, startUTF16: citation.startUTF16, lengthUTF16: citation.lengthUTF16, region: citation.region)
        }
        return nil
    }
    private var region: EvidenceRegion? {
        if let chosenAnchor, chosenAnchor.page == page { return chosenAnchor.region }
        return draft.citations.first?.page == page ? draft.citations.first?.region : nil
    }
    private var dirty: Bool { draft.value != observation.value || draft.missingness != observation.missingness || draft.context != observation.context || draft.note != observation.note || draft.sourceAdjudication != observation.sourceAdjudication || quote != (observation.citations.first?.quote ?? "") || page != (observation.citations.first?.page ?? 1) || region != observation.citations.first?.region || visuallyChecked != (observation.citations.first?.visuallyVerified == true) || (chosenAnchor != nil && (chosenAnchor?.startUTF16 != observation.citations.first?.startUTF16 || chosenAnchor?.lengthUTF16 != observation.citations.first?.lengthUTF16)) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(variable.label).font(.headline)
                    Spacer()
                    if let score = draft.confidence { Text("Model score \(score)%").font(.caption).foregroundStyle(score < 80 ? .orange : .secondary) }
                }
                Text(variable.definition).font(.caption).foregroundStyle(.secondary)
                if let valueError { Label(valueError, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                if !draft.model.isEmpty && draft.missingness == .reported {
                    let fresh = SourceCheckPolicy.fresh(draft, variable: variable, document: document)
                    Text("Independent AI source check: \(fresh ? draft.sourceCheck?.verdict.rawValue ?? "pending" : "pending / claim changed")").font(.caption.bold()).foregroundStyle(SourceCheckPolicy.supported(draft, variable: variable, document: document) ? .green : .orange)
                    if fresh, let check = draft.sourceCheck { Text(check.reason).font(.caption).textSelection(.enabled) }
                    Button("Run independent source check") { store.checkObservation(observation) }.disabled(store.busy || dirty)
                    if !draft.model.isEmpty {
                        TextField("Human source review: record value, units, denominator, group and time point", text: Binding(get: { draft.sourceAdjudication ?? "" }, set: { draft.sourceAdjudication = $0 }), axis: .vertical).lineLimit(2...5).textFieldStyle(.roundedBorder)
                        Text("AI review is available in Automatic mode. Human verification requires your own documented source decision.").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if observation.planVersion != currentPlanVersion { Text("Earlier plan v\(observation.planVersion). Recheck against v\(currentPlanVersion) before verification.").font(.caption).foregroundStyle(.orange) }
                Picker("Data status", selection: Binding(get: { draft.missingness }, set: { value in draft.missingness = value; if value != .reported { draft.value = "" }; invalidateSource() })) { ForEach(Missingness.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                if draft.missingness == .reported {
                    Text("Value · \(variable.type.rawValue)\(variable.unit.isEmpty ? "" : " · " + variable.unit)").font(.caption.weight(.semibold))
                    TextField("Extracted value", text: Binding(get: { draft.value }, set: { draft.value = $0; invalidateSource() }), axis: .vertical).lineLimit(2...6).textFieldStyle(.roundedBorder)
                }
                DisclosureGroup("Arm / outcome / time point and analysis", isExpanded: $showContext) {
                    VStack(spacing: 8) {
                        contextField("Arm / population", text: $draft.context.arm)
                        contextField("Comparator", text: $draft.context.comparator)
                        contextField("Outcome / instrument", text: $draft.context.outcome)
                        contextField("Time point (include units)", text: $draft.context.timepoint)
                        contextField("Subgroup", text: $draft.context.subgroup)
                        contextField("Analysis / adjustment / CI level", text: $draft.context.analysis)
                    }.padding(.top, 8)
                }.font(.caption)
                Divider()
                HStack {
                    Text(region == nil ? "Exact source quotation" : "Transcription of boxed image evidence").font(.caption.weight(.semibold))
                    Spacer()
                    Stepper("Page \(page)", value: $page, in: 1...max(document.pages.count, 1)).font(.caption)
                }
                if !quote.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Provenance text · value emphasis").font(.caption.weight(.semibold))
                        Text(quotePreview).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        Text("Emphasis locates literal text; it does not verify the value or its context.").font(.caption2).foregroundStyle(.secondary)
                    }.padding(10).background(.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }
                DisclosureGroup("Edit quotation / visual transcription", isExpanded: $editQuote) {
                    TextEditor(text: $quote).font(.callout).frame(minHeight: 70).padding(4).overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                }.font(.caption)
                HStack {
                    Button(sourceSelection?.region == nil ? "Use PDF selection" : "Attach drawn box") { if let selection = sourceSelection { if selection.region == nil { quote = selection.quote }; page = selection.page; chosenAnchor = selection; visuallyChecked = false; draft.confidence = nil; draft.status = .edited; draft.sourceCheck = nil; draft.sourceAdjudication = nil } }.disabled(sourceSelection == nil)
                    Button("Show source") { showSource(.init(page: page, quote: quote, startUTF16: activeAnchor?.startUTF16, lengthUTF16: activeAnchor?.lengthUTF16, region: region)) }.disabled(quote.isEmpty && region == nil)
                }.font(.caption)
                if let region, region.isValid {
                    Toggle("I checked the boxed value, units, row/column, group and time point against the original image", isOn: $visuallyChecked).font(.caption)
                    Text("This is a reviewer transcription, not a machine-matched text quotation. Include headers and footnotes in your source check.").font(.caption).foregroundStyle(.secondary)
                } else if !quote.isEmpty {
                    Label(quoteMatches ? "Quote matches page text" : "Quote is missing or ambiguous; select its exact occurrence", systemImage: quoteMatches ? "checkmark.circle" : "exclamationmark.triangle").font(.caption).foregroundStyle(quoteMatches ? .green : .orange)
                }
                FieldBlock(label: "Reviewer note / missingness reason", text: $draft.note)
                Text("Text matching confirms the quotation exists. A reviewer must still check whether it supports the value, denominator, group and time point.").font(.caption2).foregroundStyle(.secondary)
                HStack {
                    Button("Save edit") { save(verify: false) }
                    Button("Discard") { draft = observation; chosenAnchor = nil; quote = observation.citations.first?.quote ?? ""; page = observation.citations.first?.page ?? 1; visuallyChecked = observation.citations.first?.visuallyVerified == true; store.hasUnsavedObservation = false }.disabled(!dirty)
                    Button("Reject", role: .destructive) { store.rejectObservation(observation.id) }.disabled(store.current?.observations.contains(where: { $0.id == observation.id }) != true)
                    Spacer()
                    Button("Verify & save") { save(verify: true) }.buttonStyle(.borderedProminent).disabled(valueError != nil || !SourceCheckPolicy.resolved(draft) || (draft.missingness == .reported && (region != nil ? !(region?.isValid == true && visuallyChecked && !quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) : !quoteMatches)))
                }.disabled(store.busy || store.current?.plan.readyForArticles != true)
            }.padding(14)
        }
        .onChange(of: dirty) { _, value in store.hasUnsavedObservation = value }
        .onChange(of: quote) { _, _ in visuallyChecked = false; draft.sourceCheck = nil; draft.sourceAdjudication = nil }
        .onChange(of: draft.note) { _, _ in draft.sourceCheck = nil; draft.sourceAdjudication = nil }
        .onChange(of: page) { _, _ in if chosenAnchor?.page != page { chosenAnchor = nil }; visuallyChecked = false }
        .onDisappear { store.hasUnsavedObservation = false }
        .onAppear { editQuote = quote.isEmpty }
    }
    private var quotePreview: AttributedString {
        var result = AttributedString(quote)
        for nsRange in ProvenanceValueLocator.ranges(value: draft.value, quote: quote, numeric: variable.type == .number || variable.type == .integer) {
            guard let range = Range(nsRange, in: quote), let lower = AttributedString.Index(range.lowerBound, within: result), let upper = AttributedString.Index(range.upperBound, within: result) else { continue }
            result[lower..<upper].backgroundColor = .yellow
            result[lower..<upper].foregroundColor = .black
            result[lower..<upper].font = .body.bold()
        }
        return result
    }
    private func contextField(_ placeholder: String, text: Binding<String>) -> some View { TextField(placeholder, text: Binding(get: { text.wrappedValue }, set: { text.wrappedValue = $0; invalidateSource() })).textFieldStyle(.roundedBorder) }
    private func invalidateSource() { quote = ""; chosenAnchor = nil; visuallyChecked = false; draft.citations = []; draft.confidence = nil; draft.reviewer = ""; draft.status = .edited; draft.sourceCheck = nil; draft.sourceAdjudication = nil }
    private func save(verify: Bool) {
        var edited = draft
        if let region {
            edited.citations = [.init(page: page, quote: quote, region: region, visuallyVerified: visuallyChecked)]
        } else if chosenAnchor == nil, quote == observation.citations.first?.quote, page == observation.citations.first?.page, !draft.citations.isEmpty {
            edited.citations = draft.citations
        } else { edited.citations = quote.isEmpty ? [] : [.init(page: page, quote: quote, exactMatch: quoteMatches, startUTF16: activeAnchor?.startUTF16, lengthUTF16: activeAnchor?.lengthUTF16)] }
        store.saveObservation(edited, verify: verify)
    }
}
