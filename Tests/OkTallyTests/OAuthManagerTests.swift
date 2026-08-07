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
}
