import Foundation

struct OAuthConfig {
    let providerId: String
    let authorizeURL: URL
    let tokenURL: URL
    let clientId: String
    let scopes: [String]
    let redirectURI: String
}
