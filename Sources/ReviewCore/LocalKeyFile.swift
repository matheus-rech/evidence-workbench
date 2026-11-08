import Foundation

/// Reads only the approved variable as data. Never executes an env file as shell code.
public enum LocalKeyFile {
    public static func read(_ url: URL) throws -> String {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
        guard values.isSymbolicLink != true, values.isRegularFile == true, (values.fileSize ?? 0) <= 64_000 else { throw WorkbenchError.invalid("The API key file must be a regular file smaller than 64 KB, not a symbolic link.") }
        let text = try String(contentsOf: url, encoding: .utf8)
        for line in text.components(separatedBy: .newlines) {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "OPENAI_API_KEY" else { continue }
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            if let data = value.data(using: .utf8), let decoded = try? JSONDecoder().decode(String.self, from: data), !decoded.isEmpty { return decoded }
            let unquoted = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            guard !unquoted.isEmpty, !unquoted.contains(where: { $0.isWhitespace }) else { throw WorkbenchError.missingKey }
            return unquoted
        }
        throw WorkbenchError.missingKey
    }
}
