// Sources/OkTally/Auth/AccountEmailResolver.swift
import Foundation

/// Descobre o e-mail de uma conta depois do login (ou, para contas legadas, na primeira
/// leitura bem-sucedida). O e-mail é o rótulo automático e, normalizado, a chave de dedup.
///
/// Tudo aqui é melhor-esforço: nenhuma fonte lança, e uma conta sem e-mail descoberto
/// continua funcionando — só fica rotulada pelo apelido ou pela posição.
struct AccountEmailResolver {
    let tokenStore: TokenStoring
    let oauthManager: OAuthManaging
    let claudeProfile: ClaudeIdentityFetching?
    /// E-mail que o IDE Cursor cacheia no `state.vscdb` (só para a conta legada).
    let cursorEmail: () -> String?
    /// E-mail do login do IDE Antigravity (só para a conta legada).
    let antigravityEmail: () -> String?
    /// Chave de API salva de uma conta (por id).
    var apiKey: (String) -> String? = { _ in nil }
    /// Rótulo da chave no OpenRouter (`OpenRouterAPIClient.fetchKeyLabel`).
    var openRouterKeyLabel: (String) async -> String? = { _ in nil }

    func resolve(_ account: AccountInstance) async -> AccountIdentity {
        switch account.kind {
        case .openrouter, .minimax, .opencode:
            // Contas de chave não têm e-mail: a identidade é a impressão digital da chave.
            guard let key = apiKey(account.id), !key.isEmpty else { return AccountIdentity() }
            let label = account.kind == .openrouter ? await openRouterKeyLabel(key) : nil
            return AccountIdentity(identityKey: AccountDedup.fingerprint(apiKey: key), autoLabel: label)
        default:
            let email = await resolveEmail(account)
            guard let email, !email.isEmpty else { return AccountIdentity() }
            return AccountIdentity(email: email, identityKey: email.lowercased())
        }
    }

    private func resolveEmail(_ account: AccountInstance) async -> String? {
        let email: String?
        switch account.kind {
        case .claude:
            // Decisão do dono (2026-09-28): a identidade do Claude é só o e-mail. A org
            // não entra na chave, então a mesma pessoa em Pro e Team conta como uma.
            guard let accessToken = try? await oauthManager.validAccessToken(
                providerId: account.id, config: ClaudeOAuth.config.forInstance(account.id)
            ) else { return nil }
            email = await claudeProfile?.fetchIdentity(accessToken: accessToken)?.email
        case .codex:
            email = tokenStore.load(providerId: account.id).flatMap {
                Self.codexEmail(accessToken: $0.accessToken, extra: $0.extra)
            }
        case .supergrok:
            email = tokenStore.load(providerId: account.id)?.extra["email"]
        case .cursor:
            email = AccountID.isLegacy(account.id)
                ? cursorEmail()
                : tokenStore.load(providerId: account.id)?.extra["email"]
        case .antigravity:
            email = AccountID.isLegacy(account.id)
                ? antigravityEmail()
                : tokenStore.load(providerId: account.id)?.extra["email"]
        case .grokbot, .copilot, .mimo, .openrouter, .minimax, .opencode:
            email = nil
        }
        return email
    }

    /// Codex: o `email` do `id_token` (guardado em `extra` no login) ou, para logins
    /// antigos, a claim `https://api.openai.com/profile.email` do próprio access token.
    static func codexEmail(accessToken: String, extra: [String: String]) -> String? {
        if let email = extra["email"], !email.isEmpty { return email }
        let profile = JWT.decodePayload(accessToken)?["https://api.openai.com/profile"] as? [String: Any]
        return (profile?["email"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
}
