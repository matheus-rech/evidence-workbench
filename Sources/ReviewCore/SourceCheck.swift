import Foundation
import CryptoKit

public enum SourceCheckVerdict: String, Codable, CaseIterable, Sendable { case supported, contradicted, unclear }
public struct SourceCheck: Codable, Equatable, Sendable {
    public var verdict: SourceCheckVerdict
    public var reason: String
    public var quote: String
    public var model: String
    public var claimFingerprint: String
    public var sourceFingerprint: String?
    public var checkedAt: Date
    public init(verdict: SourceCheckVerdict, reason: String, quote: String = "", model: String, claimFingerprint: String, checkedAt: Date = Date(), sourceFingerprint: String? = nil) {
        self.verdict = verdict; self.reason = reason; self.quote = quote; self.model = model; self.claimFingerprint = claimFingerprint; self.checkedAt = checkedAt; self.sourceFingerprint = sourceFingerprint
    }
}
public enum SourceCheckPolicy {
    public static func fingerprint(_ observation: Observation) -> String {
        let claim = ["document": observation.documentID.uuidString, "planVersion": String(observation.planVersion), "variable": observation.variableID, "value": observation.value, "missingness": observation.missingness.rawValue, "arm": observation.context.arm, "comparator": observation.context.comparator, "outcome": observation.context.outcome, "timepoint": observation.context.timepoint, "subgroup": observation.context.subgroup, "analysis": observation.context.analysis, "note": observation.note, "source": observation.citations.map { "\($0.page)|\($0.quote)|\($0.region.map { "\($0.x),\($0.y),\($0.width),\($0.height)" } ?? "text")" }.joined(separator: "\n")]
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(claim)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    /// Binds a decision to the original, cached transcription, full field definition, plan and exact evidence.
    public static func evidenceFingerprint(_ observation: Observation, variable: VariableDefinition, document: SourceDocument) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let field = (try? encoder.encode(variable)) ?? Data()
        let pages = (try? encoder.encode(document.pages)) ?? Data()
        let citations = (try? encoder.encode(observation.citations)) ?? Data()
        let binding = [String(data: citations, encoding: .utf8) ?? "", fingerprint(observation), document.sha256, String(data: field, encoding: .utf8) ?? "", SHA256.hash(data: pages).map { String(format: "%02x", $0) }.joined(), observation.reviewer, observation.sourceAdjudication ?? ""].joined(separator: "\n")
        return SHA256.hash(data: Data(binding.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    /// AI evidence binding deliberately excludes reviewer/adjudication, which the checker never receives.
    public static func checkFingerprint(_ observation: Observation, variable: VariableDefinition, document: SourceDocument) -> String {
        var claim = observation; claim.reviewer = ""; claim.sourceAdjudication = nil
        return evidenceFingerprint(claim, variable: variable, document: document)
    }
    public static func supported(_ observation: Observation, variable: VariableDefinition, document: SourceDocument) -> Bool {
        supported(observation) && fresh(observation, variable: variable, document: document)
    }
    public static func fresh(_ observation: Observation, variable: VariableDefinition, document: SourceDocument) -> Bool {
        observation.sourceCheck?.claimFingerprint == fingerprint(observation) && observation.sourceCheck?.sourceFingerprint == checkFingerprint(observation, variable: variable, document: document)
    }
    public static func supported(_ observation: Observation) -> Bool {
        observation.sourceCheck?.verdict == .supported && observation.sourceCheck?.claimFingerprint == fingerprint(observation)
    }
    public static func resolved(_ observation: Observation) -> Bool {
        observation.model.isEmpty || observation.missingness != .reported || !(observation.sourceAdjudication ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
public struct ModelSourceCheckReply: Decodable, Sendable {
    public struct Item: Decodable, Sendable { public var observation_id: UUID; public var verdict: SourceCheckVerdict; public var reason: String; public var source_quote: String }
    public var checks: [Item]
}
