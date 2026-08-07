// Sources/OkTally/Plugins/SuperGrok/SuperGrokOAuth.swift
import Foundation

/// xAI's OAuth 2.0 Device Authorization Grant (RFC 8628) endpoints, client id,
/// and scopes for the "Grok Build" / coding-agent product (what SuperGrok's
/// CLI-style OAuth logs into — see docs/superpowers/research/plan2-supergrok.md,
/// "Implementation pin" section, for full sourcing).
///
/// client_id and endpoints are pinned from two independent, working
/// open-source OAuth client implementations that read as production code
/// (not test fixtures), not reverse-engineered or invented by OkTally:
///   - github.com/stnly/pi-grok, oauth.ts:18-28
///   - github.com/BlockedPath/pi-xai-oauth, extensions/xai/constants.ts:3-14
enum SuperGrokOAuth {
    static let providerId = "supergrok"

    static let config = DeviceCodeOAuthConfig(
        providerId: providerId,
        deviceAuthorizationURL: URL(string: "https://auth.x.ai/oauth2/device/code")!,
        tokenURL: URL(string: "https://auth.x.ai/oauth2/token")!,
        clientId: "b1a00492-073a-47ea-816f-4c329264a828",
        scopes: [
            "openid", "profile", "email", "offline_access",
            "grok-cli:access", "api:access",
            "conversations:read", "conversations:write"
        ]
    )

    /// `OAuthManaging.validAccessToken`/`refresh` operate on the shared
    /// `OAuthConfig` shape (used by the authorization-code+PKCE providers).
    /// The device-code login itself doesn't use `authorizeURL`/`redirectURI`,
    /// but the standard `refresh_token` grant xAI uses afterwards does match
    /// `OAuthManager`'s existing refresh flow, so we reuse it rather than
    /// duplicating refresh logic. The unused fields are set to `config`'s own
    /// endpoints as harmless placeholders — they're never sent on a refresh.
    static let refreshConfig = OAuthConfig(
        providerId: providerId,
        authorizeURL: config.deviceAuthorizationURL,
        tokenURL: config.tokenURL,
        clientId: config.clientId,
        scopes: config.scopes,
        redirectURI: ""
    )
}
