import Foundation
import Security

enum ClaudeCredentialError: Error, Equatable {
    case notFound
    case malformed
}

extension ClaudeCredentialError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Credenciais do Claude Code não encontradas — faça login com `claude login` no terminal."
        case .malformed:
            return "Credenciais do Claude Code em formato inesperado."
        }
    }
}

protocol CredentialStoreReading {
    func readClaudeCredentialsJSON() -> Data?
}

final class KeychainCredentialReader: CredentialStoreReading {
    func readClaudeCredentialsJSON() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecAttrAccount as String: NSUserName(),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return data
    }
}

final class ClaudeCredentialProvider {
    private let keychainReader: CredentialStoreReading
    private let fileURL: URL

    init(
        keychainReader: CredentialStoreReading = KeychainCredentialReader(),
        fileURL: URL = URL(fileURLWithPath: NSHomeDirectory() + "/.claude/.credentials.json")
    ) {
        self.keychainReader = keychainReader
        self.fileURL = fileURL
    }

    func loadCredentials() throws -> ClaudeCredentials {
        guard let data = keychainReader.readClaudeCredentialsJSON() ?? (try? Data(contentsOf: fileURL)) else {
            throw ClaudeCredentialError.notFound
        }
        guard let credentials = Self.decode(data) else {
            throw ClaudeCredentialError.malformed
        }
        return credentials
    }

    private static func decode(_ data: Data) -> ClaudeCredentials? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        struct Wrapper: Codable { let claudeAiOauth: ClaudeCredentials }
        if let wrapper = try? decoder.decode(Wrapper.self, from: data) {
            return wrapper.claudeAiOauth
        }
        return try? decoder.decode(ClaudeCredentials.self, from: data)
    }
}
