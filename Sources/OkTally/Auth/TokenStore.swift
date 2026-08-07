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

    func save(_ token: OAuthToken, providerId: String) throws {
        let data = try JSONEncoder().encode(token)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service(providerId),
            kSecAttrAccount as String: "oktally"
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw TokenStoreError.keychainWriteFailed(status) }
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
