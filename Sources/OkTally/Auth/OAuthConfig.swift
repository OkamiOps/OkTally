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

    /// A mesma config com outra chave de armazenamento: o `providerId` aqui é onde o
    /// token mora no Keychain (e a chave do single-flight de refresh), então cada conta
    /// extra usa o próprio id. Client, escopos e redirect continuam os do tipo.
    func forInstance(_ instanceId: String) -> OAuthConfig {
        var copy = OAuthConfig(
            providerId: instanceId, authorizeURL: authorizeURL, tokenURL: tokenURL,
            clientId: clientId, scopes: scopes, redirectURI: redirectURI
        )
        copy.redirectPort = redirectPort
        return copy
    }
}
