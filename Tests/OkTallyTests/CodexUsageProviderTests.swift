import XCTest
@testable import OkTally

final class FakeOAuthManaging: OAuthManaging {
    var accessTokenToReturn = "tok"
    var errorToThrow: Error?
    func validAccessToken(providerId: String, config: OAuthConfig) async throws -> String {
        if let errorToThrow { throw errorToThrow }
        return accessTokenToReturn
    }
    func exchangeCode(_ code: String, verifier: String, config: OAuthConfig) async throws -> OAuthToken {
        OAuthToken(accessToken: accessTokenToReturn, refreshToken: nil, expiresAt: nil, extra: [:])
    }
    func exchangeManualCode(code: String, state: String, verifier: String, config: OAuthConfig) async throws -> OAuthToken {
        OAuthToken(accessToken: accessTokenToReturn, refreshToken: nil, expiresAt: nil, extra: [:])
    }
    func refresh(providerId: String, config: OAuthConfig) async throws -> OAuthToken {
        OAuthToken(accessToken: accessTokenToReturn, refreshToken: nil, expiresAt: nil, extra: [:])
    }
}

final class FakeCodexUsageFetching: CodexUsageFetching {
    var responseToReturn: CodexUsageResponse!
    private(set) var lastAccountId: String?
    func fetchUsage(accessToken: String, accountId: String?) async throws -> CodexUsageResponse {
        lastAccountId = accountId
        return responseToReturn
    }
}

final class CodexUsageProviderTests: XCTestCase {
    private func makeProvider(fetcher: FakeCodexUsageFetching, tokenInStore: Bool = true) throws -> CodexUsageProvider {
        let store = InMemoryTokenStore()
        if tokenInStore {
            try store.save(OAuthToken(accessToken: "tok", refreshToken: "rt", expiresAt: nil, extra: ["account_id": "acc-9"]), providerId: "codex")
        }
        return CodexUsageProvider(oauthManager: FakeOAuthManaging(), tokenStore: store, apiClient: fetcher)
    }

    func test_fetchSnapshot_labelsWindowsByDuration_andIncludesAdditionalLimits() async throws {
        let fetcher = FakeCodexUsageFetching()
        fetcher.responseToReturn = CodexUsageResponse(
            planType: "pro",
            rateLimit: CodexRateLimit(
                primaryWindow: CodexRateLimitWindow(usedPercent: 69, limitWindowSeconds: 604800, resetAt: Date(timeIntervalSince1970: 1000)),
                secondaryWindow: nil
            ),
            additionalRateLimits: [
                CodexAdditionalLimit(
                    limitName: "GPT-5.3-Codex-Spark",
                    rateLimit: CodexRateLimit(
                        primaryWindow: CodexRateLimitWindow(usedPercent: 9, limitWindowSeconds: 604800, resetAt: Date(timeIntervalSince1970: 2000)),
                        secondaryWindow: nil
                    )
                )
            ]
        )
        let provider = try makeProvider(fetcher: fetcher)

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.providerId, "codex")
        XCTAssertEqual(snapshot.quotas.count, 2)
        // The 604800s general window is labelled "semanal", never "5h".
        XCTAssertEqual(snapshot.quotas.first { $0.label == "semanal" }?.shape.usedPercent, 69)
        XCTAssertNil(snapshot.quotas.first { $0.label == "5h" })
        // The named additional limit surfaces under its feature name.
        XCTAssertEqual(snapshot.quotas.first { $0.label.contains("GPT-5.3-Codex-Spark") }?.shape.usedPercent, 9)
        XCTAssertEqual(fetcher.lastAccountId, "acc-9")
        XCTAssertEqual(snapshot.planLabel, "Pro")
    }

    func test_planDisplayName_capitalizesAndStripsPrefix() {
        XCTAssertEqual(CodexUsageProvider.planDisplayName("pro"), "Pro")
        XCTAssertEqual(CodexUsageProvider.planDisplayName("plus"), "Plus")
        XCTAssertEqual(CodexUsageProvider.planDisplayName("chatgpt_team"), "Team")
    }

    func test_fetchSnapshot_fiveHourWindowLabelled5h() async throws {
        let fetcher = FakeCodexUsageFetching()
        fetcher.responseToReturn = CodexUsageResponse(
            planType: nil,
            rateLimit: CodexRateLimit(
                primaryWindow: CodexRateLimitWindow(usedPercent: 5, limitWindowSeconds: 18000, resetAt: nil),
                secondaryWindow: nil
            )
        )
        let provider = try makeProvider(fetcher: fetcher)

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.quotas.count, 1)
        XCTAssertEqual(snapshot.quotas.first?.label, "5h")
    }

    func test_isAuthenticated_reflectsStoredToken() async throws {
        let withToken = try makeProvider(fetcher: FakeCodexUsageFetching(), tokenInStore: true)
        let withoutToken = try makeProvider(fetcher: FakeCodexUsageFetching(), tokenInStore: false)
        let a = await withToken.isAuthenticated()
        let b = await withoutToken.isAuthenticated()
        XCTAssertTrue(a)
        XCTAssertFalse(b)
    }

    func test_apiClient_decodesFixture() async throws {
        let data = try Data(contentsOf: Bundle.module.url(forResource: "codex_usage_response", withExtension: "json", subdirectory: "Fixtures")!)
        URLProtocolStub.stubResponses[URL(string: "https://chatgpt.com/backend-api/wham/usage")!] = (data, 200)
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [URLProtocolStub.self]

        let client = CodexUsageAPIClient(session: URLSession(configuration: cfg))
        let response = try await client.fetchUsage(accessToken: "tok", accountId: "acc-9")

        XCTAssertEqual(response.planType, "pro")
        XCTAssertEqual(response.rateLimit?.primaryWindow?.usedPercent, 37.5)
        XCTAssertNotNil(response.rateLimit?.secondaryWindow)
    }
}
