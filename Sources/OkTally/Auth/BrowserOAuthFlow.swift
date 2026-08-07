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
        let port = try server.start()
        defer { server.stop() }

        let redirect = "http://127.0.0.1:\(port)/callback"
        var comps = URLComponents(url: config.authorizeURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: config.clientId),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "scope", value: config.scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state)
        ]

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
            NSWorkspace.shared.open(comps.url!)
        }

        let redirectConfig = OAuthConfig(
            providerId: config.providerId, authorizeURL: config.authorizeURL,
            tokenURL: config.tokenURL, clientId: config.clientId,
            scopes: config.scopes, redirectURI: redirect
        )
        return try await manager.exchangeCode(code, verifier: verifier, config: redirectConfig)
    }
}
