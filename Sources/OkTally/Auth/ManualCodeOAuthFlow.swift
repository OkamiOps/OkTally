// Sources/OkTally/Auth/ManualCodeOAuthFlow.swift
import Foundation
import AppKit

/// Held by the UI between opening the browser and the user pasting back the code.
struct ManualCodeSession {
    let verifier: String
    let state: String
    let config: OAuthConfig
}

/// OAuth for providers whose app uses a FIXED hosted redirect that renders a
/// `CODE#STATE` string for the user to copy and paste back (Claude), instead of a
/// loopback callback. Two phases: `begin` opens the browser, `complete` exchanges the
/// pasted code.
final class ManualCodeOAuthFlow {
    private let manager: OAuthManaging

    init(manager: OAuthManaging) {
        self.manager = manager
    }

    @discardableResult
    func begin(config: OAuthConfig) -> ManualCodeSession {
        let verifier = PKCE.makeVerifier()
        let challenge = PKCE.challenge(for: verifier)
        let state = PKCE.makeVerifier()

        var comps = URLComponents(url: config.authorizeURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "code", value: "true"),
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: config.clientId),
            .init(name: "redirect_uri", value: config.redirectURI),
            .init(name: "scope", value: config.scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state)
        ]
        NSWorkspace.shared.open(comps.url!)
        return ManualCodeSession(verifier: verifier, state: state, config: config)
    }

    func complete(pasted: String, session: ManualCodeSession) async throws -> OAuthToken {
        let trimmed = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let code = String(parts[0])
        let returnedState = parts.count > 1 ? String(parts[1]) : session.state
        guard returnedState == session.state else {
            throw OAuthError.tokenExchangeFailed(nil)
        }
        return try await manager.exchangeManualCode(
            code: code, state: returnedState, verifier: session.verifier, config: session.config
        )
    }
}
