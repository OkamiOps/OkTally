// Sources/OkTally/Plugins/Cursor/CursorTokenReader.swift
import CommonCrypto
import Foundation
import GRDB
import Security

protocol CursorTokenReading {
    func readAccessToken() -> String?
    /// Plano da conta ("pro", "free", "pro_student"…) que o app Cursor cacheia no mesmo
    /// banco. `nil` quando ausente — o badge só não aparece.
    func readMembershipType() -> String?
    // Requisitos (e não só extensão) para o despacho ser dinâmico: com a extensão
    // sozinha, quem guarda um `CursorTokenReading` chamaria sempre o padrão.
    func hasCredential() -> Bool
    func unavailableError() -> Error?
}

extension CursorTokenReading {
    func readMembershipType() -> String? { nil }

    /// Existe uma credencial configurada (mesmo que vencida)? Para o IDE, é ter token.
    func hasCredential() -> Bool { readAccessToken() != nil }

    /// Por que não há token utilizável, quando o motivo não é "nada configurado". `nil`
    /// deixa o provedor usar o erro de sempre.
    func unavailableError() -> Error? { nil }
}

/// Sessão do Cursor de uma conta EXTRA: gravada no Keychain pelo login próprio
/// (`CursorDeepLoginFlow`) sob o id da conta, e dividida pelo Cursor e pelo GrokBot gêmeo.
///
/// Não há renovação: o refresh do Cursor não pôde ser verificado ao vivo sem arriscar a
/// sessão do IDE do dono (ver docs/superpowers/research/multi-account-cursor.md). A
/// sessão vale ~60 dias; vencida, o provedor pede "Reconectar" (`needsReauth`).
final class KeychainCursorTokenSource: CursorTokenReading {
    private let instanceId: String
    private let tokenStore: TokenStoring

    init(instanceId: String, tokenStore: TokenStoring) {
        self.instanceId = instanceId
        self.tokenStore = tokenStore
    }

    func readAccessToken() -> String? {
        guard let token = tokenStore.load(providerId: instanceId), !token.isExpired else { return nil }
        return token.accessToken
    }

    /// O plano não vem junto da sessão própria; o badge só não aparece.
    func readMembershipType() -> String? { nil }

    func hasCredential() -> Bool { tokenStore.load(providerId: instanceId) != nil }

    func unavailableError() -> Error? {
        guard let token = tokenStore.load(providerId: instanceId), token.isExpired else { return nil }
        return OAuthError.noRefreshToken
    }
}

/// Reads the Cursor desktop app's own session token from its local VS Code-style
/// `state.vscdb` SQLite store. This is a sanctioned exception to the "don't depend on
/// third-party app internals" rule: without Cursor installed and logged in there is no
/// Cursor usage to measure in the first place, so this plugin degrades to a graceful
/// "not detected" state whenever the file, table, or row is absent — never a crash or
/// raw error.
final class CursorTokenReader: CursorTokenReading {
    private let dbPath: String
    private let safeStoragePassword: () -> String?
    private let passwordLock = NSLock()
    private var cachedPassword: String?

    /// `safeStoragePassword` só é consultado quando o token está cifrado — ler o Keychain
    /// de outro app pode pedir permissão ao usuário, então nunca acontece à toa.
    init(
        dbPath: String = NSHomeDirectory() + "/Library/Application Support/Cursor/User/globalStorage/state.vscdb",
        safeStoragePassword: @escaping () -> String? = CursorSafeStorage.readKeychainPassword
    ) {
        self.dbPath = dbPath
        self.safeStoragePassword = safeStoragePassword
    }

    func readAccessToken() -> String? {
        guard let stored = readItem(key: "cursorAuth/accessToken") else { return nil }
        guard CursorSafeStorage.isEncrypted(stored) else { return stored }
        return decrypt(stored)
    }

    /// Ter a linha basta: decifrar exigiria o Keychain, e isso fica para a busca.
    func hasCredential() -> Bool {
        readItem(key: "cursorAuth/accessToken") != nil
    }

    func readMembershipType() -> String? {
        readItem(key: "cursorAuth/stripeMembershipType")
    }

    /// E-mail que o Cursor cacheia junto da sessão — rótulo da conta legada.
    func readEmail() -> String? {
        readItem(key: "cursorAuth/cachedEmail").flatMap { $0.isEmpty ? nil : $0 }
    }

    /// A senha fica em memória depois da primeira leitura boa. Se o Cursor trocar a chave,
    /// a decifração falha e uma releitura do Keychain resolve.
    private func decrypt(_ stored: String) -> String? {
        passwordLock.lock()
        defer { passwordLock.unlock() }
        if let cachedPassword, let token = CursorSafeStorage.decrypt(stored, password: cachedPassword) {
            return token
        }
        guard let password = safeStoragePassword(),
              let token = CursorSafeStorage.decrypt(stored, password: password) else {
            cachedPassword = nil
            return nil
        }
        cachedPassword = password
        return token
    }

    private func readItem(key: String) -> String? {
        guard FileManager.default.fileExists(atPath: dbPath) else { return nil }

        var config = Configuration()
        config.readonly = true

        guard let dbQueue = try? DatabaseQueue(path: dbPath, configuration: config) else { return nil }

        return try? dbQueue.read { db -> String? in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT value FROM ItemTable WHERE key = ?",
                arguments: [key]
            ) else { return nil }

            if let string: String = row["value"] {
                return string
            }
            if let data: Data = row["value"] {
                return String(data: data, encoding: .utf8)
            }
            return nil
        }
    }
}

/// Desde o Cursor 3.27 (`cursor.storage.authTokenEncryptionAtRest`) os tokens no
/// `state.vscdb` vêm como `cursor-safe-storage:v1:<base64>`, cifrados pelo `safeStorage` do
/// Electron. No macOS isso é "v10" + AES-128-CBC, chave PBKDF2-SHA1(senha do Keychain,
/// "saltysalt", 1003 iterações), IV de 16 espaços. Conferido ao vivo em 2026-10-26: o
/// token cifrado mandado como Bearer dava 401 em todas as rotas; decifrado, 200.
enum CursorSafeStorage {
    static let prefix = "cursor-safe-storage:v1:"
    private static let electronVersionTag = Data("v10".utf8)

    static func isEncrypted(_ stored: String) -> Bool { stored.hasPrefix(prefix) }

    static func decrypt(_ stored: String, password: String) -> String? {
        guard isEncrypted(stored),
              let blob = Data(base64Encoded: String(stored.dropFirst(prefix.count))),
              blob.starts(with: electronVersionTag),
              let key = deriveKey(password: password) else { return nil }
        let ciphertext = blob.dropFirst(electronVersionTag.count)
        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)

        var output = Data(count: ciphertext.count + kCCBlockSizeAES128)
        var written = 0
        let outputCapacity = output.count
        let status = output.withUnsafeMutableBytes { out in
            ciphertext.withUnsafeBytes { input in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, key.count, ivBytes.baseAddress,
                            input.baseAddress, ciphertext.count,
                            out.baseAddress, outputCapacity, &written
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        // Senha errada às vezes passa no padding; texto que não é UTF-8 limpo é lixo.
        guard let token = String(data: output.prefix(written), encoding: .utf8),
              !token.isEmpty, token.allSatisfy({ $0.isASCII && !$0.isWhitespace }) else { return nil }
        return token
    }

    private static func deriveKey(password: String) -> Data? {
        let salt = Data("saltysalt".utf8)
        var key = Data(count: kCCKeySizeAES128)
        let status = key.withUnsafeMutableBytes { keyBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2), password, password.utf8.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003,
                    keyBytes.bindMemory(to: UInt8.self).baseAddress, kCCKeySizeAES128
                )
            }
        }
        return status == kCCSuccess ? key : nil
    }

    /// Item do próprio Cursor. Na primeira vez o macOS pergunta se o OkTally pode lê-lo
    /// ("Permitir Sempre" evita a pergunta de novo). Só roda dentro da busca, nunca na
    /// abertura do app.
    static func readKeychainPassword() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Cursor Safe Storage",
            kSecAttrAccount as String: "Cursor Key",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
