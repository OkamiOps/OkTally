// Sources/OkTally/Plugins/Claude/ClaudeOAuth.swift
import Foundation

enum ClaudeOAuth {
    // Claude's OAuth (the same public client the Claude Code CLI uses) does NOT use a
    // loopback redirect. It redirects to a FIXED hosted callback that renders an
    // authorization code in `CODE#STATE` form for the user to copy and paste back —
    // so this provider uses ManualCodeOAuthFlow, not the loopback BrowserOAuthFlow.
    //
    // Values are community/binary-derived (shubcodes gist analysing the CLI binary,
    // cross-checked against maintained open-source implementations). The token-exchange
    // body shape (JSON, with `state`) and the platform.claude.com host are the parts most
    // likely to drift; if login fails at the exchange step, that's the first thing to swap.
    static let config = OAuthConfig(
        providerId: "claude",
        authorizeURL: URL(string: "https://claude.ai/oauth/authorize")!,
        tokenURL: URL(string: "https://platform.claude.com/v1/oauth/token")!,
        clientId: "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
        scopes: ["org:create_api_key", "user:profile", "user:inference"],
        redirectURI: "https://platform.claude.com/oauth/code/callback",
        redirectPort: nil
    )
}
