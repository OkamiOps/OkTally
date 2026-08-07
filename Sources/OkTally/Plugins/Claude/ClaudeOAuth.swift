// Sources/OkTally/Plugins/Claude/ClaudeOAuth.swift
import Foundation

enum ClaudeOAuth {
    // NOTE: community-documented values (cedws gist et al.) — confirm against a current
    // source or traffic capture before first release; wrong values fail loudly at login.
    //
    // TODO: confirm porta registrada do redirect_uri da Anthropic. Most OAuth providers
    // (including OpenAI's Codex app — see CodexOAuth) reject any `redirect_uri` other
    // than exactly what's pre-registered for the client id, which means an ephemeral
    // loopback port almost certainly breaks this login too. We did not find a confirmed
    // fixed port for Anthropic's public client in research, so `redirectPort` is left
    // `nil` (ephemeral) rather than guessing a wrong number that would fail silently in a
    // different way. Capture real traffic from `claude login` (or the Claude Code CLI) to
    // find the actual registered port/path, then set `redirectPort` here the same way
    // `CodexOAuth` does.
    static let config = OAuthConfig(
        providerId: "claude",
        authorizeURL: URL(string: "https://claude.ai/oauth/authorize")!,
        tokenURL: URL(string: "https://console.anthropic.com/v1/oauth/token")!,
        clientId: "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
        scopes: ["org:create_api_key", "user:profile", "user:inference"],
        redirectURI: "http://127.0.0.1:0/callback",
        redirectPort: nil
    )
}
