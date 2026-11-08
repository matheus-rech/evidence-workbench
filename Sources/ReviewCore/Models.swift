import Foundation

public enum WorkbenchError: LocalizedError {
    case invalid(String), conflict, missingKey, cancelled
    public var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        case .conflict: return "The project changed on disk. Reopen it before saving to avoid overwriting another window or process."
        case .missingKey: return "Add your OpenAI API key in Settings before using AI."
        case .cancelled: return "The operation was cancelled."
        }
    }
}

public struct PICOTT: Codable, Equatable, Sendable {
    public var population = ""
    public var intervention = ""
    public var comparator = ""
    public var outcomes = ""
    public var timing = ""
    public var studyTypes = ""
    public init() {}
    public var complete: Bool {
        [population, intervention, comparator, outcomes, timing, studyTypes].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

public enum FieldType: String, CaseIterable, Codable, Sendable {
    case text, number, integer, date, yesNo
}
public enum FieldScope: String, CaseIterable, Codable, Sendable {
    case study, population, arm, outcome, comparison, riskOfBias
}
public struct VariableDefinition: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var label: String
    public var definition: String
    public var type: FieldType
    public var scope: FieldScope
    public var unit: String
    public var core: Bool
    public init(id: String = UUID().uuidString, label: String, definition: String, type: FieldType = .text, scope: FieldScope = .study, unit: String = "", core: Bool = false) {
        self.id = id; self.label = label; self.definition = definition; self.type = type; self.scope = scope; self.unit = unit; self.core = core
    }
}

public struct ReviewPlan: Codable, Equatable, Sendable {
    public var researchQuestion = ""
    public var framework = "Non-Cochrane"
    public var reviewType = "Intervention"
    public var registration = ""
    public var picott = PICOTT()
    public var outcomeSelection = "Extract all eligible outcomes, time points, arms and analyses; preserve their labels. Predefine any selection hierarchy here."
    public var missingDataPolicy = "Record not reported, not applicable and unclear separately. Never infer zero or substitute medians for means."
    public var extractionProcess = ""
    public var riskOfBiasTool = ""
    public var synthesisPlan = ""
    public var reviewer = ""
    public var variables = CoreFields.defaults
    public var approvedAt: Date?
    public var approvedBy: String?
    public var version = 1
    public init() {}
    public var validationMessages: [String] {
        var issues: [String] = []
        if researchQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("Define the research question.") }
        if !picott.complete { issues.append("Complete all six PICOTT components; explicitly state ‘Not applicable’ where appropriate.") }
        if reviewer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("Name the reviewer approving this plan.") }
        if variables.contains(where: { $0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.definition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { issues.append("Every variable needs a label and operational definition.") }
        if Set(variables.map(\.id)).count != variables.count { issues.append("Variable identifiers must be unique.") }
        if !CoreFields.requiredIDs.isSubset(of: Set(variables.map(\.id))) { issues.append("Restore the core PICOTT, demographics, methods and results fields.") }
        for (label, value) in [("outcome selection", outcomeSelection), ("missing-data policy", missingDataPolicy), ("extraction process", extractionProcess), ("risk-of-bias approach", riskOfBiasTool), ("synthesis plan", synthesisPlan)] {
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("Define the \(label).") }
        }
        return issues
    }
    public var readyForArticles: Bool { approvedAt != nil && validationMessages.isEmpty }
}

public struct DocumentPage: Codable, Equatable, Sendable {
    public var number: Int
    public var text: String
    public var ocr: Bool
    public init(number: Int, text: String, ocr: Bool = false) { self.number = number; self.text = text; self.ocr = ocr }
}
public struct SourceDocument: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var filename: String
    public var relativePath: String
    public var sha256: String
    public var pages: [DocumentPage]
    public var importedAt: Date
    public var studyID: UUID
    public var peerReviewStatus: String
    public var warnings: [String]
    public init(id: UUID = UUID(), filename: String, relativePath: String, sha256: String, pages: [DocumentPage], studyID: UUID = UUID(), warnings: [String] = []) {
        self.id = id; self.filename = filename; self.relativePath = relativePath; self.sha256 = sha256; self.pages = pages; self.studyID = studyID; self.importedAt = Date(); self.peerReviewStatus = "Unconfirmed"; self.warnings = warnings
    }
    public var hasText: Bool { pages.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
}
public enum ObservationStatus: String, CaseIterable, Codable, Sendable {
    case suggested, edited, verified, rejected
}
public enum Missingness: String, CaseIterable, Codable, Sendable {
    case reported, notReported, notApplicable, unclear
}
public struct ObservationContext: Codable, Equatable, Sendable {
    public var arm: String
    public var comparator: String
    public var outcome: String
    public var timepoint: String
    public var subgroup: String
    public var analysis: String
    public init(arm: String = "", comparator: String = "", outcome: String = "", timepoint: String = "", subgroup: String = "", analysis: String = "") {
        self.arm = arm; self.comparator = comparator; self.outcome = outcome; self.timepoint = timepoint; self.subgroup = subgroup; self.analysis = analysis
    }
    public var summary: String { [arm, comparator.isEmpty ? "" : "vs \(comparator)", outcome, timepoint, subgroup, analysis].filter { !$0.isEmpty }.joined(separator: " · ") }
}
/// Fractions of the PDF crop box in unrotated page coordinates, origin at bottom left.
public struct EvidenceRegion: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(x: Double, y: Double, width: Double, height: Double) { self.x = x; self.y = y; self.width = width; self.height = height }
    public var isValid: Bool {
        [x, y, width, height].allSatisfy(\.isFinite) && x >= 0 && y >= 0 && width > 0 && height > 0 && x + width <= 1.0000001 && y + height <= 1.0000001
    }
}
public struct EvidenceCitation: Codable, Equatable, Sendable {
    public var page: Int
    public var quote: String
    public var exactMatch: Bool
    public var startUTF16: Int?
    public var lengthUTF16: Int?
    public var region: EvidenceRegion?
    public var visuallyVerified: Bool?
    public init(page: Int, quote: String, exactMatch: Bool = false, startUTF16: Int? = nil, lengthUTF16: Int? = nil, region: EvidenceRegion? = nil, visuallyVerified: Bool? = nil) {
        self.page = page; self.quote = quote; self.exactMatch = exactMatch; self.startUTF16 = startUTF16; self.lengthUTF16 = lengthUTF16
        self.region = region; self.visuallyVerified = visuallyVerified
    }
}
public struct Observation: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var documentID: UUID
    public var variableID: String
    public var value: String
    public var missingness: Missingness
    public var context: ObservationContext
    public var citations: [EvidenceCitation]
    public var confidence: Int?
    public var status: ObservationStatus
    public var reviewer: String
    public var note: String
    public var model: String
    public var sourceCheck: SourceCheck?
    public var sourceAdjudication: String?
    public var planVersion: Int
    public var updatedAt: Date
    public init(id: UUID = UUID(), documentID: UUID, variableID: String, value: String = "", missingness: Missingness = .reported, context: ObservationContext = .init(), citations: [EvidenceCitation] = [], confidence: Int? = nil, status: ObservationStatus = .suggested, reviewer: String = "", note: String = "", model: String = "", planVersion: Int = 1) {
        self.id = id; self.documentID = documentID; self.variableID = variableID; self.value = value; self.missingness = missingness; self.context = context; self.citations = citations; self.confidence = confidence; self.status = status; self.reviewer = reviewer; self.note = note; self.model = model; self.planVersion = planVersion; self.updatedAt = Date()
    }
}
public struct AuditEvent: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var date = Date()
    public var actor: String
    public var action: String
    public var detail: String
    public init(actor: String, action: String, detail: String) { self.actor = actor; self.action = action; self.detail = detail }
}
public struct PlanSnapshot: Codable, Equatable, Sendable {
    public var date: Date
    public var reason: String
    public var plan: ReviewPlan
    public init(date: Date, reason: String, plan: ReviewPlan) { self.date = date; self.reason = reason; self.plan = plan }
}
public struct ChatMessage: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var role: String
    public var text: String
    public var date = Date()
    public var sources: [ResearchSource] = []
    public init(role: String, text: String, sources: [ResearchSource] = []) { self.role = role; self.text = text; self.sources = sources }
}
public struct ResearchSource: Codable, Equatable, Sendable {
    public var title: String
    public var url: String
    public init(title: String, url: String) { self.title = title; self.url = url }
}
public struct AgentProposal: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var summary: String
    public var variables: [VariableDefinition]
    public var picott: PICOTT?
    public var sources: [ResearchSource]
    public var createdAt = Date()
    public init(summary: String, variables: [VariableDefinition], picott: PICOTT? = nil, sources: [ResearchSource] = []) { self.summary = summary; self.variables = variables; self.picott = picott; self.sources = sources }
}
public struct ResearchJob: Codable, Equatable, Sendable {
    public var responseID: String
    public var question: String
    public var model: String
    public var startedAt: Date
}
public struct ReviewProject: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var title = "Untitled review"
    public var schemaVersion = 1
    public var revision = 0
    public var updatedAt = Date()
    public var plan = ReviewPlan()
    public var planHistory: [PlanSnapshot] = []
    public var protocols: [SourceDocument] = []
    public var documents: [SourceDocument] = []
    public var observations: [Observation] = []
    public var assets: [SourceAsset]?
    public var audit: [AuditEvent] = []
    public var messages: [ChatMessage] = []
    public var proposals: [AgentProposal] = []
    public var researchJob: ResearchJob?
    public init(title: String = "Untitled review") { self.title = title }
}
