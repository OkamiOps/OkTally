import XCTest
@testable import OkTally

final class FakeClaudeUsageFetching: ClaudeUsageFetching {
    var responseToReturn: ClaudeUsageResponse!
    func fetchUsage(accessToken: String) async throws -> ClaudeUsageResponse { responseToReturn }
}

final class ClaudeUsageProviderTests: XCTestCase {
    private func makeProvider(fetcher: FakeClaudeUsageFetching, tokenInStore: Bool = true) throws -> ClaudeUsageProvider {
        let store = InMemoryTokenStore()
        if tokenInStore {
            try store.save(OAuthToken(accessToken: "tok", refreshToken: "rt", expiresAt: nil, extra: [:]), providerId: "claude")
        }
        return ClaudeUsageProvider(oauthManager: FakeOAuthManaging(), tokenStore: store, apiClient: fetcher, legacyCredentialProvider: nil)
    }

    func test_fetchSnapshot_mapsThreeWindows() async throws {
        let fetcher = FakeClaudeUsageFetching()
        fetcher.responseToReturn = ClaudeUsageResponse(
            fiveHour: ClaudeUsageWindow(utilization: 42.5, resetsAt: Date(timeIntervalSince1970: 2_000_000)),
            sevenDay: ClaudeUsageWindow(utilization: 61.0, resetsAt: Date(timeIntervalSince1970: 2_500_000)),
            sevenDayOpus: ClaudeUsageWindow(utilization: 15.0, resetsAt: Date(timeIntervalSince1970: 2_500_000))
        )
        let provider = try makeProvider(fetcher: fetcher)

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.providerId, "claude")
        XCTAssertEqual(snapshot.quotas.count, 3)
        let fiveHour = try XCTUnwrap(snapshot.quotas.first { $0.label == "5h" })
        let weekly = try XCTUnwrap(snapshot.quotas.first { $0.label == "weekly" })
        let weeklyOpus = try XCTUnwrap(snapshot.quotas.first { $0.label == "weekly-opus" })
        XCTAssertEqual(fiveHour.shape.usedPercent, 42.5)
        XCTAssertNil(fiveHour.renewalCadence)
        XCTAssertEqual(weekly.shape.usedPercent, 61.0)
        XCTAssertEqual(weekly.renewalCadence, .weekly)
        XCTAssertEqual(weeklyOpus.shape.usedPercent, 15.0)
        XCTAssertEqual(weeklyOpus.renewalCadence, .weekly)
    }

    func test_fetchSnapshot_withoutOpusWindow_returnsTwoWindows() async throws {
        let fetcher = FakeClaudeUsageFetching()
        fetcher.responseToReturn = ClaudeUsageResponse(
            fiveHour: ClaudeUsageWindow(utilization: 10, resetsAt: Date()),
            sevenDay: ClaudeUsageWindow(utilization: 20, resetsAt: Date()),
            sevenDayOpus: nil
        )
        let provider = try makeProvider(fetcher: fetcher)

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.quotas.count, 2)
    }

    func test_isAuthenticated_falseWhenNoCredentials() async throws {
        let provider = try makeProvider(fetcher: FakeClaudeUsageFetching(), tokenInStore: false)

        let isAuthenticated = await provider.isAuthenticated()

        XCTAssertFalse(isAuthenticated)
    }

    func test_apiClient_decodesFixture() async throws {
        let fixtureURL = Bundle.module.url(forResource: "claude_usage_response", withExtension: "json", subdirectory: "Fixtures")!
        let data = try Data(contentsOf: fixtureURL)
        URLProtocolStub.stubResponses[URL(string: "https://api.anthropic.com/api/oauth/usage")!] = (data, 200)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: config)

        let client = ClaudeUsageAPIClient(session: session)
        let response = try await client.fetchUsage(accessToken: "tok")

        XCTAssertEqual(response.fiveHour.utilization, 42.5)
        // Idle window: the live API reports `resets_at: null` — must decode, not fail.
        XCTAssertEqual(response.sevenDayOpus?.utilization, 15.0)
        XCTAssertNil(response.sevenDayOpus?.resetsAt)
    }

    func test_fetchSnapshot_windowWithNilReset_stillProducesQuota() async throws {
        let fetcher = FakeClaudeUsageFetching()
        fetcher.responseToReturn = ClaudeUsageResponse(
            fiveHour: ClaudeUsageWindow(utilization: 0, resetsAt: nil),
            sevenDay: ClaudeUsageWindow(utilization: 61.0, resetsAt: Date(timeIntervalSince1970: 2_500_000)),
            sevenDayOpus: nil
        )
        let provider = try makeProvider(fetcher: fetcher)

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.quotas.count, 2)
        let fiveHour = try XCTUnwrap(snapshot.quotas.first { $0.label == "5h" })
        XCTAssertEqual(fiveHour.shape.usedPercent, 0)
        // Synthetic reset anchored at fetch time: no countdown is rendered for it.
        XCTAssertNil(QuotaPresentation.resetText(fiveHour.shape))
    }

    func test_importLegacyCredentials_savesTokenWhenLegacyExists() throws {
        let keychain = FakeCredentialStoreReading()
        keychain.dataToReturn = """
        {"claudeAiOauth":{"accessToken":"legacy-at","refreshToken":"legacy-rt","expiresAt":1900000000000}}
        """.data(using: .utf8)
        let legacy = ClaudeCredentialProvider(keychainReader: keychain, fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let store = InMemoryTokenStore()
        let provider = ClaudeUsageProvider(oauthManager: FakeOAuthManaging(), tokenStore: store, apiClient: FakeClaudeUsageFetching(), legacyCredentialProvider: legacy)

        XCTAssertTrue(provider.importLegacyCredentialsIfAvailable())
        XCTAssertEqual(store.load(providerId: "claude")?.accessToken, "legacy-at")
    }

    func test_importLegacyCredentials_falseWhenNoLegacy() {
        let keychain = FakeCredentialStoreReading()
        let legacy = ClaudeCredentialProvider(keychainReader: keychain, fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let provider = ClaudeUsageProvider(oauthManager: FakeOAuthManaging(), tokenStore: InMemoryTokenStore(), apiClient: FakeClaudeUsageFetching(), legacyCredentialProvider: legacy)

        XCTAssertFalse(provider.importLegacyCredentialsIfAvailable())
    }

    func test_importLegacyCredentials_skipsWhenTokenAlreadyPresent() throws {
        let store = InMemoryTokenStore()
        try store.save(OAuthToken(accessToken: "already", refreshToken: nil, expiresAt: nil, extra: [:]), providerId: "claude")
        let keychain = FakeCredentialStoreReading()
        keychain.dataToReturn = "{\"accessToken\":\"legacy\"}".data(using: .utf8)
        let legacy = ClaudeCredentialProvider(keychainReader: keychain, fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let provider = ClaudeUsageProvider(oauthManager: FakeOAuthManaging(), tokenStore: store, apiClient: FakeClaudeUsageFetching(), legacyCredentialProvider: legacy)

        XCTAssertFalse(provider.importLegacyCredentialsIfAvailable())
        XCTAssertEqual(store.load(providerId: "claude")?.accessToken, "already")
    }
}
