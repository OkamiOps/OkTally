// Sources/OkTally/Plugins/Codex/CodexOAuth.swift
import Foundation

enum CodexOAuth {
    // The Codex CLI registers a FIXED redirect port (1455) with its OAuth app — an
    // ephemeral port is rejected by the authorize endpoint. See LoopbackCallbackServer.
    static let redirectPort = 1455

    static let config = OAuthConfig(
        providerId: "codex",
        authorizeURL: URL(string: "https://auth.openai.com/oauth/authorize")!,
        tokenURL: URL(string: "https://auth.openai.com/oauth/token")!,
        clientId: "app_EMoamEEZ73f0CkXaXp7hrann",
        scopes: ["openid", "profile", "email", "offline_access"],
        // Exact redirect the Codex OAuth app registers — host `localhost` (not 127.0.0.1)
        // and path `/auth/callback` (not `/callback`); any deviation is rejected as an
        // invalid authorize request.
        redirectURI: "http://localhost:\(redirectPort)/auth/callback",
        redirectPort: redirectPort
    )
}
