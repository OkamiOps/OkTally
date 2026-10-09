import Foundation
import GRDB

/// Dados que o Kiro CLI mantém em sua única sessão global. Esta estrutura só existe
/// durante a importação: depois dela, a cópia isolada vive no Keychain do OkTally.
struct KiroCLISession: Equatable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
    let oidcRegion: String
    let startURL: String?
    let clientId: String
    let clientSecret: String
    let clientSecretExpiresAt: Date?
    let profileArn: String
    let profileName: String?
}

protocol KiroSessionReading {
    func readCLISession() throws -> KiroCLISession
}

enum KiroSessionReaderError: Error, LocalizedError {
    case cliSessionNotFound
    case unsupportedAuthentication
    case incompleteSession

    var errorDescription: String? {
        switch self {
        case .cliSessionNotFound:
            return L("Sessão do Kiro CLI não encontrada. Faça login no Kiro CLI e tente importar novamente.")
        case .unsupportedAuthentication:
            return L("Esta sessão do Kiro não expõe o registro OIDC necessário. Logins Social/Builder ID ainda não podem ser importados por esta versão.")
        case .incompleteSession:
            return L("A sessão do Kiro CLI está incompleta. Faça login novamente no Kiro CLI e tente importar.")
        }
    }
}

/// Leitor estritamente read-only do banco do Kiro CLI independente. O IDE não entra
/// aqui: suas credenciais dependem do Secret Storage/Keychain do VS Code e não formam
/// um bundle copiável previsível para múltiplas contas.
final class KiroSessionReader: KiroSessionReading {
    private let dbPath: String

    init(dbPath: String = NSHomeDirectory() + "/Library/Application Support/kiro-cli/data.sqlite3") {
        self.dbPath = dbPath
    }

    func readCLISession() throws -> KiroCLISession {
        guard FileManager.default.fileExists(atPath: dbPath) else {
            throw KiroSessionReaderError.cliSessionNotFound
        }

        var configuration = Configuration()
        configuration.readonly = true
        guard let queue = try? DatabaseQueue(path: dbPath, configuration: configuration) else {
            throw KiroSessionReaderError.cliSessionNotFound
        }

        let records: (token: Data?, registration: Data?, profile: Data?)
        do {
            records = try queue.read { db in
                guard try db.tableExists("auth_kv"), try db.tableExists("state") else {
                    return (nil, nil, nil)
                }
                return (
                    Self.value(in: db, table: "auth_kv", key: "kirocli:odic:token"),
                    Self.value(in: db, table: "auth_kv", key: "kirocli:odic:device-registration"),
                    Self.value(in: db, table: "state", key: "api.codewhisperer.profile")
                )
            }
        } catch {
            throw KiroSessionReaderError.cliSessionNotFound
        }

        guard let tokenData = records.token, let profileData = records.profile else {
            throw KiroSessionReaderError.cliSessionNotFound
        }
        // Sem um device registration OIDC, não há contrato confirmado para renovar a
        // cópia. Não inferimos um registro Social/Builder ID de outra tabela/chave.
        guard let registrationData = records.registration else {
            throw KiroSessionReaderError.unsupportedAuthentication
        }

        let token = Self.object(from: tokenData)
        let registration = Self.object(from: registrationData)
        let profile = Self.object(from: profileData)

        guard let accessToken = Self.string(in: token, keys: ["access_token", "accessToken"]),
              let clientId = Self.string(in: registration, keys: ["client_id", "clientId"]),
              let clientSecret = Self.string(in: registration, keys: ["client_secret", "clientSecret"]),
              let profileArn = Self.string(in: profile, keys: ["arn", "profile_arn", "profileArn"])
        else {
            throw KiroSessionReaderError.incompleteSession
        }

        // O region do registro é o do endpoint OIDC. A região do control plane vem do
        // profile ARN e é deliberadamente calculada só pelo provider, nunca daqui.
        guard let oidcRegion = Self.string(in: registration, keys: ["region"])
                ?? Self.string(in: token, keys: ["region"])
        else {
            throw KiroSessionReaderError.incompleteSession
        }

        return KiroCLISession(
            accessToken: accessToken,
            refreshToken: Self.string(in: token, keys: ["refresh_token", "refreshToken"]),
            expiresAt: Self.date(in: token, keys: ["expires_at", "expiresAt"]),
            oidcRegion: oidcRegion,
            startURL: Self.string(in: token, keys: ["start_url", "startURL"]),
            clientId: clientId,
            clientSecret: clientSecret,
            clientSecretExpiresAt: Self.date(in: registration, keys: ["client_secret_expires_at", "clientSecretExpiresAt"]),
            profileArn: profileArn,
            profileName: Self.string(in: profile, keys: ["profile_name", "profileName"])
        )
    }

    private static func value(in db: Database, table: String, key: String) -> Data? {
        guard let row = try? Row.fetchOne(db, sql: "SELECT value FROM \(table) WHERE key = ?", arguments: [key]) else {
            return nil
        }
        if let value: Data = row["value"] { return value }
        if let value: String = row["value"] { return Data(value.utf8) }
        return nil
    }

    private static func object(from data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private static func string(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    /// O CLI persiste epoch em segundos. Aceitamos milissegundos e ISO-8601 apenas para
    /// tolerar uma migração local, sem supor um vencimento quando o valor é inválido.
    private static func date(in object: [String: Any], keys: [String]) -> Date? {
        for key in keys {
            guard let value = object[key] else { continue }
            if let seconds = value as? Double { return date(epoch: seconds) }
            if let seconds = value as? Int { return date(epoch: Double(seconds)) }
            if let text = value as? String {
                if let seconds = Double(text) { return date(epoch: seconds) }
                let fractional = ISO8601DateFormatter()
                fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = fractional.date(from: text) { return date }
                if let date = ISO8601DateFormatter().date(from: text) { return date }
            }
        }
        return nil
    }

    private static func date(epoch: Double) -> Date? {
        guard epoch.isFinite, epoch > 0 else { return nil }
        let seconds = epoch > 10_000_000_000 ? epoch / 1_000 : epoch
        return Date(timeIntervalSince1970: seconds)
    }
}
