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
}
