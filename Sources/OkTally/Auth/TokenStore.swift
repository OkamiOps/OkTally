import Foundation
import Security

protocol TokenStoring {
    func save(_ token: OAuthToken, providerId: String) throws
    func load(providerId: String) -> OAuthToken?
    func delete(providerId: String) throws
}

enum TokenStoreError: Error, LocalizedError {
    case keychainWriteFailed(OSStatus)
    case keychainDeleteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychainWriteFailed(let status):
            return "Falha ao gravar token no Keychain (status \(status))."
        case .keychainDeleteFailed(let status):
            return "Falha ao remover token do Keychain (status \(status))."
        }
    }
}

final class KeychainTokenStore: TokenStoring {
    private func service(_ providerId: String) -> String { "com.oktally.app.oauth.\(providerId)" }

    /// Updates in place when the item already exists, falling back to add only when it
    /// doesn't. NOT delete-then-add: a crash (or being killed) between those two calls
    /// would leave the user with no stored token at all, i.e. signed out, even though the
    /// old token was still valid. `SecItemUpdate` mutates the existing keychain entry
    /// atomically, so there's no window where the item is missing.
    func save(_ token: OAuthToken, providerId: String) throws {
        let data = try JSONEncoder().encode(token)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service(providerId),
            kSecAttrAccount as String: "oktally"
        ]
        // Also set on update, not just on add: items written by older builds (which used
        // a delete-then-add without this attribute) land here via `SecItemUpdate` and,
        // without this line, would keep the pre-upgrade default accessibility forever —
        // `SecItemUpdate` only touches attributes explicitly passed to it.
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw TokenStoreError.keychainWriteFailed(updateStatus)
        }
        var attributes = query
        attributes[kSecValueData as String] = data
        // Menu-bar app that refreshes tokens from a background loop, potentially before
        // the user has unlocked their session after boot — `afterFirstUnlock` keeps the
        // token readable then, unlike the SO default which can require an active unlock.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw TokenStoreError.keychainWriteFailed(addStatus) }
    }

    func load(providerId: String) -> OAuthToken? {
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
        return try? JSONDecoder().decode(OAuthToken.self, from: data)
    }

    func delete(providerId: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service(providerId),
            kSecAttrAccount as String: "oktally"
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TokenStoreError.keychainDeleteFailed(status)
        }
    }
}
