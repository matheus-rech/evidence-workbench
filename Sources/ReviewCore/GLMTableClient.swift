import Foundation

/// Optional remote table specialist. The caller must obtain explicit Hugging Face image consent.
public actor GLMTableClient {
    private let transport: any ResponsesTransport
    private let endpoint = "https://prithivmlmods-glm-ocr-demo.hf.space/gradio_api/call/run_router"
    public init(transport: any ResponsesTransport = URLSessionTransport(allowRedirects: false)) { self.transport = transport }
    public func transcribe(image: PageImage, title: String = "", token: String = "") async throws -> ModelTableReply {
        guard image.page > 0, image.dataURL.hasPrefix("data:image/jpeg;base64,"), image.dataURL.count <= 5_400_000 else { throw WorkbenchError.invalid("Table OCR requires one bounded JPEG image.") }
        var request = URLRequest(url: URL(string: endpoint)!); request.httpMethod = "POST"
        if !token.isEmpty { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["data": ["Table", image.dataURL, 4096, 60]])
        let (data, status, _) = try await transport.send(request)
        guard status == 200, data.count < 100_000,
              let reply = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = reply["event_id"] as? String, (1...100).contains(event.count), event.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { throw WorkbenchError.invalid("Hugging Face could not start table OCR. No partial table or silent provider fallback was applied.") }
        var poll = URLRequest(url: URL(string: endpoint + "/" + event)!)
        if !token.isEmpty { poll.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        let (events, eventStatus, _) = try await transport.send(poll)
        guard eventStatus == 200 else { throw WorkbenchError.invalid("Hugging Face table OCR failed. Existing tables were preserved.") }
        return try GLMTableParser.parse(Self.completedText(events), title: title)
    }
    public static func completedText(_ data: Data) throws -> String {
        guard data.count <= 4_000_000, let text = String(data: data, encoding: .utf8) else { throw WorkbenchError.invalid("Table OCR response exceeds the supported limit.") }
        var event = ""; var completed: String?
        for line in text.components(separatedBy: .newlines) {
            if line.hasPrefix("event:") { event = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces) }
            else if line.hasPrefix("data:") {
                if event == "error" { throw WorkbenchError.invalid("The Hugging Face OCR service reported a failure or quota limit. No partial table was used.") }
                if event == "complete", let bytes = String(line.dropFirst(5)).data(using: .utf8), let values = try? JSONDecoder().decode([String].self, from: bytes), values.count == 1 { completed = values[0] }
            }
        }
        guard let completed, !completed.isEmpty, !completed.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[ERROR]") else { throw WorkbenchError.invalid("Table OCR did not complete. Partial output was discarded.") }
        return completed
    }
}

/// Converts a bounded untrusted HTML grid to inert cells; never renders HTML or fetches resources.
public enum GLMTableParser {
    private static func matches(_ pattern: String, _ text: String) throws -> [NSTextCheckingResult] {
        try NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]).matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }
    public static func parse(_ html: String, title: String) throws -> ModelTableReply {
        guard html.count <= 2_000_000, try matches("<(script|iframe|object|style)\\b|<!DOCTYPE|<!ENTITY", html).isEmpty else { throw WorkbenchError.invalid("Table OCR returned unsafe or oversized markup.") }
        guard try matches("<table\\b", html).count == 1, try matches("</table\\s*>", html).count == 1 else { throw WorkbenchError.invalid("Table OCR requires exactly one complete table; multiple or truncated grids were discarded.") }
        let source = html as NSString
        let rows = try matches("<tr\\b[^>]*>(.*?)</tr>", html)
        guard (2...500).contains(rows.count) else { throw WorkbenchError.invalid("Table OCR returned no complete bounded grid.") }
        var occupied: [Int: [Int: String]] = [:]
        var fullWidthRows: [Int: Int] = [:]
        var explicitHeaderRows: Set<Int> = []
        var firstRowGrouped = false
        for (r, match) in rows.enumerated() {
            let row = source.substring(with: match.range(at: 1)); let rowText = row as NSString
            let cells = try matches("<t[dh]\\b([^>]*)>(.*?)</t[dh]>", row)
            if !cells.isEmpty, try matches("<th\\b", row).count == cells.count { explicitHeaderRows.insert(r) }
            var c = 0
            for cell in cells {
                while occupied[r]?[c] != nil { c += 1 }
                let attributes = rowText.substring(with: cell.range(at: 1))
                func span(_ name: String) throws -> Int {
                    guard let match = try matches("\\b" + name + "\\s*=\\s*[\"']?(\\d+)", attributes).first else { return 1 }
                    guard let n = Int((attributes as NSString).substring(with: match.range(at: 1))), (1...40).contains(n) else { throw WorkbenchError.invalid("Table OCR contains an invalid span.") }
                    return n
                }
                let across = try span("colspan"), down = try span("rowspan")
                if r == 0 && across > 1 && cells.count > 1 { firstRowGrouped = true }
                if cells.count == 1 && across > 1 { fullWidthRows[r] = across }
                guard c + across <= 40, r + down <= rows.count else { throw WorkbenchError.invalid("Table OCR span exceeds the grid.") }
                let raw = rowText.substring(with: cell.range(at: 2))
                var value = raw.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression).replacingOccurrences(of: "</?[A-Za-z][^>]*>", with: "", options: .regularExpression)
                for (entity, literal) in [("&nbsp;", " "),("&lt;","<"),("&gt;",">"),("&quot;","\""),("&plusmn;","±"),("&ndash;","–"),("&amp;","&")] { value = value.replacingOccurrences(of: entity, with: literal) }
                value = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard value.count <= 10_000 else { throw WorkbenchError.invalid("Table OCR cell exceeds the supported limit.") }
                for y in r..<(r + down) { for x in c..<(c + across) {
                    guard occupied[y]?[x] == nil else { throw WorkbenchError.invalid("Table OCR cells overlap.") }
                    occupied[y, default: [:]][x] = value
                } }
                c += across
            }
        }
        let width = (occupied[0]?.keys.max() ?? -1) + 1
        guard (1...40).contains(width), rows.indices.allSatisfy({ occupied[$0]?.count == width && Set(occupied[$0]?.keys.map { $0 } ?? []) == Set(0..<width) }) else { throw WorkbenchError.invalid("Table OCR returned ragged rows; no column was guessed or shifted.") }
        let grid = rows.indices.map { r in (0..<width).map { occupied[r]?[$0] ?? "" } }
        var headers = 1
        var headerNotes: Set<Int> = []
        while headers < min(8, grid.count - 1), explicitHeaderRows.contains(headers) {
            if fullWidthRows[headers] == width {
                let label = grid[headers][0].trimmingCharacters(in: .whitespacesAndNewlines)
                let markedNote = label.range(of: "^(note|footnote|source)\\b", options: [.regularExpression, .caseInsensitive]) != nil
                if markedNote { headerNotes.insert(headers) }
                else if !explicitHeaderRows.contains(headers + 1) || fullWidthRows[headers + 1] == width {
                    throw WorkbenchError.invalid("A full-width header may be a heading or note. Its role is ambiguous; no table structure was guessed.")
                }
            }
            headers += 1
        }
        if headers == 1, firstRowGrouped, grid[0][0].isEmpty, grid.count > 2 {
            guard explicitHeaderRows.contains(1) else { throw WorkbenchError.invalid("A grouped table with an empty corner needs explicit header rows; no header/data boundary was guessed.") }
            headers = 2
        }
        while headers < min(8, grid.count - 1), !grid[0][0].isEmpty, grid[headers][0] == grid[0][0] { headers += 1 }
        let columns = (0..<width).map { column -> String in
            var labels: [String] = []
            for index in 0..<headers where !headerNotes.contains(index) && !grid[index][column].isEmpty && !labels.contains(grid[index][column]) { labels.append(grid[index][column]) }
            return labels.isEmpty ? (column == 0 ? "[Row label]" : "[Unlabeled column \(column + 1)]") : labels.joined(separator: " / ")
        }
        let mergedNotes = grid.indices.filter { headerNotes.contains($0) || ($0 >= headers && fullWidthRows[$0] == width) }.map { grid[$0][0] }
        let body = grid.indices.filter { $0 >= headers && fullWidthRows[$0] != width }.map { grid[$0] }
        return ModelTableReply(title: title.isEmpty ? "OCR table" : String(title.prefix(2_000)), columns: columns, rows: body.map { .init(cells: $0) }, footnotes: mergedNotes, warnings: ["GLM-OCR AI draft from a Hugging Face community Space. Check cells, headers, units and omitted footnotes. The hosted model revision is not guaranteed immutable. This does not verify dataset observations."])
    }
}
