import Foundation
import AppKit

final class BrowserOAuthFlow {
    private let manager: OAuthManaging
    private let loginTimeoutNanoseconds: UInt64

    init(manager: OAuthManaging, loginTimeoutNanoseconds: UInt64 = 300 * 1_000_000_000) {
        self.manager = manager
        self.loginTimeoutNanoseconds = loginTimeoutNanoseconds
    }

    func login(config: OAuthConfig) async throws -> OAuthToken {
        let verifier = PKCE.makeVerifier()
        let challenge = PKCE.challenge(for: verifier)
        let state = PKCE.makeVerifier()
        let server = LoopbackCallbackServer()
        let port = try server.start(port: config.redirectPort)
        defer { server.stop() }

        // When the provider registered a fixed port, its OAuth app also registered an exact
        // redirect_uri (host + path) — using anything else returns an "invalid authorize
        // request". Send that registered URI verbatim (e.g. Codex's
        // http://localhost:1455/auth/callback). Only the no-fixed-port case builds an
        // ephemeral loopback URI.
        let redirect = config.redirectPort != nil ? config.redirectURI : "http://127.0.0.1:\(port)/callback"
        let authorizeURL = Self.authorizeURL(config: config, redirect: redirect, challenge: challenge, state: state)

        let resumeGuard = SingleResume()

        let code: String = try await withCheckedThrowingContinuation { continuation in
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: loginTimeoutNanoseconds)
                resumeGuard.fire { continuation.resume(throwing: OAuthError.loginTimeout) }
            }

            server.onCallback = { path in
                resumeGuard.fire {
                    timeoutTask.cancel()
                    if let code = PKCE.parseCode(fromCallbackPath: path, expectedState: state) {
                        continuation.resume(returning: code)
                    } else {
                        continuation.resume(throwing: OAuthError.tokenExchangeFailed(nil))
                    }
                }
            }
            NSWorkspace.shared.open(authorizeURL)
        }

        return try await manager.exchangeCode(code, verifier: verifier,
                                              config: Self.redirectConfig(from: config, redirect: redirect))
    }

    /// URL do authorize: os parâmetros padrão do PKCE mais os extras do provedor. O
    /// secret NUNCA vai aqui — só no corpo do POST ao token endpoint.
    static func authorizeURL(config: OAuthConfig, redirect: String, challenge: String, state: String) -> URL {
        var comps = URLComponents(url: config.authorizeURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: config.clientId),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "scope", value: config.scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state)
        ] + config.additionalAuthorizeParameters.sorted { $0.key < $1.key }.map { .init(name: $0.key, value: $0.value) }
        return comps.url!
    }

    /// A config da troca do código, com o redirect efetivamente usado. Antes era
    /// reconstruída à mão aqui e perderia calada qualquer campo novo (secret, extras).
    static func redirectConfig(from config: OAuthConfig, redirect: String) -> OAuthConfig {
        config.with(providerId: config.providerId, redirectURI: redirect)
    }
}
