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

/// Project files written by earlier builds lack keys that later builds added with defaults. Synthesized `Decodable`
/// requires every key, so the types that grew over time decode each such key as optional and fall back to the default.
extension KeyedDecodingContainer {
    func value<T: Decodable>(_ type: T.Type, _ key: Key, or fallback: @autoclosure () -> T) throws -> T {
        try decodeIfPresent(type, forKey: key) ?? fallback()
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
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        population = try c.value(String.self, .population, or: ""); intervention = try c.value(String.self, .intervention, or: "")
        comparator = try c.value(String.self, .comparator, or: ""); outcomes = try c.value(String.self, .outcomes, or: "")
        timing = try c.value(String.self, .timing, or: ""); studyTypes = try c.value(String.self, .studyTypes, or: "")
    }
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
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); label = try c.decode(String.self, forKey: .label); definition = try c.decode(String.self, forKey: .definition)
        type = try c.value(FieldType.self, .type, or: .text); scope = try c.value(FieldScope.self, .scope, or: .study)
        unit = try c.value(String.self, .unit, or: ""); core = try c.value(Bool.self, .core, or: false)
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
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self); let fresh = ReviewPlan()
        researchQuestion = try c.value(String.self, .researchQuestion, or: ""); framework = try c.value(String.self, .framework, or: fresh.framework)
        reviewType = try c.value(String.self, .reviewType, or: fresh.reviewType); registration = try c.value(String.self, .registration, or: "")
        picott = try c.value(PICOTT.self, .picott, or: PICOTT())
        outcomeSelection = try c.value(String.self, .outcomeSelection, or: fresh.outcomeSelection); missingDataPolicy = try c.value(String.self, .missingDataPolicy, or: fresh.missingDataPolicy)
        extractionProcess = try c.value(String.self, .extractionProcess, or: ""); riskOfBiasTool = try c.value(String.self, .riskOfBiasTool, or: ""); synthesisPlan = try c.value(String.self, .synthesisPlan, or: "")
        reviewer = try c.value(String.self, .reviewer, or: ""); variables = try c.value([VariableDefinition].self, .variables, or: CoreFields.defaults)
        approvedAt = try c.decodeIfPresent(Date.self, forKey: .approvedAt); approvedBy = try c.decodeIfPresent(String.self, forKey: .approvedBy)
        version = try c.value(Int.self, .version, or: 1)
    }
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
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        number = try c.decode(Int.self, forKey: .number); text = try c.value(String.self, .text, or: ""); ocr = try c.value(Bool.self, .ocr, or: false)
    }
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
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); filename = try c.decode(String.self, forKey: .filename)
        relativePath = try c.decode(String.self, forKey: .relativePath); sha256 = try c.decode(String.self, forKey: .sha256)
        pages = try c.value([DocumentPage].self, .pages, or: []); importedAt = try c.value(Date.self, .importedAt, or: Date())
        studyID = try c.value(UUID.self, .studyID, or: UUID()); peerReviewStatus = try c.value(String.self, .peerReviewStatus, or: "Unconfirmed")
        warnings = try c.value([String].self, .warnings, or: [])
    }
    public var hasText: Bool { pages.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
}
public enum ObservationStatus: String, CaseIterable, Codable, Sendable {
    case suggested, edited, verified, rejected, aiReviewed
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
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        arm = try c.value(String.self, .arm, or: ""); comparator = try c.value(String.self, .comparator, or: ""); outcome = try c.value(String.self, .outcome, or: "")
        timepoint = try c.value(String.self, .timepoint, or: ""); subgroup = try c.value(String.self, .subgroup, or: ""); analysis = try c.value(String.self, .analysis, or: "")
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
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        page = try c.decode(Int.self, forKey: .page); quote = try c.value(String.self, .quote, or: ""); exactMatch = try c.value(Bool.self, .exactMatch, or: false)
        startUTF16 = try c.decodeIfPresent(Int.self, forKey: .startUTF16); lengthUTF16 = try c.decodeIfPresent(Int.self, forKey: .lengthUTF16)
        region = try c.decodeIfPresent(EvidenceRegion.self, forKey: .region); visuallyVerified = try c.decodeIfPresent(Bool.self, forKey: .visuallyVerified)
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
    public var verificationFingerprint: String?
    public var planVersion: Int
    public var updatedAt: Date
    public init(id: UUID = UUID(), documentID: UUID, variableID: String, value: String = "", missingness: Missingness = .reported, context: ObservationContext = .init(), citations: [EvidenceCitation] = [], confidence: Int? = nil, status: ObservationStatus = .suggested, reviewer: String = "", note: String = "", model: String = "", planVersion: Int = 1) {
        self.id = id; self.documentID = documentID; self.variableID = variableID; self.value = value; self.missingness = missingness; self.context = context; self.citations = citations; self.confidence = confidence; self.status = status; self.reviewer = reviewer; self.note = note; self.model = model; self.planVersion = planVersion; self.updatedAt = Date()
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); documentID = try c.decode(UUID.self, forKey: .documentID); variableID = try c.decode(String.self, forKey: .variableID)
        value = try c.value(String.self, .value, or: ""); missingness = try c.value(Missingness.self, .missingness, or: .reported)
        context = try c.value(ObservationContext.self, .context, or: ObservationContext()); citations = try c.value([EvidenceCitation].self, .citations, or: [])
        confidence = try c.decodeIfPresent(Int.self, forKey: .confidence); status = try c.value(ObservationStatus.self, .status, or: .suggested)
        reviewer = try c.value(String.self, .reviewer, or: ""); note = try c.value(String.self, .note, or: ""); model = try c.value(String.self, .model, or: "")
        sourceCheck = try c.decodeIfPresent(SourceCheck.self, forKey: .sourceCheck); sourceAdjudication = try c.decodeIfPresent(String.self, forKey: .sourceAdjudication)
        verificationFingerprint = try c.decodeIfPresent(String.self, forKey: .verificationFingerprint)
        planVersion = try c.value(Int.self, .planVersion, or: 1); updatedAt = try c.value(Date.self, .updatedAt, or: Date())
    }
}
public struct AuditEvent: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var date = Date()
    public var actor: String
    public var action: String
    public var detail: String
    public init(actor: String, action: String, detail: String) { self.actor = actor; self.action = action; self.detail = detail }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.value(UUID.self, .id, or: UUID()); date = try c.value(Date.self, .date, or: Date())
        actor = try c.value(String.self, .actor, or: ""); action = try c.decode(String.self, forKey: .action); detail = try c.value(String.self, .detail, or: "")
    }
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
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.value(UUID.self, .id, or: UUID()); role = try c.decode(String.self, forKey: .role); text = try c.value(String.self, .text, or: "")
        date = try c.value(Date.self, .date, or: Date()); sources = try c.value([ResearchSource].self, .sources, or: [])
    }
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
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.value(UUID.self, .id, or: UUID()); summary = try c.value(String.self, .summary, or: ""); variables = try c.value([VariableDefinition].self, .variables, or: [])
        picott = try c.decodeIfPresent(PICOTT.self, forKey: .picott); sources = try c.value([ResearchSource].self, .sources, or: []); createdAt = try c.value(Date.self, .createdAt, or: Date())
    }
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
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // The id names the review's folder; minting one would save the review elsewhere or block every save.
        id = try c.decode(UUID.self, forKey: .id); title = try c.value(String.self, .title, or: "Untitled review")
        schemaVersion = try c.value(Int.self, .schemaVersion, or: 1); revision = try c.value(Int.self, .revision, or: 0); updatedAt = try c.value(Date.self, .updatedAt, or: Date())
        plan = try c.value(ReviewPlan.self, .plan, or: ReviewPlan()); planHistory = try c.value([PlanSnapshot].self, .planHistory, or: [])
        protocols = try c.value([SourceDocument].self, .protocols, or: []); documents = try c.value([SourceDocument].self, .documents, or: [])
        observations = try c.value([Observation].self, .observations, or: []); assets = try c.decodeIfPresent([SourceAsset].self, forKey: .assets)
        audit = try c.value([AuditEvent].self, .audit, or: []); messages = try c.value([ChatMessage].self, .messages, or: [])
        proposals = try c.value([AgentProposal].self, .proposals, or: []); researchJob = try c.decodeIfPresent(ResearchJob.self, forKey: .researchJob)
    }
}
