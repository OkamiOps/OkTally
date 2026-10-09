import Foundation

enum KiroSessionSource { case ide, cli }

protocol KiroSessionImporting {
    /// Retorna uma sessão validada sem gravar credenciais nem alterar o Kiro.
    func importSession(source: KiroSessionSource) async throws -> OAuthToken
}

enum KiroAccountImportError: Error, LocalizedError {
    case differentAccount
    case missingIdentity

    var errorDescription: String? {
        switch self {
        case .differentAccount:
            return L("Esta sessão pertence a outra conta Kiro. Use Adicionar conta → Kiro para acompanhá-la separadamente.")
        case .missingIdentity:
            return L("O Kiro não informou a identidade desta sessão. Entre novamente no Kiro e tente importar.")
        }
    }
}

enum KiroAccountImport {
    static func identity(from token: OAuthToken) -> AccountIdentity {
        let trimmed = token.extra["email"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = trimmed.flatMap { $0.isEmpty ? nil : $0 }
        let key = token.extra["profileArn"].flatMap { $0.isEmpty ? nil : $0 } ?? email?.lowercased()
        return AccountIdentity(email: email, identityKey: key, autoLabel: token.extra["profileName"])
    }

    /// Reimportar nunca muda a identidade de uma conta cujo histórico já existe.
    static func validate(_ token: OAuthToken, replacing account: AccountInstance?) throws {
        let identity = identity(from: token)
        guard let key = identity.identityKey else { throw KiroAccountImportError.missingIdentity }
        if let expected = account?.identityKey, expected.lowercased() != key.lowercased() {
            throw KiroAccountImportError.differentAccount
        }
    }
}
