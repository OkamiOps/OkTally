import XCTest
@testable import OkTally

final class OAuthManagerTests: XCTestCase {
    private let config = OAuthConfig(
        providerId: "codex",
        authorizeURL: URL(string: "https://auth.example.com/authorize")!,
        tokenURL: URL(string: "https://auth.example.com/oauth/token")!,
        clientId: "client123",
        scopes: ["openid"],
        redirectURI: "http://127.0.0.1:0/callback"
    )

    private func makeSession() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: cfg)
    }

    func test_validAccessToken_returnsStoredTokenWhenNotExpired() async throws {
        let store = InMemoryTokenStore()
        try store.save(OAuthToken(accessToken: "still-good", refreshToken: "rt", expiresAt: Date().addingTimeInterval(3600), extra: [:]), providerId: "codex")
        let manager = OAuthManager(store: store, session: makeSession())

        let token = try await manager.validAccessToken(providerId: "codex", config: config)

        XCTAssertEqual(token, "still-good")
    }

    func test_validAccessToken_refreshesWhenExpired() async throws {
        let data = try Data(contentsOf: Bundle.module.url(forResource: "oauth_token_response", withExtension: "json", subdirectory: "Fixtures")!)
        URLProtocolStub.stubResponses[config.tokenURL] = (data, 200)
        let store = InMemoryTokenStore()
        try store.save(OAuthToken(accessToken: "expired", refreshToken: "rt", expiresAt: Date().addingTimeInterval(-10), extra: [:]), providerId: "codex")
        let manager = OAuthManager(store: store, session: makeSession())

        let token = try await manager.validAccessToken(providerId: "codex", config: config)

        XCTAssertEqual(token, "new-access")
        XCTAssertEqual(store.load(providerId: "codex")?.refreshToken, "new-refresh")
    }

    func test_refresh_withoutRefreshToken_throws() async {
        let store = InMemoryTokenStore()
        try? store.save(OAuthToken(accessToken: "at", refreshToken: nil, expiresAt: Date().addingTimeInterval(-10), extra: [:]), providerId: "codex")
        let manager = OAuthManager(store: store, session: makeSession())

        do {
            _ = try await manager.refresh(providerId: "codex", config: config)
            XCTFail("expected throw")
        } catch OAuthError.noRefreshToken {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func test_exchangeCode_storesTokenWithExpiry() async throws {
        let data = try Data(contentsOf: Bundle.module.url(forResource: "oauth_token_response", withExtension: "json", subdirectory: "Fixtures")!)
        URLProtocolStub.stubResponses[config.tokenURL] = (data, 200)
        let store = InMemoryTokenStore()
        let fixedNow = Date(timeIntervalSince1970: 1_000_000)
        let manager = OAuthManager(store: store, session: makeSession(), now: { fixedNow })

        let token = try await manager.exchangeCode("authcode", verifier: "verifier", config: config)

        XCTAssertEqual(token.accessToken, "new-access")
        XCTAssertEqual(token.expiresAt, fixedNow.addingTimeInterval(3600))
        XCTAssertEqual(store.load(providerId: "codex")?.accessToken, "new-access")
    }

    /// CRITICAL 1 regression: the `id_token` a token endpoint returns alongside the
    /// access token is a JWT carrying OpenAI's `chatgpt_account_id` claim. Without
    /// decoding it, `extra["account_id"]` is never populated and the `ChatGPT-Account-Id`
    /// header never gets sent to Codex's usage endpoint. This builds a synthetic
    /// (unsigned, made-up) JWT locally — never a real token — to verify the decode path.
    func test_exchangeCode_withIdTokenClaim_populatesAccountIdInExtra() async throws {
        let syntheticIdToken = Self.makeSyntheticJWT(payload: [
            "sub": "user_123",
            "https://api.openai.com/auth": ["chatgpt_account_id": "acc-from-jwt"]
        ])
        let responseJSON: [String: Any] = [
            "access_token": "new-access",
            "refresh_token": "new-refresh",
            "expires_in": 3600,
            "id_token": syntheticIdToken
        ]
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        URLProtocolStub.stubResponses[config.tokenURL] = (data, 200)
        let store = InMemoryTokenStore()
        let manager = OAuthManager(store: store, session: makeSession())

        let token = try await manager.exchangeCode("authcode", verifier: "verifier", config: config)

        XCTAssertEqual(token.extra["account_id"], "acc-from-jwt")
        XCTAssertEqual(store.load(providerId: "codex")?.extra["account_id"], "acc-from-jwt")
    }

    func test_exchangeCode_withMalformedIdToken_doesNotThrow() async throws {
        let responseJSON: [String: Any] = [
            "access_token": "new-access",
            "expires_in": 3600,
            "id_token": "not-a-jwt"
        ]
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        URLProtocolStub.stubResponses[config.tokenURL] = (data, 200)
        let store = InMemoryTokenStore()
        let manager = OAuthManager(store: store, session: makeSession())

        let token = try await manager.exchangeCode("authcode", verifier: "verifier", config: config)

        XCTAssertEqual(token.accessToken, "new-access")
        XCTAssertNil(token.extra["account_id"])
    }

    /// CRITICAL 3 regression: two overlapping calls to `validAccessToken` for the same
    /// expired token must not each fire an independent refresh request — the second
    /// refresh would consume an already-rotated refresh token and could clobber the
    /// Keychain with an invalid pair. Asserts the token endpoint was hit exactly once.
    func test_validAccessToken_concurrentCalls_refreshTokenEndpointCalledOnce() async throws {
        URLProtocolStub.resetRequestCounts()
        let data = try Data(contentsOf: Bundle.module.url(forResource: "oauth_token_response", withExtension: "json", subdirectory: "Fixtures")!)
        URLProtocolStub.stubResponses[config.tokenURL] = (data, 200)
        let store = InMemoryTokenStore()
        try store.save(OAuthToken(accessToken: "expired", refreshToken: "rt", expiresAt: Date().addingTimeInterval(-10), extra: [:]), providerId: "codex")
        let manager = OAuthManager(store: store, session: makeSession())

        async let first = manager.validAccessToken(providerId: "codex", config: config)
        async let second = manager.validAccessToken(providerId: "codex", config: config)
        let (tokenA, tokenB) = try await (first, second)

        XCTAssertEqual(tokenA, "new-access")
        XCTAssertEqual(tokenB, "new-access")
        XCTAssertEqual(URLProtocolStub.requestCount(for: config.tokenURL), 1)
    }

    private static func makeSyntheticJWT(payload: [String: Any]) -> String {
        let header = ["alg": "none", "typ": "JWT"]
        let headerData = try! JSONSerialization.data(withJSONObject: header)
        let payloadData = try! JSONSerialization.data(withJSONObject: payload)
        func base64url(_ data: Data) -> String {
            data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return "\(base64url(headerData)).\(base64url(payloadData)).synthetic-unsigned"
    }
}
