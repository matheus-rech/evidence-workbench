import Foundation

public enum SourceAssetKind: String, Codable, Sendable, CaseIterable { case table, figure }

public struct SourceAsset: Codable, Equatable, Sendable, Identifiable {
    public var id = UUID()
    public var documentID: UUID
    public var sourceSHA256: String
    public var page: Int
    public var kind: SourceAssetKind
    public var label: String
    public var title: String
    public var caption: String
    public var region: EvidenceRegion
    public var exactCrop: Bool
    public var table: EditableTable?
    public var warnings: [String]
    public var origin: String
    public var reviewedBy: String?
    public var reviewedAt: Date?
    public var excluded: Bool?
    public init(documentID: UUID, sourceSHA256: String, page: Int, kind: SourceAssetKind, label: String, title: String, caption: String = "", region: EvidenceRegion = .init(x: 0, y: 0, width: 1, height: 1), exactCrop: Bool = false, table: EditableTable? = nil, warnings: [String] = [], origin: String = "AI discovery") {
        self.documentID = documentID; self.sourceSHA256 = sourceSHA256; self.page = page; self.kind = kind
        self.label = label; self.title = title; self.caption = caption; self.region = region; self.exactCrop = exactCrop; self.table = table; self.warnings = warnings; self.origin = origin
    }
    public var sourceKey: String { "\(documentID)|\(page)|\(kind.rawValue)|" + label.lowercased().filter { $0.isLetter || $0.isNumber } }
    public func validate(document: SourceDocument) throws {
        guard documentID == document.id, sourceSHA256 == document.sha256,
              document.pages.contains(where: { $0.number == page }), region.isValid,
              !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              label.count <= 200, title.count <= 2_000, caption.count <= 10_000, warnings.count <= 50 else {
            throw WorkbenchError.invalid("The table/image source identity, page or metadata is invalid.")
        }
        if let table {
            try table.validate()
            guard kind == .table, table.sourceSHA256 == sourceSHA256, table.sourceFilename == document.filename,
                  table.page == page, table.region == region else { throw WorkbenchError.invalid("The editable table does not match its original source asset.") }
        }
    }
    public static func merge(existing: [SourceAsset], incoming: [SourceAsset]) -> [SourceAsset] {
        var result = existing
        for value in incoming {
            if let index = result.firstIndex(where: { $0.sourceKey == value.sourceKey }) {
                // Preserve reviewed transcriptions, manual crops and user edits on rerun.
                if result[index].reviewedAt == nil && result[index].origin == "AI discovery" {
                    var replacement = value; replacement.id = result[index].id; result[index] = replacement
                }
            } else { result.append(value) }
        }
        return result
    }
}

public struct ModelAssetDiscovery: Decodable, Sendable {
    public struct Item: Decodable, Sendable {
        public var kind: SourceAssetKind
        public var page: Int
        public var label: String
        public var title: String
        public var caption: String
        public var warnings: [String]
    }
    public var assets: [Item]
}
