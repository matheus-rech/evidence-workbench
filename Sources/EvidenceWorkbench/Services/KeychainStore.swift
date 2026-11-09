import Foundation
import Security
import ReviewCore

enum KeychainStore {
    private static var service: String { Bundle.main.object(forInfoDictionaryKey: "EWIsolatedReview") as? Bool == true ? "com.matheusrech.EvidenceWorkbench.Review.openai" : "com.matheusrech.EvidenceWorkbench.openai" }
    private static let account = "api-key"
    private static func query(_ provider: String) -> [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: provider == "huggingface" ? service + ".huggingface" : service, kSecAttrAccount as String: account] }
    static func read(provider: String = "openai") throws -> String {
        var request = query(provider); request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8) else { throw WorkbenchError.invalid("Keychain could not read the app's API key (\(status)).") }
        return key
    }
    static func save(_ key: String, provider: String = "openai") throws {
        let data = Data(key.utf8)
        let status = SecItemUpdate(query(provider) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query(provider); attributes[kSecValueData as String] = data; attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let inserted = SecItemAdd(attributes as CFDictionary, nil)
            guard inserted == errSecSuccess else { throw WorkbenchError.invalid("Keychain could not save the API key (\(inserted)).") }
        } else if status != errSecSuccess { throw WorkbenchError.invalid("Keychain could not update the API key (\(status)).") }
    }
    static func delete(provider: String = "openai") throws {
        let status = SecItemDelete(query(provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw WorkbenchError.invalid("Keychain could not remove the API key (\(status)).") }
    }
}
