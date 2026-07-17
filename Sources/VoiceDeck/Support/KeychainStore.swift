import Foundation
import Security

enum KeychainKey: String {
    case dashScopeAPIKey = "dashscope-api-key"
}

enum KeychainStore {
    private static let service = "com.bobhe.voicedeck"
    private static var cachedValues: [KeychainKey: String] = [:]

    static func value(for key: KeychainKey) -> String? {
        if let cachedValue = cachedValues[key] { return cachedValue }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        let value = String(data: data, encoding: .utf8)
        if let value { cachedValues[key] = value }
        return value
    }

    static func save(_ value: String, for key: KeychainKey) throws {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        let addQuery: [String: Any] = deleteQuery.merging([
            kSecValueData as String: Data(value.utf8)
        ]) { _, new in new }
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unableToSave(status) }
        cachedValues[key] = value
    }
}

private enum KeychainError: LocalizedError {
    case unableToSave(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .unableToSave(status): "无法保存 API Key（钥匙串错误 \(status)）。"
        }
    }
}
