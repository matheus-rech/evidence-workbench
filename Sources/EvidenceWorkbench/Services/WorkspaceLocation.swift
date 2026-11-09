import Foundation

enum WorkspaceLocation {
    static func resolve(arguments: [String], bundleURL: URL, identifier: String?, isolated: Bool, configuredQA: String?, normal: URL) -> URL {
        if let index = arguments.firstIndex(of: "--workspace"), index + 1 < arguments.count {
            return URL(fileURLWithPath: arguments[index + 1])
        }
        if isolated || identifier?.hasSuffix(".Review") == true || identifier?.hasSuffix(".QA") == true {
            // Release and Debug obey the same isolation rule. No fallback to the production workspace.
            if identifier?.hasSuffix(".QA") == true, let configuredQA, !configuredQA.isEmpty { return URL(fileURLWithPath: configuredQA) }
            return bundleURL.deletingLastPathComponent().appendingPathComponent("ReviewData", isDirectory: true)
        }
        return normal
    }
}
