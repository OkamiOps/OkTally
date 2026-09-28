import XCTest
@testable import OkTally

/// Cada plugin aceita um `instanceId` (padrão = o tipo): o mesmo código serve a conta
/// legada e as extras, cada uma com a própria credencial e o próprio snapshot.
final class PluginInstanceIdTests: XCTestCase {
    // MARK: - OAuth

    func test_claude_extraInstance_usesInstanceIdForTokenAndSnapshot() async throws {
        let store = InMemoryTokenStore()
        try store.save(OAuthToken(accessToken: "tok2", refreshToken: "rt", expiresAt: nil, extra: [:]), providerId: "claude#abc123")
        let fetcher = FakeClaudeUsageFetching()
        fetcher.responseToReturn = ClaudeUsageResponse(
            fiveHour: ClaudeUsageWindow(utilization: 1, resetsAt: Date()),
            sevenDay: ClaudeUsageWindow(utilization: 2, resetsAt: Date()), sevenDayOpus: nil)
        let oauth = FakeOAuthManaging()
        let provider = ClaudeUsageProvider(instanceId: "claude#abc123", oauthManager: oauth,
                                           tokenStore: store, apiClient: fetcher, profileClient: nil,
                                           legacyCredentialProvider: nil)
        XCTAssertEqual(provider.id, "claude#abc123")
        let authenticated = await provider.isAuthenticated()
        XCTAssertTrue(authenticated)
        let snapshot = try await provider.fetchSnapshot()
        XCTAssertEqual(snapshot.providerId, "claude#abc123")
        XCTAssertEqual(oauth.lastProviderId, "claude#abc123")
        XCTAssertEqual(oauth.lastConfig?.providerId, "claude#abc123")
    }

    func test_claude_legacyImport_neverSeedsExtraInstance() {
        let keychain = FakeCredentialStoreReading()
        keychain.dataToReturn = """
        {"claudeAiOauth":{"accessToken":"legacy-at","refreshToken":"legacy-rt","expiresAt":1900000000000}}
        """.data(using: .utf8)
        let legacy = ClaudeCredentialProvider(keychainReader: keychain, fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let store = InMemoryTokenStore()
        let provider = ClaudeUsageProvider(instanceId: "claude#abc123", oauthManager: FakeOAuthManaging(),
                                           tokenStore: store, legacyCredentialProvider: legacy)
        XCTAssertFalse(provider.importLegacyCredentialsIfAvailable())
        XCTAssertNil(store.load(providerId: "claude#abc123"))
    }

    func test_codex_extraInstance_usesOwnTokenAndAccountId() async throws {
        let store = InMemoryTokenStore()
        try store.save(OAuthToken(accessToken: "t", refreshToken: "rt", expiresAt: nil, extra: ["account_id": "acc-2"]), providerId: "codex#abc123")
        try store.save(OAuthToken(accessToken: "t", refreshToken: "rt", expiresAt: nil, extra: ["account_id": "acc-1"]), providerId: "codex")
        let fetcher = FakeCodexUsageFetching()
        fetcher.responseToReturn = CodexUsageResponse(planType: nil, rateLimit: nil)
        let oauth = FakeOAuthManaging()
        let provider = CodexUsageProvider(instanceId: "codex#abc123", oauthManager: oauth, tokenStore: store, apiClient: fetcher)
        let snapshot = try await provider.fetchSnapshot()
        XCTAssertEqual(provider.id, "codex#abc123")
        XCTAssertEqual(snapshot.providerId, "codex#abc123")
        XCTAssertEqual(fetcher.lastAccountId, "acc-2")
        XCTAssertEqual(oauth.lastConfig?.providerId, "codex#abc123")
        XCTAssertEqual(oauth.lastConfig?.clientId, CodexOAuth.config.clientId)
    }

    func test_superGrok_extraInstance_usesInstanceRefreshConfig() async throws {
        let store = InMemoryTokenStore()
        try store.save(OAuthToken(accessToken: "t", refreshToken: "rt", expiresAt: nil, extra: [:]), providerId: "supergrok#abc123")
        let fetcher = FakeSuperGrokUsageFetching()
        fetcher.responseToReturn = SuperGrokUsageSnapshot(creditUsagePercent: 10, resetAt: nil)
        let oauth = FakeOAuthManaging()
        let provider = SuperGrokUsageProvider(instanceId: "supergrok#abc123", oauthManager: oauth, tokenStore: store, apiClient: fetcher)
        let authenticated = await provider.isAuthenticated()
        XCTAssertTrue(authenticated)
        let snapshot = try await provider.fetchSnapshot()
        XCTAssertEqual(snapshot.providerId, "supergrok#abc123")
        XCTAssertEqual(oauth.lastConfig?.providerId, "supergrok#abc123")
    }

    func test_oauthConfig_forInstance_replacesStorageKeyOnly() {
        let c = CodexOAuth.config.forInstance("codex#abc123")
        XCTAssertEqual(c.providerId, "codex#abc123")
        XCTAssertEqual(c.clientId, CodexOAuth.config.clientId)
        XCTAssertEqual(c.redirectURI, CodexOAuth.config.redirectURI)
        XCTAssertEqual(c.redirectPort, 1455)
    }

    func test_deviceCodeConfig_forInstance_replacesStorageKeyOnly() {
        let c = SuperGrokOAuth.config.forInstance("supergrok#abc123")
        XCTAssertEqual(c.providerId, "supergrok#abc123")
        XCTAssertEqual(c.clientId, SuperGrokOAuth.config.clientId)
        XCTAssertEqual(c.scopes, SuperGrokOAuth.config.scopes)
    }

    // MARK: - Chave de API

    func test_openRouter_extraInstanceId() async throws {
        let fetcher = FakeOpenRouterCreditsFetching()
        fetcher.responseToReturn = OpenRouterCreditsResponse(data: .init(totalCredits: 5, totalUsage: 1))
        let provider = OpenRouterUsageProvider(instanceId: "openrouter#abc123", apiKeyProvider: { "k" }, creditsClient: fetcher)
        XCTAssertEqual(provider.id, "openrouter#abc123")
        let snapshot = try await provider.fetchSnapshot()
        XCTAssertEqual(snapshot.providerId, "openrouter#abc123")
    }

    func test_miniMax_extraInstanceId() async throws {
        let fetcher = FakeMiniMaxRemainsFetching()
        fetcher.responseToReturn = MiniMaxRemainsResponse(models: [])
        let provider = MiniMaxUsageProvider(instanceId: "minimax#abc123", apiKeyProvider: { "k" }, region: { .global }, client: fetcher)
        let snapshot = try await provider.fetchSnapshot()
        XCTAssertEqual(snapshot.providerId, "minimax#abc123")
    }

    func test_openCode_instanceIdDefaultsToKind() {
        XCTAssertEqual(OpenCodeUsageProvider(apiKeyProvider: { nil }, estimator: FakeOpenCodeLocalEstimating()).id, "opencode")
        XCTAssertEqual(OpenCodeUsageProvider(instanceId: "opencode#abc123", apiKeyProvider: { nil }, estimator: FakeOpenCodeLocalEstimating()).id, "opencode#abc123")
    }

    // MARK: - IDE

    func test_cursor_extraInstanceId() async throws {
        let reader = FakeCursorTokenReading(); reader.tokenToReturn = "tok"
        let fetcher = FakeCursorUsageFetching()
        fetcher.responseToReturn = CursorUsageResponse(
            billingCycleStart: "1783750752000", billingCycleEnd: "1786429152000",
            planUsage: .init(totalSpend: 10, remaining: nil, limit: 2000, totalPercentUsed: 1))
        let provider = CursorUsageProvider(instanceId: "cursor#abc123", tokenReader: reader, client: fetcher)
        let snapshot = try await provider.fetchSnapshot()
        XCTAssertEqual(snapshot.providerId, "cursor#abc123")
    }

    func test_grokBot_extraInstanceId() async throws {
        let reader = FakeCursorTokenReading(); reader.tokenToReturn = "tok"
        let fetcher = FakeGrokBotUsageFetching()
        fetcher.responseToReturn = GrokBotUsageResponse(usagePercent: 1, nextResetTimestampUtc: "2026-08-31T00:31:02.272Z",
                                                        hasNonZeroIncludedLimit: true, hasAvailableUsage: true, grokPlanLabel: "x")
        let provider = GrokBotUsageProvider(instanceId: "cursor-grokbot#abc123", tokenReader: reader, client: fetcher)
        let snapshot = try await provider.fetchSnapshot()
        XCTAssertEqual(snapshot.providerId, "cursor-grokbot#abc123")
    }

    func test_antigravity_instanceIdDefaultsToKind() {
        XCTAssertEqual(AntigravityUsageProvider().id, "antigravity")
        XCTAssertEqual(AntigravityUsageProvider(instanceId: "antigravity#abc123").id, "antigravity#abc123")
    }
}
