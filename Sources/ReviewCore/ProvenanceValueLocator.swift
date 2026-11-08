import Foundation

/// Literal emphasis only. This never establishes whether a quote supports a value.
public enum ProvenanceValueLocator {
    public static func ranges(value: String, quote: String, numeric: Bool) -> [NSRange] {
        let literal = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !literal.isEmpty else { return [] }
        let escaped = NSRegularExpression.escapedPattern(for: literal)
        // Do not emphasize 5 in 15, -5, 5.2, 1,500 or 5e3.
        let pattern = numeric ? "(?<![\\p{N}.,+\\-])" + escaped + "(?![\\p{N}.,eE])" : escaped
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: quote, range: NSRange(location: 0, length: (quote as NSString).length)).map(\.range)
    }
}
