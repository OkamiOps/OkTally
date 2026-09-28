// Tests/OkTallyTests/AntigravityUsageProviderTests.swift
import XCTest
@testable import OkTally

final class AntigravityTokenReaderTests: XCTestCase {
    func test_decodeTokens_fromSyntheticBlobInIDEFormat() {
        let blob = AntigravityTokenReader.encodeTestBlob(accessToken: "fake-access-token", refreshToken: "fake-refresh-token")
        let tokens = AntigravityTokenReader.decodeTokens(fromBase64: blob)
        XCTAssertEqual(tokens, AntigravityTokens(accessToken: "fake-access-token", refreshToken: "fake-refresh-token"))
    }

    func test_decodeTokens_garbage_returnsNil() {
        XCTAssertNil(AntigravityTokenReader.decodeTokens(fromBase64: "não-é-base64!!"))
        XCTAssertNil(AntigravityTokenReader.decodeTokens(fromBase64: Data("random".utf8).base64EncodedString()))
    }

    func test_readTokens_missingDatabase_returnsNil() {
        let reader = AntigravityTokenReader(dbPath: "/nonexistent/state.vscdb")
        XCTAssertNil(reader.readTokens())
    }
}

final class AntigravityUsageProviderTests: XCTestCase {
    /// Forma real capturada ao vivo em 2026-08-12.
    private let summaryJSON = """
    {
        "groups": [
            {
                "displayName": "Gemini Models",
                "buckets": [
                    {"bucketId": "gemini-weekly", "displayName": "Weekly Limit", "window": "weekly", "resetTime": "2026-08-19T10:51:46Z", "remainingFraction": 0.4},
                    {"bucketId": "gemini-5h", "displayName": "Five Hour Limit", "window": "5h", "resetTime": "2026-08-12T15:51:46Z", "remainingFraction": 1}
                ]
            },
            {
                "displayName": "Claude and GPT models",
                "buckets": [
                    {"bucketId": "3p-weekly", "displayName": "Weekly Limit", "window": "weekly", "resetTime": "2026-08-19T10:51:46Z", "remainingFraction": 0.93}
                ]
            }
        ]
    }
    """

    func test_windows_mapsGroupsAndBuckets() throws {
        let now = Date()
        let windows = AntigravityUsageProvider.windows(fromSummary: Data(summaryJSON.utf8), now: now)

        XCTAssertEqual(windows.count, 3)
        let byLabel = Dictionary(uniqueKeysWithValues: windows.map { ($0.label, $0) })

        guard case .rollingWindow(let used, let limit, _, let resetAt) = byLabel["Gemini (weekly)"]?.shape else {
            return XCTFail("expected Gemini weekly window")
        }
        XCTAssertEqual(used, 60, accuracy: 0.0001)
        XCTAssertEqual(limit, 100)
        XCTAssertEqual(resetAt, ISO8601DateFormatter().date(from: "2026-08-19T10:51:46Z"))
        XCTAssertEqual(byLabel["Gemini (weekly)"]?.renewalCadence, .weekly)

        XCTAssertEqual(byLabel["Gemini (5h)"]?.shape.usedPercent ?? -1, 0, accuracy: 0.0001)
        XCTAssertNil(byLabel["Gemini (5h)"]?.renewalCadence)
        XCTAssertEqual(byLabel["Claude/GPT (weekly)"]?.shape.usedPercent ?? -1, 7, accuracy: 0.0001)
        XCTAssertEqual(byLabel["Claude/GPT (weekly)"]?.renewalCadence, .weekly)
    }

    func test_windows_toleratesMissingFractionAndUnknownGroups() {
        let json = """
        {"groups": [
            {"displayName": "Mystery Models", "buckets": [{"window": "5h", "remainingFraction": 0.5}]},
            {"displayName": "Gemini Models", "buckets": [{"window": "5h"}]}
        ]}
        """
        XCTAssertTrue(AntigravityUsageProvider.windows(fromSummary: Data(json.utf8), now: Date()).isEmpty)
        XCTAssertTrue(AntigravityUsageProvider.windows(fromSummary: Data("{}".utf8), now: Date()).isEmpty)
    }

    func test_classification() {
        XCTAssertEqual(ProviderErrorPresentation.classify(AntigravityError.notDetected), .notConfigured)
        XCTAssertEqual(ProviderErrorPresentation.classify(AntigravityError.tokenRejected), .needsReauth)
        XCTAssertEqual(ProviderErrorPresentation.classify(AntigravityError.badResponse(500)), .error)
    }

    // MARK: - Conta própria do OkTally (login Google)

    private final class FixedTokenReader: AntigravityTokenReading {
        let tokens: AntigravityTokens?
        init(_ tokens: AntigravityTokens?) { self.tokens = tokens }
        func readTokens() -> AntigravityTokens? { tokens }
    }

    private func makeSession() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: cfg)
    }

    func test_appOwnedInstance_usesOAuthManagerTokenNotIDE() async throws {
        let store = InMemoryTokenStore()
        try store.save(OAuthToken(accessToken: "app-tok", refreshToken: "rt", expiresAt: .distantFuture, extra: [:]),
                       providerId: "antigravity#abc123")
        URLProtocolStub.stubResponses[AntigravityOAuth.summaryURL] = (Data(summaryJSON.utf8), 200)
        let oauth = FakeOAuthManaging(); oauth.accessTokenToReturn = "app-tok"
        let provider = AntigravityUsageProvider(instanceId: "antigravity#abc123", oauthManager: oauth,
                                                tokenStore: store, session: makeSession())

        let authenticated = await provider.isAuthenticated()
        XCTAssertTrue(authenticated)
        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.providerId, "antigravity#abc123")
        XCTAssertEqual(snapshot.quotas.count, 3)
        XCTAssertEqual(URLProtocolStub.lastAuthorization(for: AntigravityOAuth.summaryURL), "Bearer app-tok")
        XCTAssertEqual(oauth.lastConfig?.providerId, "antigravity#abc123")
        XCTAssertEqual(oauth.lastConfig?.clientSecret, AntigravityOAuth.config.clientSecret)
    }

    func test_appOwnedInstance_withoutToken_isNotAuthenticated() async {
        let provider = AntigravityUsageProvider(instanceId: "antigravity#abc123", oauthManager: FakeOAuthManaging(),
                                                tokenStore: InMemoryTokenStore())
        let authenticated = await provider.isAuthenticated()
        XCTAssertFalse(authenticated)
    }

    func test_legacyInstance_stillReadsIDE() async throws {
        let ideTokens = AntigravityTokens(accessToken: "ide-access", refreshToken: "ide-refresh")
        URLProtocolStub.stubResponses[AntigravityOAuth.config.tokenURL] = (Data(#"{"access_token":"ide-fresh","expires_in":3600}"#.utf8), 200)
        URLProtocolStub.stubResponses[AntigravityOAuth.summaryURL] = (Data(summaryJSON.utf8), 200)
        let provider = AntigravityUsageProvider(tokenReader: FixedTokenReader(ideTokens), session: makeSession())

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.providerId, "antigravity")
        XCTAssertEqual(URLProtocolStub.lastAuthorization(for: AntigravityOAuth.summaryURL), "Bearer ide-fresh")
        // O refresh legado codifica os valores com `.alphanumerics`; basta ver as chaves.
        let body = URLProtocolStub.lastBody(for: AntigravityOAuth.config.tokenURL) ?? ""
        XCTAssertTrue(body.contains("refresh_token="))
        XCTAssertTrue(body.contains("client_secret="))
    }
}
