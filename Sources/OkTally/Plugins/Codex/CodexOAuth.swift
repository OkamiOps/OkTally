// Sources/OkTally/Plugins/Codex/CodexOAuth.swift
import Foundation

enum CodexOAuth {
    static let config = OAuthConfig(
        providerId: "codex",
        authorizeURL: URL(string: "https://auth.openai.com/oauth/authorize")!,
        tokenURL: URL(string: "https://auth.openai.com/oauth/token")!,
        clientId: "app_EMoamEEZ73f0CkXaXp7hrann",
        scopes: ["openid", "profile", "email", "offline_access"],
        redirectURI: "http://127.0.0.1:0/callback"
    )
}
