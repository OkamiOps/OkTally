// Sources/OkTally/Plugins/Cursor/CursorTokenReader.swift
import Foundation
import GRDB

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

    init(dbPath: String = NSHomeDirectory() + "/Library/Application Support/Cursor/User/globalStorage/state.vscdb") {
        self.dbPath = dbPath
    }

    func readAccessToken() -> String? {
        readItem(key: "cursorAuth/accessToken")
    }

    func readMembershipType() -> String? {
        readItem(key: "cursorAuth/stripeMembershipType")
    }

    /// E-mail que o Cursor cacheia junto da sessão — rótulo da conta legada.
    func readEmail() -> String? {
        readItem(key: "cursorAuth/cachedEmail").flatMap { $0.isEmpty ? nil : $0 }
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
