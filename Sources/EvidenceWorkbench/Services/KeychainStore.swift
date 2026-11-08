import Foundation
import Security
import ReviewCore

enum KeychainStore {
    private static let service = "com.matheusrech.EvidenceWorkbench.openai"
    private static let account = "api-key"
    private static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] }
    static func read() throws -> String {
        var request = query; request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8) else { throw WorkbenchError.invalid("Keychain could not read the app's API key (\(status)).") }
        return key
    }
    static func save(_ key: String) throws {
        let data = Data(key.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query; attributes[kSecValueData as String] = data; attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let inserted = SecItemAdd(attributes as CFDictionary, nil)
            guard inserted == errSecSuccess else { throw WorkbenchError.invalid("Keychain could not save the API key (\(inserted)).") }
        } else if status != errSecSuccess { throw WorkbenchError.invalid("Keychain could not update the API key (\(status)).") }
    }
    static func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw WorkbenchError.invalid("Keychain could not remove the API key (\(status)).") }
    }
}
