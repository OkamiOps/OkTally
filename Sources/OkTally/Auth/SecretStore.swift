// Sources/OkTally/Auth/SecretStore.swift
import Foundation
import Security

/// Storage for provider API keys — a secret, same as an OAuth token, so it belongs in the
/// Keychain rather than `UserDefaults` (`~/Library/Preferences/*.plist`, readable by any
/// process running as the user and unencrypted in Time Machine/iCloud backups). Mirrors
/// `TokenStoring`'s shape deliberately: same service-name convention (just a different
/// namespace: `com.oktally.app.apikey.<providerId>` vs. `...oauth.<providerId>`), same
/// update-before-add atomicity, same `afterFirstUnlock` accessibility.
protocol SecretStoring {
    func save(_ secret: String, providerId: String) throws
    func load(providerId: String) -> String?
    func delete(providerId: String) throws
}

enum SecretStoreError: Error, LocalizedError {
    case keychainWriteFailed(OSStatus)
    case keychainDeleteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychainWriteFailed(let status):
            return "Falha ao gravar chave de API no Keychain (status \(status))."
        case .keychainDeleteFailed(let status):
            return "Falha ao remover chave de API do Keychain (status \(status))."
        }
    }
}

final class KeychainSecretStore: SecretStoring {
    private func service(_ providerId: String) -> String { "com.oktally.app.apikey.\(providerId)" }

    /// Same update-then-add-only-on-not-found pattern as `KeychainTokenStore.save` — see
    /// its doc comment for why delete-then-add is unsafe.
    func save(_ secret: String, providerId: String) throws {
        let data = Data(secret.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service(providerId),
            kSecAttrAccount as String: "oktally"
        ]
        // Also set on update, not just on add — see `KeychainTokenStore.save`'s matching
        // comment: `SecItemUpdate` only applies attributes explicitly passed to it, so
        // items from older builds would otherwise keep the pre-upgrade accessibility.
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw SecretStoreError.keychainWriteFailed(updateStatus)
        }
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw SecretStoreError.keychainWriteFailed(addStatus) }
    }

    func load(providerId: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service(providerId),
            kSecAttrAccount as String: "oktally",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func delete(providerId: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service(providerId),
            kSecAttrAccount as String: "oktally"
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.keychainDeleteFailed(status)
        }
    }
}
