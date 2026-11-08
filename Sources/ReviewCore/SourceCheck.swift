import Foundation
import CryptoKit

public enum SourceCheckVerdict: String, Codable, CaseIterable, Sendable { case supported, contradicted, unclear }
public struct SourceCheck: Codable, Equatable, Sendable {
    public var verdict: SourceCheckVerdict
    public var reason: String
    public var quote: String
    public var model: String
    public var claimFingerprint: String
    public var checkedAt: Date
    public init(verdict: SourceCheckVerdict, reason: String, quote: String = "", model: String, claimFingerprint: String, checkedAt: Date = Date()) {
        self.verdict = verdict; self.reason = reason; self.quote = quote; self.model = model; self.claimFingerprint = claimFingerprint; self.checkedAt = checkedAt
    }
}
public enum SourceCheckPolicy {
    public static func fingerprint(_ observation: Observation) -> String {
        let claim = ["variable": observation.variableID, "value": observation.value, "missingness": observation.missingness.rawValue, "arm": observation.context.arm, "comparator": observation.context.comparator, "outcome": observation.context.outcome, "timepoint": observation.context.timepoint, "subgroup": observation.context.subgroup, "analysis": observation.context.analysis, "note": observation.note, "source": observation.citations.map { "\($0.page)|\($0.quote)|\($0.region.map { "\($0.x),\($0.y),\($0.width),\($0.height)" } ?? "text")" }.joined(separator: "\n")]
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(claim)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    public static func supported(_ observation: Observation) -> Bool {
        observation.sourceCheck?.verdict == .supported && observation.sourceCheck?.claimFingerprint == fingerprint(observation)
    }
    public static func resolved(_ observation: Observation) -> Bool {
        observation.model.isEmpty || observation.missingness != .reported || supported(observation) || !(observation.sourceAdjudication ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
public struct ModelSourceCheckReply: Decodable, Sendable {
    public struct Item: Decodable, Sendable { public var observation_id: UUID; public var verdict: SourceCheckVerdict; public var reason: String; public var source_quote: String }
    public var checks: [Item]
}
