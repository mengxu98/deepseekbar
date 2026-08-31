import Foundation
import Security

/// Stores DeepSeekBar's own API keys in the macOS Keychain.
///
/// Secret material never touches disk: only non-sensitive account metadata
/// is written to Application Support (see APIKeyStore). Each account's key
/// is stored under service "com.deepseekbar.app" with account = account UUID,
/// which keeps it separate from DeepSeek-TUI's Keychain entries (service
/// "deepseek").
struct AppKeychainStore: KeychainStoring {
    static let service = "com.deepseekbar.app"

    func get(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Stores or updates a key. Prefers update so no read-modify-write gap
    /// ever leaves the entry missing (unlike delete-then-add).
    func set(_ key: String, account: String) throws {
        let data = Data(key.utf8)
        var query = baseQuery(account: account)

        let updateAttrs: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, updateAttrs as CFDictionary) == errSecSuccess {
            return
        }

        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AppKeychainError.unhandledStatus(status, operation: "add")
        }
    }

    func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]
    }
}

enum AppKeychainError: LocalizedError {
    case unhandledStatus(OSStatus, operation: String)

    var errorDescription: String? {
        switch self {
        case let .unhandledStatus(status, operation):
            return "Keychain \(operation) failed with status \(status)."
        }
    }
}
