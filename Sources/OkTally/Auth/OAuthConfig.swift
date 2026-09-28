import Foundation

struct OAuthConfig {
    let providerId: String
    let authorizeURL: URL
    let tokenURL: URL
    let clientId: String
    let scopes: [String]
    let redirectURI: String

    /// Fixed local port the loopback callback server must bind to, when the provider's
    /// OAuth app has a pre-registered `redirect_uri` (most providers reject any
    /// `redirect_uri` other than exactly what's registered — an ephemeral port breaks
    /// login). `nil` means "no fixed port known/needed" and the loopback server falls
    /// back to an OS-assigned ephemeral port (used by tests and providers without a
    /// confirmed registered port).
    var redirectPort: Int? = nil

    /// Secret do client, para provedores cujo token endpoint o exige mesmo em app
    /// instalado (a Google, no login do Antigravity). Em app instalado ele é público por
    /// definição (RFC 8252 §8.5) — não autentica nada sozinho. `nil` = não enviado, e o
    /// corpo das requisições fica exatamente como era.
    var clientSecret: String? = nil

    /// Parâmetros extras do authorize (ex.: `access_type=offline`, `prompt=consent` na
    /// Google, sem os quais não vem refresh token).
    var additionalAuthorizeParameters: [String: String] = [:]

    /// A mesma config com outra chave de armazenamento: o `providerId` aqui é onde o
    /// token mora no Keychain (e a chave do single-flight de refresh), então cada conta
    /// extra usa o próprio id. Client, escopos e redirect continuam os do tipo.
    func forInstance(_ instanceId: String) -> OAuthConfig {
        with(providerId: instanceId, redirectURI: redirectURI)
    }

    /// Cópia com `providerId`/`redirectURI` trocados, preservando TODOS os outros campos —
    /// reconstruir a config à mão em cada lugar é o que faria um campo novo sumir calado.
    func with(providerId: String, redirectURI: String) -> OAuthConfig {
        var copy = OAuthConfig(
            providerId: providerId, authorizeURL: authorizeURL, tokenURL: tokenURL,
            clientId: clientId, scopes: scopes, redirectURI: redirectURI
        )
        copy.redirectPort = redirectPort
        copy.clientSecret = clientSecret
        copy.additionalAuthorizeParameters = additionalAuthorizeParameters
        return copy
    }
}
