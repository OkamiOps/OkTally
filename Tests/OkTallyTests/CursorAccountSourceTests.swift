import XCTest
@testable import OkTally

/// Contas extras do Cursor: a sessão vem do Keychain (login próprio), não do IDE, e é
/// dividida entre o Cursor e o GrokBot gêmeo.
final class CursorAccountSourceTests: XCTestCase {
    private func store(expiresAt: Date?) throws -> InMemoryTokenStore {
        let store = InMemoryTokenStore()
        try store.save(OAuthToken(accessToken: "sess", refreshToken: "sess", expiresAt: expiresAt, extra: [:]),
                       providerId: "cursor#abc123")
        return store
    }

    func test_validToken_isRead() throws {
        let source = KeychainCursorTokenSource(instanceId: "cursor#abc123", tokenStore: try store(expiresAt: .distantFuture))
        XCTAssertEqual(source.readAccessToken(), "sess")
        XCTAssertNil(source.readMembershipType())
        XCTAssertTrue(source.hasCredential())
        XCTAssertNil(source.unavailableError())
    }

    func test_expiredToken_isNotReturned_andAsksForReauth() throws {
        let source = KeychainCursorTokenSource(instanceId: "cursor#abc123", tokenStore: try store(expiresAt: Date().addingTimeInterval(-10)))
        XCTAssertNil(source.readAccessToken())
        XCTAssertTrue(source.hasCredential())
        let error = try XCTUnwrap(source.unavailableError())
        XCTAssertEqual(ProviderErrorPresentation.classify(error), .needsReauth)
    }

    func test_noToken_isNotConfigured() {
        let source = KeychainCursorTokenSource(instanceId: "cursor#abc123", tokenStore: InMemoryTokenStore())
        XCTAssertFalse(source.hasCredential())
        XCTAssertNil(source.unavailableError())
    }

    func test_ideReader_hasCredentialFollowsToken() {
        let reader = FakeCursorTokenReading()
        XCTAssertFalse(reader.hasCredential())
        reader.tokenToReturn = "t"
        XCTAssertTrue(reader.hasCredential())
    }

    func test_cursorProvider_expiredSession_isAuthenticatedButFailsAsNeedsReauth() async throws {
        let source = KeychainCursorTokenSource(instanceId: "cursor#abc123", tokenStore: try store(expiresAt: Date().addingTimeInterval(-10)))
        let provider = CursorUsageProvider(instanceId: "cursor#abc123", tokenReader: source, client: FakeCursorUsageFetching())
        let authenticated = await provider.isAuthenticated()
        XCTAssertTrue(authenticated)
        do {
            _ = try await provider.fetchSnapshot()
            XCTFail("expected needsReauth")
        } catch {
            XCTAssertEqual(ProviderErrorPresentation.classify(error), .needsReauth)
        }
    }

    func test_grokBotTwin_usesTheSameSession() async throws {
        let source = KeychainCursorTokenSource(instanceId: "cursor#abc123", tokenStore: try store(expiresAt: .distantFuture))
        let fetcher = FakeGrokBotUsageFetching()
        fetcher.responseToReturn = GrokBotUsageResponse(usagePercent: 3, nextResetTimestampUtc: "2026-08-31T00:31:02.272Z",
                                                        hasNonZeroIncludedLimit: true, hasAvailableUsage: true, grokPlanLabel: "x")
        let twin = GrokBotUsageProvider(instanceId: "cursor-grokbot#abc123", tokenReader: source, client: fetcher)
        _ = try await twin.fetchSnapshot()
        XCTAssertEqual(fetcher.receivedAccessToken, "sess")
    }

    func test_grokBotTwin_expiredSession_needsReauth() async throws {
        let source = KeychainCursorTokenSource(instanceId: "cursor#abc123", tokenStore: try store(expiresAt: Date().addingTimeInterval(-10)))
        let twin = GrokBotUsageProvider(instanceId: "cursor-grokbot#abc123", tokenReader: source, client: FakeGrokBotUsageFetching())
        do {
            _ = try await twin.fetchSnapshot()
            XCTFail("expected needsReauth")
        } catch {
            XCTAssertEqual(ProviderErrorPresentation.classify(error), .needsReauth)
        }
    }

    func test_factory_extraCursorPairReadsTheKeychainSession() async throws {
        let preferences = PreferencesStore(store: FakeKeyValueStore(), secretStore: FakeSecretStore())
        let factory = ProviderFactory(dependencies: .testing(tokenStore: try store(expiresAt: .distantFuture), preferences: preferences))
        let extra = AccountInstance(id: "cursor#abc123", kind: .cursor)
        let providers = factory.providers(for: extra, all: [extra])
        let cursorAuthenticated = await providers[0].isAuthenticated()
        XCTAssertTrue(cursorAuthenticated)
        let other = AccountInstance(id: "cursor#ffffff", kind: .cursor)
        let otherAuthenticated = await factory.providers(for: other, all: [other])[0].isAuthenticated()
        XCTAssertFalse(otherAuthenticated)
    }

    func test_emailParser_readsGetEmailResponse() {
        XCTAssertEqual(CursorAccountAPI.email(fromGetEmail: Data(#"{"email":"c@cursor.test"}"#.utf8)), "c@cursor.test")
        XCTAssertNil(CursorAccountAPI.email(fromGetEmail: Data("{}".utf8)))
    }

    func test_resolver_extraCursor_usesGetEmailWithTheStoredSession() async throws {
        var received: String?
        let resolver = AccountEmailResolver(tokenStore: try store(expiresAt: .distantFuture), oauthManager: FakeOAuthManaging(),
                                            claudeProfile: nil, cursorEmail: { "ide@cursor.test" }, antigravityEmail: { nil },
                                            cursorEmailForToken: { received = $0; return "extra@cursor.test" })
        let identity = await resolver.resolve(AccountInstance(id: "cursor#abc123", kind: .cursor))
        XCTAssertEqual(identity.email, "extra@cursor.test")
        XCTAssertEqual(received, "sess")
        let legacy = await resolver.resolve(AccountInstance(id: "cursor", kind: .cursor))
        XCTAssertEqual(legacy.email, "ide@cursor.test")
    }
}
