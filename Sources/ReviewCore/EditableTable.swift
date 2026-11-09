import Foundation

public struct EditableTable: Codable, Equatable, Sendable, Identifiable {
    public var id = UUID()
    public var title: String
    public var columns: [String]
    public var rows: [[String]]
    public var footnotes: [String]
    public var warnings: [String]
    public var reviewerNote: String?
    public var sourceFilename: String
    public var sourceSHA256: String
    public var page: Int
    public var region: EvidenceRegion
    public init(title: String, columns: [String], rows: [[String]], footnotes: [String] = [], warnings: [String] = [], sourceFilename: String, sourceSHA256: String, page: Int, region: EvidenceRegion) {
        self.title = title; self.columns = columns; self.rows = rows; self.footnotes = footnotes; self.warnings = warnings
        self.sourceFilename = sourceFilename; self.sourceSHA256 = sourceSHA256; self.page = page; self.region = region
    }
    public func validate() throws {
        if let row = rows.firstIndex(where: { $0.count != columns.count }) { throw WorkbenchError.invalid("Table row \(row + 1) contains \(rows[row].count) cells; expected \(columns.count). No columns were guessed or shifted.") }
        guard (1...40).contains(columns.count), rows.count <= 500, region.isValid, page > 0,
              (columns + rows.flatMap { $0 } + footnotes + warnings + [reviewerNote ?? ""]).allSatisfy({ $0.count <= 10_000 }) else {
            throw WorkbenchError.invalid("The table has invalid dimensions, cell lengths or source coordinates. No partial table was applied.")
        }
    }
    public var provenance: String { "Source: \(sourceFilename), PDF page \(page). SHA-256: \(sourceSHA256). Region (crop-box fractions): x=\(region.x), y=\(region.y), width=\(region.width), height=\(region.height)." }
    private func escapedHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "\n", with: "<br>")
    }
    public var html: String {
        let head = columns.map { "<th>\(escapedHTML($0))</th>" }.joined()
        let body = rows.map { "<tr>" + $0.map { "<td>\(escapedHTML($0))</td>" }.joined() + "</tr>" }.joined()
        return "<!doctype html><html><head><meta charset=\"utf-8\"><style>body{font-family:Helvetica,Arial,sans-serif}table{border-collapse:collapse}td,th{border:1px solid #777;padding:6px;vertical-align:top}</style></head><body><h2>\(escapedHTML(title))</h2><table><thead><tr>\(head)</tr></thead><tbody>\(body)</tbody></table>" + footnotes.map { "<p>\(escapedHTML($0))</p>" }.joined() + "<p>\(escapedHTML(provenance))</p>" + warnings.map { "<p>AI review note: \(escapedHTML($0))</p>" }.joined() + "<p>Reviewer note: \(escapedHTML(reviewerNote ?? ""))</p></body></html>"
    }
    private func spreadsheetSafe(_ value: String) -> String {
        let clean = value.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        let dangerous = clean.trimmingCharacters(in: .whitespacesAndNewlines).first.map { "=+-@".contains($0) } ?? false
        return dangerous && Double(clean).map(\.isFinite) != true ? "'" + clean : clean
    }
    public var tsv: String { ([columns] + rows).map { $0.map(spreadsheetSafe).joined(separator: "\t") }.joined(separator: "\n") + "\n" }
    public var csv: String { ([columns] + rows).map { $0.map(DatasetExporter.cell).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n" }
    private func escapedRTF(_ value: String) -> String {
        value.utf16.map { unit -> String in
            switch unit {
            case 92: return "\\\\"
            case 123: return "\\{"
            case 125: return "\\}"
            case 10, 13: return "\\line "
            case 9: return "\\tab "
            case 32...126: return String(UnicodeScalar(unit)!)
            default: return "\\u\(Int16(bitPattern: unit))?"
            }
        }.joined()
    }
    public var rtf: String {
        let width = max(700, 10_000 / max(columns.count, 1))
        func row(_ cells: [String], header: Bool) -> String {
            let positions = cells.indices.map { "\\cellx\(($0 + 1) * width)" }.joined()
            let content = cells.map { cell -> String in
                var result = "\\intbl "
                if header { result += "\\b " }
                result += escapedRTF(cell)
                if header { result += "\\b0 " }
                return result + "\\cell "
            }.joined()
            return "\\trowd\\trgaph100" + positions + "\n" + content + "\\row\n"
        }
        var result = "{\\rtf1\\ansi\\deff0{\\fonttbl{\\f0 Helvetica;}}\\f0\\fs20 "
        result += escapedRTF(title) + "\\par\n"
        result += row(columns, header: true)
        result += rows.map { row($0, header: false) }.joined()
        let notes = footnotes + [provenance] + warnings + ["Reviewer note: " + (reviewerNote ?? "")]
        result += "\\pard " + notes.map(escapedRTF).joined(separator: "\\par ") + "}"
        return result
    }
}

public struct ModelTableReply: Decodable, Sendable {
    public struct Row: Decodable, Sendable { public var cells: [String] }
    public var title: String
    public var columns: [String]
    public var rows: [Row]
    public var footnotes: [String]
    public var warnings: [String]
}
