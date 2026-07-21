import Foundation
import Security

enum KeychainKey: String {
    case dashScopeAPIKey = "dashscope-api-key"
}

enum KeychainStore {
    private static let service = "com.bobhe.voicedeck.capture"
    private static var cachedValues: [String: String] = [:]

    static func value(for key: KeychainKey) -> String? {
        value(forReference: key.rawValue)
    }

    static func value(forReference reference: String) -> String? {
        if let cachedValue = cachedValues[reference] { return cachedValue }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: reference,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        let value = String(data: data, encoding: .utf8)
        if let value { cachedValues[reference] = value }
        return value
    }

    static func save(_ value: String, for key: KeychainKey) throws {
        try save(value, forReference: key.rawValue)
    }

    static func save(_ value: String, forReference reference: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: reference
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8)
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        let status: OSStatus
        if updateStatus == errSecItemNotFound {
            let addQuery = query.merging(attributes) { _, new in new }
            status = SecItemAdd(addQuery as CFDictionary, nil)
        } else {
            status = updateStatus
        }
        guard status == errSecSuccess else { throw KeychainError.unableToSave(status) }
        cachedValues[reference] = value
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
