import Foundation
import ReviewCore

enum AppCredentials {
    static var keyFileURL: URL? {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--api-key-file"), index + 1 < args.count { return URL(fileURLWithPath: args[index + 1]) }
        if let path = UserDefaults.standard.string(forKey: "apiKeyFile"), !path.isEmpty { return URL(fileURLWithPath: path) }
        // Source-package builds live in <project>/dist/App.app; the approved key stays outside the bundle.
        let local = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".env.local")
        return FileManager.default.fileExists(atPath: local.path) ? local : nil
    }
    static func read() throws -> String {
        if let url = keyFileURL { return try LocalKeyFile.read(url) }
        let key = try KeychainStore.read()
        guard !key.isEmpty else { throw WorkbenchError.missingKey }
        return key
    }
    static func checkConnection() async -> String {
        do {
            let models = try await availableModels()
            return "Connected to OpenAI. \(models.count) model identifiers returned; no paid inference was run. Listing does not establish feature compatibility."
        } catch { return "Connection check failed (\(type(of: error))). The credential was not displayed." }
    }

    static func availableModels() async throws -> [String] {
        let key = try read()
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!); request.timeoutInterval = 30
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw WorkbenchError.invalid("Could not list models. Check API authentication and project permissions.") }
        struct ModelList: Decodable { struct Model: Decodable { var id: String }; var data: [Model] }
        return try JSONDecoder().decode(ModelList.self, from: data).data.map(\.id).filter { $0.count < 150 && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.:".contains($0)) } }.sorted()
    }
}
