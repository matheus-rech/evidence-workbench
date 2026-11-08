import Foundation

/// Maps whitespace/ligature-normalized matches back to original UTF-16 offsets.
/// Never changes digits, decimal points, punctuation or case; never guesses a partial match.
public enum QuoteLocator {
    private struct Mapped {
        var text = ""
        var ranges: [NSRange] = []
    }
    private static func mapped(_ value: String) -> Mapped {
        var output = Mapped(); var offset = 0
        let ligatures = ["ﬁ": "fi", "ﬂ": "fl", "ﬀ": "ff", "ﬃ": "ffi", "ﬄ": "ffl"]
        for character in value {
            let original = String(character); let length = original.utf16.count
            defer { offset += length }
            if original == "\u{00AD}" { continue }
            let normalized = character.isWhitespace ? " " : (ligatures[original] ?? original.precomposedStringWithCanonicalMapping)
            if normalized == " ", output.text.hasSuffix(" ") {
                if let last = output.ranges.last { output.ranges[output.ranges.count - 1] = NSRange(location: last.location, length: offset + length - last.location) }
                continue
            }
            output.text += normalized
            output.ranges.append(contentsOf: Array(repeating: NSRange(location: offset, length: length), count: normalized.utf16.count))
        }
        return output
    }
    public static func normalized(_ value: String) -> String { mapped(value).text.trimmingCharacters(in: .whitespacesAndNewlines) }
    public static func matches(in text: String, quote: String) -> [NSRange] {
        let source = mapped(text); let target = normalized(quote)
        guard !target.isEmpty else { return [] }
        let string = source.text as NSString
        var search = NSRange(location: 0, length: string.length); var result: [NSRange] = []
        while search.length > 0 {
            let found = string.range(of: target, options: [], range: search)
            if found.location == NSNotFound { break }
            let first = source.ranges[found.location]; let last = source.ranges[NSMaxRange(found) - 1]
            result.append(NSRange(location: first.location, length: NSMaxRange(last) - first.location))
            let next = found.location + 1
            search = NSRange(location: next, length: string.length - next)
        }
        return result
    }
    public static func resolve(in text: String, quote: String, start: Int? = nil, length: Int? = nil) -> NSRange? {
        if start != nil || length != nil {
            guard let start, let length, start >= 0, length > 0, start <= (text as NSString).length, length <= (text as NSString).length - start else { return nil }
            let range = NSRange(location: start, length: length)
            if !normalized(quote).isEmpty, normalized((text as NSString).substring(with: range)) == normalized(quote) { return range }
            return nil // An invalid saved anchor must not jump to another occurrence.
        }
        let ranges = matches(in: text, quote: quote)
        return ranges.count == 1 ? ranges[0] : nil
    }
}
