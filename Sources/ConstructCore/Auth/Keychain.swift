import Foundation
import Security

/// Thin wrapper over the macOS/iOS Keychain for storing secrets
/// (auth tokens, OAuth credentials). Replaces the Rust `construct_auth_*`
/// keychain commands.
public struct Keychain: Sendable {
    public let service: String

    public init(service: String = "space.construct.app") {
        self.service = service
    }

    public func set(_ value: String, for account: String) throws {
        let data = Data(value.utf8)
        // Delete any existing item first so we always write fresh.
        delete(account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    public func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    public func delete(_ account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

public enum KeychainError: Error, LocalizedError {
    case status(OSStatus)
    public var errorDescription: String? {
        switch self {
        case let .status(s):
            let msg = SecCopyErrorMessageString(s, nil) as String? ?? "unknown"
            return "Keychain error \(s): \(msg)"
        }
    }
}
