// Sources/OkTally/Plugins/Antigravity/AntigravityOAuth.swift
import Foundation

/// Tudo o que identifica o Antigravity perante a Google: client, endpoints e a config do
/// login próprio do OkTally (contas extras). Mora aqui, num lugar só, para o secret não
/// se espalhar pelo código.
enum AntigravityOAuth {
    // Credenciais OAuth do app instalado — as MESMAS que a Google publica em texto puro
    // no repositório open-source do gemini-cli e que o IDE Antigravity embute. Em apps
    // instalados o "secret" é público por definição (RFC 8252 §8.5): ele não autentica
    // nada sozinho, só identifica o client; o que autentica é o refresh token do dono
    // (lido do IDE na conta legada; obtido pelo login próprio nas extras). O secret
    // scanning do GitHub marca isso como falso positivo — o push exige o unblock de uma
    // vez pelo dono do repositório.
    static let clientId = "1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com"
    static let clientSecret = "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"
    static let userAgent = "antigravity/1.11.3 Darwin/arm64"
    static let summaryURL = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary")!
    static let userInfoURL = URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!

    /// Login Google próprio (contas extras). Conferido ao vivo em 2026-09-28
    /// (docs/superpowers/research/multi-account-antigravity.md): o client aceita redirect
    /// loopback em QUALQUER porta, então a porta é efêmera (`redirectPort: nil`) — assim
    /// não disputa a 51121 com o próprio IDE; o token endpoint exige o secret.
    /// `access_type=offline` + `prompt=consent` garantem o refresh token; `openid` traz o
    /// `id_token` com o e-mail.
    static let config: OAuthConfig = {
        var config = OAuthConfig(
            providerId: AccountKind.antigravity.rawValue,
            authorizeURL: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
            tokenURL: URL(string: "https://oauth2.googleapis.com/token")!,
            clientId: clientId,
            scopes: [
                "openid",
                "https://www.googleapis.com/auth/cloud-platform",
                "https://www.googleapis.com/auth/userinfo.email",
                "https://www.googleapis.com/auth/userinfo.profile",
                "https://www.googleapis.com/auth/cclog",
                "https://www.googleapis.com/auth/experimentsandconfigs"
            ],
            redirectURI: ""
        )
        config.clientSecret = clientSecret
        config.additionalAuthorizeParameters = ["access_type": "offline", "prompt": "consent"]
        return config
    }()

    /// Fallback do e-mail quando o token não trouxe `id_token`.
    static func fetchUserInfoEmail(accessToken: String, session: URLSession = .shared) async -> String? {
        var request = URLRequest(url: userInfoURL)
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return email(fromUserInfo: data)
    }

    static func email(fromUserInfo data: Data) -> String? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let email = json["email"] as? String, !email.isEmpty else { return nil }
        return email
    }
}
