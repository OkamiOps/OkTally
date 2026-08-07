import XCTest
@testable import OkTally

final class FakeSuperGrokUsageFetching: SuperGrokUsageFetching {
    var responseToReturn: SuperGrokUsageSnapshot!
    var errorToThrow: Error?
    private(set) var lastAccessToken: String?

    func fetchUsage(accessToken: String) async throws -> SuperGrokUsageSnapshot {
        lastAccessToken = accessToken
        if let errorToThrow { throw errorToThrow }
        return responseToReturn
    }
}

final class SuperGrokUsageProviderTests: XCTestCase {
    private func makeProvider(fetcher: FakeSuperGrokUsageFetching, tokenInStore: Bool = true, now: @escaping () -> Date = Date.init) throws -> SuperGrokUsageProvider {
        let store = InMemoryTokenStore()
        if tokenInStore {
            try store.save(OAuthToken(accessToken: "tok", refreshToken: "rt", expiresAt: nil, extra: [:]), providerId: "supergrok")
        }
        let oauthManager = FakeOAuthManaging()
        oauthManager.accessTokenToReturn = "tok"
        return SuperGrokUsageProvider(oauthManager: oauthManager, tokenStore: store, apiClient: fetcher, now: now)
    }

    func test_id_displayName_refreshInterval() {
        let provider = try! makeProvider(fetcher: FakeSuperGrokUsageFetching())
        XCTAssertEqual(provider.id, "supergrok")
        XCTAssertEqual(provider.displayName, "SuperGrok")
        XCTAssertEqual(provider.refreshInterval, 300)
    }

    func test_isAuthenticated_reflectsStoredToken() async throws {
        let withToken = try makeProvider(fetcher: FakeSuperGrokUsageFetching(), tokenInStore: true)
        let withoutToken = try makeProvider(fetcher: FakeSuperGrokUsageFetching(), tokenInStore: false)

        let authenticated = await withToken.isAuthenticated()
        let notAuthenticated = await withoutToken.isAuthenticated()
        XCTAssertTrue(authenticated)
        XCTAssertFalse(notAuthenticated)
    }

    func test_fetchSnapshot_mapsCreditUsagePercentToWeeklyRollingWindow() async throws {
        let fetcher = FakeSuperGrokUsageFetching()
        let resetAt = Date(timeIntervalSince1970: 2_000_000)
        fetcher.responseToReturn = SuperGrokUsageSnapshot(creditUsagePercent: 42.5, resetAt: resetAt)
        let provider = try makeProvider(fetcher: fetcher)

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.providerId, "supergrok")
        XCTAssertEqual(snapshot.quotas.count, 1)
        let window = snapshot.quotas[0]
        XCTAssertEqual(window.label, "weekly")
        XCTAssertEqual(window.shape, .rollingWindow(
            used: 42.5, limit: 100,
            windowStart: resetAt.addingTimeInterval(-7 * 24 * 3600),
            resetAt: resetAt
        ))
        XCTAssertEqual(window.shape.usedPercent, 42.5)
        XCTAssertEqual(fetcher.lastAccessToken, "tok")
    }

    /// xAI's proto/JSON encoding omits `creditUsagePercent` entirely at 0%
    /// usage (documented in the research, see plan2-supergrok.md §2.1) — an
    /// absent value must be treated as 0%, not "unknown".
    func test_fetchSnapshot_absentCreditUsagePercent_treatedAsZero() async throws {
        let fetcher = FakeSuperGrokUsageFetching()
        fetcher.responseToReturn = SuperGrokUsageSnapshot(creditUsagePercent: nil, resetAt: Date(timeIntervalSince1970: 2_000_000))
        let provider = try makeProvider(fetcher: fetcher)

        let snapshot = try await provider.fetchSnapshot()

        guard case .rollingWindow(let used, _, _, _) = snapshot.quotas[0].shape else {
            return XCTFail("expected .rollingWindow shape")
        }
        XCTAssertEqual(used, 0)
    }

    func test_fetchSnapshot_missingResetAt_fallsBackToNow() async throws {
        let fetcher = FakeSuperGrokUsageFetching()
        fetcher.responseToReturn = SuperGrokUsageSnapshot(creditUsagePercent: 10, resetAt: nil)
        let fixedNow = Date(timeIntervalSince1970: 3_000_000)
        let provider = try makeProvider(fetcher: fetcher, now: { fixedNow })

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.quotas[0].shape.resetAt, fixedNow)
    }

    func test_fetchSnapshot_propagatesApiClientError() async throws {
        let fetcher = FakeSuperGrokUsageFetching()
        fetcher.errorToThrow = SuperGrokUsageError.badResponse(500)
        let provider = try makeProvider(fetcher: fetcher)

        do {
            _ = try await provider.fetchSnapshot()
            XCTFail("expected throw")
        } catch SuperGrokUsageError.badResponse(let code) {
            XCTAssertEqual(code, 500)
        }
    }
}

final class SuperGrokAPIClientTests: XCTestCase {
    private func makeSession() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: cfg)
    }

    func test_fetchUsage_decodesUserThenBillingFixtures() async throws {
        let userData = try Data(contentsOf: Bundle.module.url(forResource: "supergrok_user_response", withExtension: "json", subdirectory: "Fixtures")!)
        let billingData = try Data(contentsOf: Bundle.module.url(forResource: "supergrok_billing_response", withExtension: "json", subdirectory: "Fixtures")!)
        URLProtocolStub.stubResponses[URL(string: "https://cli-chat-proxy.grok.com/v1/user")!] = (userData, 200)
        URLProtocolStub.stubResponses[URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!] = (billingData, 200)

        let client = SuperGrokAPIClient(session: makeSession())
        let snapshot = try await client.fetchUsage(accessToken: "tok")

        XCTAssertEqual(snapshot.creditUsagePercent, 42.5)
        XCTAssertEqual(snapshot.resetAt, ISO8601DateFormatter().date(from: "2026-08-11T00:00:00Z"))
    }

    func test_fetchUsage_userLookupFails_throwsBadResponse() async {
        URLProtocolStub.stubResponses[URL(string: "https://cli-chat-proxy.grok.com/v1/user")!] = (Data(), 401)

        let client = SuperGrokAPIClient(session: makeSession())

        do {
            _ = try await client.fetchUsage(accessToken: "tok")
            XCTFail("expected throw")
        } catch SuperGrokUsageError.badResponse(let code) {
            XCTAssertEqual(code, 401)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }
}
