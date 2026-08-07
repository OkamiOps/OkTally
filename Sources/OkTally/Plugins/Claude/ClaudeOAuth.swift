// Sources/OkTally/Plugins/Claude/ClaudeOAuth.swift
import Foundation

enum ClaudeOAuth {
    // NOTE: community-documented values (cedws gist et al.) — confirm against a current
    // source or traffic capture before first release; wrong values fail loudly at login.
    static let config = OAuthConfig(
        providerId: "claude",
        authorizeURL: URL(string: "https://claude.ai/oauth/authorize")!,
        tokenURL: URL(string: "https://console.anthropic.com/v1/oauth/token")!,
        clientId: "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
        scopes: ["org:create_api_key", "user:profile", "user:inference"],
        redirectURI: "http://127.0.0.1:0/callback"
    )
}
