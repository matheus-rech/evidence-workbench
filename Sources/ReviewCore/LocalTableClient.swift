import Foundation

/// Loopback-only specialist service. Models remain outside the application bundle.
public actor LocalTableClient {
    private let transport: any ResponsesTransport
    public init(transport: any ResponsesTransport = URLSessionTransport()) { self.transport = transport }
    public func transcribe(image: PageImage, title: String, endpoint: String) async throws -> ModelTableReply {
        guard let url = URL(string: endpoint), url.scheme == "http", ["127.0.0.1", "localhost", "[::1]"].contains(url.host?.lowercased() ?? ""), url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { throw WorkbenchError.invalid("Local PaddleOCR requires an HTTP loopback endpoint. No remote image was sent.") }
        guard image.page > 0, image.dataURL.hasPrefix("data:image/jpeg;base64,"), image.dataURL.count <= 5_400_000 else { throw WorkbenchError.invalid("Local table OCR requires one bounded JPEG.") }
        var request = URLRequest(url: url); request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["image": image.dataURL])
        let (data, status, _) = try await transport.send(request)
        guard status == 200, data.count <= 4_000_000, let reply = try JSONSerialization.jsonObject(with: data) as? [String: String], reply["model_revision"] == "132c45f52c0a26ed5a6b2f6bd8e3985794cc27dd", let text = reply["text"] else { throw WorkbenchError.invalid("Local PaddleOCR did not return a complete response from the measured model revision.") }
        return try PaddleTableParser.parse(text, title: title)
    }
}

/// Native Paddle OTSL output to an inert rectangular grid; no guessed column shifts.
public enum PaddleTableParser {
    public static func parse(_ text: String, title: String) throws -> ModelTableReply {
        guard text.count <= 2_000_000, text.contains("<fcel>"), !text.contains("<script") else { throw WorkbenchError.invalid("PaddleOCR returned no bounded OTSL table.") }
        let regex = try NSRegularExpression(pattern: "<(fcel|ecel|lcel|ucel|xcel|nl)>")
        let ns = text as NSString; let tokens = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard tokens.count <= 20_500 else { throw WorkbenchError.invalid("Paddle table exceeds the cell limit.") }
        var grid: [[String]] = []; var row: [String] = []; var kinds: [String] = []; var fullRows: Set<Int> = []
        for (index, token) in tokens.enumerated() {
            let kind = ns.substring(with: token.range(at: 1))
            let end = index + 1 < tokens.count ? tokens[index + 1].range.location : ns.length
            let content = ns.substring(with: NSRange(location: token.range.location + token.range.length, length: end - token.range.location - token.range.length)).trimmingCharacters(in: .whitespacesAndNewlines)
            if kind == "nl" {
                guard !row.isEmpty, grid.count < 500, content.isEmpty else { throw WorkbenchError.invalid("Paddle table contains an invalid row boundary.") }
                if kinds.first == "fcel", kinds.dropFirst().allSatisfy({ $0 == "lcel" }), row.count > 1 { fullRows.insert(grid.count) }
                grid.append(row); row = []; kinds = []
            } else {
                guard row.count < 40, content.count <= 10_000 else { throw WorkbenchError.invalid("Paddle table exceeds the supported grid limit.") }
                kinds.append(kind)
                switch kind {
                case "fcel": row.append(content.replacingOccurrences(of: "\\pm", with: "±"))
                case "ecel": guard content.isEmpty else { throw WorkbenchError.invalid("Paddle blank cell contains unexpected text.") }; row.append("")
                case "lcel": guard content.isEmpty, let left = row.last else { throw WorkbenchError.invalid("Paddle horizontal span has no anchor.") }; row.append(left)
                default: guard content.isEmpty, let above = grid.last, above.count > row.count else { throw WorkbenchError.invalid("Paddle vertical span has no anchor.") }; row.append(above[row.count])
                }
            }
        }
        if !row.isEmpty { grid.append(row) }
        guard let first = grid.first, grid.count >= 2, !first.isEmpty, grid.allSatisfy({ $0.count == first.count }) else { throw WorkbenchError.invalid("Paddle table is incomplete or ragged; no column was inferred.") }
        func escape(_ s: String) -> String { s.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;") }
        let notes = grid.indices.filter { fullRows.contains($0) && $0 > 0 }.map { grid[$0][0] }
        if fullRows.contains(0), grid[0][0].lowercased().hasPrefix("table") { grid.removeFirst(); fullRows = Set(fullRows.map { $0 - 1 }) }
        grid = grid.enumerated().filter { !fullRows.contains($0.offset) }.map(\.element)
        guard grid.count >= 2 else { throw WorkbenchError.invalid("Paddle table has no body rows.") }
        let html = "<table>" + grid.map { "<tr>" + $0.map { "<td>" + escape($0) + "</td>" }.joined() + "</tr>" }.joined() + "</table>"
        var result = try GLMTableParser.parse(html, title: title)
        result.footnotes = notes
        result.warnings = ["PaddleOCR-VL-1.6 local AI draft, measured model revision 132c45f. Check headers, units, spans and omitted footnotes. This does not verify dataset observations."]
        return result
    }
}
