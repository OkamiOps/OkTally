import XCTest
@testable import OkTally

final class AntigravityOAuthTests: XCTestCase {
    func test_config_isGoogleWithSecretOfflineConsentAndEphemeralLoopback() {
        let c = AntigravityOAuth.config
        XCTAssertEqual(c.providerId, "antigravity")
        XCTAssertEqual(c.authorizeURL.absoluteString, "https://accounts.google.com/o/oauth2/v2/auth")
        XCTAssertEqual(c.tokenURL.absoluteString, "https://oauth2.googleapis.com/token")
        XCTAssertNotNil(c.clientSecret)
        XCTAssertEqual(c.additionalAuthorizeParameters["access_type"], "offline")
        XCTAssertEqual(c.additionalAuthorizeParameters["prompt"], "consent")
        // Task 5.0: qualquer porta loopback é aceita — efêmera evita colidir com o IDE.
        XCTAssertNil(c.redirectPort)
        XCTAssertTrue(c.scopes.contains("https://www.googleapis.com/auth/cloud-platform"))
        XCTAssertTrue(c.scopes.contains("https://www.googleapis.com/auth/userinfo.email"))
        XCTAssertTrue(c.scopes.contains("openid"))
    }

    func test_forInstance_keepsSecret() {
        let c = AntigravityOAuth.config.forInstance("antigravity#abc123")
        XCTAssertEqual(c.providerId, "antigravity#abc123")
        XCTAssertEqual(c.clientSecret, AntigravityOAuth.config.clientSecret)
    }

    func test_userInfoEmail_parsesGoogleResponse() {
        XCTAssertEqual(AntigravityOAuth.email(fromUserInfo: Data(#"{"id":"1","email":"g@gmail.test","verified_email":true}"#.utf8)), "g@gmail.test")
        XCTAssertNil(AntigravityOAuth.email(fromUserInfo: Data("{}".utf8)))
    }

    func test_resolver_extraAntigravity_fallsBackToUserInfo() async throws {
        let store = InMemoryTokenStore()
        try store.save(OAuthToken(accessToken: "t", refreshToken: "r", expiresAt: nil, extra: [:]), providerId: "antigravity#abc123")
        let resolver = AccountEmailResolver(tokenStore: store, oauthManager: FakeOAuthManaging(), claudeProfile: nil,
                                            cursorEmail: { nil }, antigravityEmail: { nil },
                                            googleUserInfoEmail: { _ in "u@g.test" })
        let identity = await resolver.resolve(AccountInstance(id: "antigravity#abc123", kind: .antigravity))
        XCTAssertEqual(identity.email, "u@g.test")
        XCTAssertEqual(identity.identityKey, "u@g.test")
    }

    func test_factory_extraAntigravityIsAppOwned() async throws {
        let tokens = InMemoryTokenStore()
        try tokens.save(OAuthToken(accessToken: "t", refreshToken: "r", expiresAt: nil, extra: [:]), providerId: "antigravity#abc123")
        let preferences = PreferencesStore(store: FakeKeyValueStore(), secretStore: FakeSecretStore())
        let factory = ProviderFactory(dependencies: .testing(tokenStore: tokens, preferences: preferences))
        let extra = AccountInstance(id: "antigravity#abc123", kind: .antigravity)
        let provider = factory.providers(for: extra, all: [extra])[0]
        let authenticated = await provider.isAuthenticated()
        XCTAssertTrue(authenticated)
    }
}
