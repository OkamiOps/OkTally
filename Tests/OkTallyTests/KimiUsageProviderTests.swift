import XCTest
@testable import OkTally

final class KimiUsageProviderTests: XCTestCase {
    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    override func tearDown() {
        URLProtocolStub.stubResponses = [:]
        URLProtocolStub.stubQueues = [:]
        URLProtocolStub.resetRequestCounts()
        super.tearDown()
    }

    func test_snapshot_parsesSubscriptionWindowsWalletDecimalAndMonthlySpend() throws {
        let reset5h = "2026-10-10T05:00:00Z"
        let reset7d = "2026-10-17T00:00:00Z"
        let resetMonth = "2026-11-01T00:00:00Z"
        let json = #"""
        {
          "usages": {
            "limit_5h": {"used_ratio": 0.3, "reset_time": "\#(reset5h)"},
            "limit_7d": {"used_ratio": "0.2", "reset_time": "\#(reset7d)"},
            "limit_month_total": {"used_ratio": 0.4, "reset_time": "\#(resetMonth)"},
            "limit_month_code": {"used_ratio": 0.25, "reset_time": "\#(resetMonth)"}
          },
          "boosterWallet": {
            "balance": {"type": "BOOSTER", "amount": "20000000000", "amountLeft": "123456789"},
            "monthlyChargeLimitEnabled": true,
            "monthlyChargeLimit": {"currency": "CNY", "priceInCents": "20000"},
            "monthlyUsed": {"currency": "CNY", "priceInCents": "5000"}
          }
        }
        """#
        let fetchedAt = Date(timeIntervalSince1970: 9_000)

        let snapshot = try KimiUsageProvider.snapshot(from: Data(json.utf8), providerID: "kimi#abc123", fetchedAt: fetchedAt, planLabel: "Vivace")

        XCTAssertEqual(snapshot.providerId, "kimi#abc123")
        XCTAssertEqual(snapshot.planLabel, "Vivace")
        XCTAssertNil(snapshot.connectionNote)
        let fiveHours = try XCTUnwrap(snapshot.quotas.first { $0.label == "5h" })
        guard case .rollingWindow(let used, let limit, let start, let reset) = fiveHours.shape else {
            return XCTFail("expected 5h rolling window")
        }
        XCTAssertEqual(used, 0.3, accuracy: 0.000_001)
        XCTAssertEqual(limit, 1)
        XCTAssertEqual(reset, ISO8601DateFormatter().date(from: reset5h))
        XCTAssertEqual(start, reset.addingTimeInterval(-5 * 60 * 60))
        XCTAssertNil(fiveHours.renewalCadence)
        XCTAssertEqual(snapshot.quotas.first { $0.label == "7d" }?.renewalCadence, .weekly)
        XCTAssertEqual(snapshot.quotas.first { $0.label == "Monthly total" }?.renewalCadence, .monthly)
        XCTAssertEqual(snapshot.quotas.first { $0.label == "Monthly code" }?.renewalCadence, .monthly)

        let balance = try XCTUnwrap(snapshot.quotas.first { $0.label == "Booster balance" })
        guard case .creditBalance(let remaining, let currency) = balance.shape else {
            return XCTFail("expected booster credit balance")
        }
        XCTAssertEqual(remaining, Decimal(string: "1.23456789")!)
        XCTAssertEqual(currency, "CNY")

        let monthly = try XCTUnwrap(snapshot.quotas.first { $0.label == "Monthly booster spend" })
        guard case .periodicCounter(let used, let limit, let resetAt) = monthly.shape else {
            return XCTFail("expected monthly booster counter")
        }
        XCTAssertEqual(used, 50, accuracy: 0.000_001)
        XCTAssertEqual(limit, 200, accuracy: 0.000_001)
        XCTAssertEqual(resetAt, ISO8601DateFormatter().date(from: resetMonth))
        XCTAssertEqual(monthly.renewalCadence, .monthly)
    }

    func test_snapshot_dropsInvalidQuotaRatherThanInventingOne() throws {
        let data = Data(#"""
        {"usages":{"limit_5h":{"used_ratio":1.2,"reset_time":"2026-10-10T05:00:00Z"},"limit_7d":{"used_ratio":0.5}}}
        """#.utf8)

        let snapshot = try KimiUsageProvider.snapshot(from: data, providerID: "kimi", fetchedAt: .distantPast, planLabel: nil)

        XCTAssertTrue(snapshot.quotas.isEmpty)
        XCTAssertNotNil(snapshot.connectionNote)
    }

    func test_quotaRejectsBooleanAndPartialDecimalButAcceptsZeroAndOne() throws {
        for (value, expected) in [("true", false), ("\"0.3oops\"", false), ("0", true), ("1", true)] {
            let data = Data("{\"usages\":{\"limit_5h\":{\"used_ratio\":\(value),\"reset_time\":\"2026-10-10T05:00:00Z\"}}}".utf8)
            let snapshot = try KimiUsageProvider.snapshot(from: data, providerID: "kimi", fetchedAt: Date(), planLabel: nil)
            XCTAssertEqual(!snapshot.quotas.isEmpty, expected, value)
        }
    }

    func test_expiredTokenRefreshesAnd401ForcesOneFurtherRefresh() async throws {
        let store = InMemoryTokenStore()
        try store.save(token(access: "expired", refresh: "old-refresh", expiresAt: .distantPast), providerId: "kimi#abc123")
        URLProtocolStub.stubResponses[KimiOAuthClient.tokenURL] = (Data(#"{"access_token":"fresh","expires_in":3600}"#.utf8), 200)
        URLProtocolStub.stubResponses[KimiOAuthClient.profileURL] = (Data(#"{"user_id":"u_1","user_level_name":"Vivace"}"#.utf8), 200)
        URLProtocolStub.stubResponses[KimiUsageProvider.usageURL] = (Data(#"{"usages":{"limit_5h":{"used_ratio":0.1,"reset_time":"2026-10-10T05:00:00Z"}}}"#.utf8), 200)
        let provider = KimiUsageProvider(instanceId: "kimi#abc123", tokenStore: store, session: makeSession())

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.quotas.count, 1)
        XCTAssertEqual(store.load(providerId: "kimi#abc123")?.accessToken, "fresh")
        XCTAssertEqual(store.load(providerId: "kimi#abc123")?.refreshToken, "old-refresh")
        XCTAssertEqual(store.load(providerId: "kimi#abc123")?.extra["userId"], "u_1")
        XCTAssertEqual(URLProtocolStub.requestCount(for: KimiOAuthClient.tokenURL), 1)
        XCTAssertEqual(URLProtocolStub.lastAuthorization(for: KimiUsageProvider.usageURL), "Bearer fresh")
    }

    func test_401_refreshesExactlyOnceThenRequiresReconnection() async throws {
        let store = InMemoryTokenStore()
        try store.save(token(), providerId: "kimi")
        URLProtocolStub.stubResponses[KimiOAuthClient.tokenURL] = (Data(#"{"access_token":"fresh","expires_in":3600}"#.utf8), 200)
        URLProtocolStub.stubResponses[KimiOAuthClient.profileURL] = (Data(#"{"user_id":"u_1"}"#.utf8), 200)
        URLProtocolStub.stubQueues[KimiUsageProvider.usageURL] = [(Data(), 401), (Data(), 401)]
        let provider = KimiUsageProvider(instanceId: "kimi", tokenStore: store, session: makeSession())

        do {
            _ = try await provider.fetchSnapshot()
            XCTFail("expected rejected credential")
        } catch let error as ProviderAPIError {
            guard case .rejectedCredential(let name) = error else { return XCTFail("unexpected provider error") }
            XCTAssertEqual(name, "Kimi Code")
        }
        XCTAssertEqual(URLProtocolStub.requestCount(for: KimiUsageProvider.usageURL), 2)
        XCTAssertEqual(URLProtocolStub.requestCount(for: KimiOAuthClient.tokenURL), 1)
    }

    func test_lateRefreshDoesNotRestoreReplacedCredential() async throws {
        let original = token(access: "expired", refresh: "old-refresh", expiresAt: .distantPast)
        let replacement = token(access: "replacement", refresh: "new-refresh", expiresAt: .distantFuture)
        let store = KimiReplacingTokenStore(original: original, replacement: replacement)
        URLProtocolStub.stubResponses[KimiOAuthClient.tokenURL] = (Data(#"{"access_token":"stale-result","expires_in":3600}"#.utf8), 200)
        URLProtocolStub.stubResponses[KimiOAuthClient.profileURL] = (Data(#"{"user_id":"u_1"}"#.utf8), 200)
        URLProtocolStub.stubResponses[KimiUsageProvider.usageURL] = (Data(#"{"usages":{"limit_5h":{"used_ratio":0,"reset_time":"2026-10-10T05:00:00Z"}}}"#.utf8), 200)
        let provider = KimiUsageProvider(instanceId: "kimi", tokenStore: store, session: makeSession())

        do {
            _ = try await provider.fetchSnapshot()
            XCTFail("replaced credentials must cancel the old fetch")
        } catch is CancellationError { }

        XCTAssertEqual(URLProtocolStub.requestCount(for: KimiUsageProvider.usageURL), 0)
        XCTAssertEqual(store.saveCount, 0)
        XCTAssertEqual(store.current, replacement)
    }

    private func token(access: String = "active", refresh: String? = "refresh", expiresAt: Date? = .distantFuture) -> OAuthToken {
        OAuthToken(accessToken: access, refreshToken: refresh, expiresAt: expiresAt, extra: ["userId": "u_old"])
    }
}

private final class KimiReplacingTokenStore: TokenStoring {
    private let original: OAuthToken
    let replacement: OAuthToken
    private var loadCount = 0
    private(set) var current: OAuthToken
    private(set) var saveCount = 0

    init(original: OAuthToken, replacement: OAuthToken) {
        self.original = original
        self.replacement = replacement
        self.current = replacement
    }

    func save(_ token: OAuthToken, providerId: String) throws {
        saveCount += 1
        current = token
    }

    func load(providerId: String) -> OAuthToken? {
        loadCount += 1
        return loadCount == 1 ? original : replacement
    }

    func delete(providerId: String) throws {
        current = OAuthToken(accessToken: "", refreshToken: nil, expiresAt: nil, extra: [:])
    }
}
