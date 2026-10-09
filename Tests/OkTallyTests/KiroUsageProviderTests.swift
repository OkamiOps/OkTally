import XCTest
@testable import OkTally

final class KiroUsageProviderTests: XCTestCase {
    private let profileArn = "arn:aws:codewhisperer:us-east-1:123456789012:profile/work-profile"
    private let usageURL = URL(string: "https://management.us-east-1.kiro.dev/Get-Usage-Limits?profileArn=arn:aws:codewhisperer:us-east-1:123456789012:profile/work-profile&origin=KIRO_CLI")!
    private let oidcURL = URL(string: "https://oidc.us-east-1.amazonaws.com/token")!

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    private func token(access: String = "active-access", refresh: String? = "refresh", expiresAt: Date? = .distantFuture) -> OAuthToken {
        OAuthToken(accessToken: access, refreshToken: refresh, expiresAt: expiresAt, extra: [
            "profileArn": profileArn,
            "region": "us-east-1",
            "clientId": "test-client",
            "clientSecret": "redacted-test-secret",
            "startURL": "https://d-123.awsapps.com/start",
            "profileName": "Work",
            "authMethod": "oidc"
        ])
    }

    private let validUsage = #"""
    {
      "usageBreakdownList": [
        {
          "resourceType": "MONTHLY_CREDITS",
          "displayName": "Kiro credits",
          "currentUsage": 7249,
          "currentUsageWithPrecision": 7249.42,
          "usageLimit": 10000,
          "usageLimitWithPrecision": 10000,
          "nextDateReset": 1798761600
        }
      ],
      "subscriptionInfo": { "subscriptionTitle": "KIRO POWER" }
    }
    """#

    override func tearDown() {
        URLProtocolStub.stubResponses = [:]
        URLProtocolStub.stubQueues = [:]
        URLProtocolStub.resetRequestCounts()
        super.tearDown()
    }

    func test_mapsIndependentMonthlyPreciseQuotaAndPlan() async throws {
        let store = InMemoryTokenStore()
        try store.save(token(), providerId: "kiro#abc123")
        URLProtocolStub.stubResponses[usageURL] = (Data(validUsage.utf8), 200)
        let provider = KiroUsageProvider(instanceId: "kiro#abc123", tokenStore: store, session: makeSession())

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.planLabel, "KIRO POWER")
        let quota = try XCTUnwrap(snapshot.quotas.first)
        XCTAssertEqual(quota.label, "Kiro credits")
        guard case .periodicCounter(let used, let limit, let resetAt) = quota.shape else {
            return XCTFail("expected periodic monthly counter")
        }
        XCTAssertEqual(used, 7249.42, accuracy: 0.000_001)
        XCTAssertEqual(limit, 10_000, accuracy: 0.000_001)
        XCTAssertEqual(resetAt, Date(timeIntervalSince1970: 1_798_761_600))
        XCTAssertEqual(quota.renewalCadence, .monthly)
        XCTAssertEqual(URLProtocolStub.lastAuthorization(for: usageURL), "Bearer active-access")
    }

    func test_expiredCredentialRefreshesRotatesAndPreservesProviderScopedCopy() async throws {
        let store = InMemoryTokenStore()
        let expired = token(access: "expired-access", refresh: "old-refresh", expiresAt: .distantPast)
        try store.save(expired, providerId: "kiro#abc123")
        URLProtocolStub.stubResponses[oidcURL] = (Data(#"{"accessToken":"fresh-access","refreshToken":"rotated-refresh","expiresIn":3600}"#.utf8), 200)
        URLProtocolStub.stubResponses[usageURL] = (Data(validUsage.utf8), 200)
        let provider = KiroUsageProvider(instanceId: "kiro#abc123", tokenStore: store, session: makeSession())

        _ = try await provider.fetchSnapshot()

        let saved = try XCTUnwrap(store.load(providerId: "kiro#abc123"))
        XCTAssertEqual(saved.accessToken, "fresh-access")
        XCTAssertEqual(saved.refreshToken, "rotated-refresh")
        XCTAssertEqual(saved.extra["profileArn"], profileArn)
        XCTAssertEqual(URLProtocolStub.lastAuthorization(for: usageURL), "Bearer fresh-access")
        XCTAssertEqual(URLProtocolStub.requestCount(for: oidcURL), 1)
    }

    func test_401ForcesExactlyOneRefreshThenRetriesUsage() async throws {
        let store = InMemoryTokenStore()
        try store.save(token(), providerId: "kiro#abc123")
        URLProtocolStub.stubResponses[oidcURL] = (Data(#"{"accessToken":"forced-fresh","expiresIn":3600}"#.utf8), 200)
        URLProtocolStub.stubQueues[usageURL] = [(Data(), 401), (Data(validUsage.utf8), 200)]
        let provider = KiroUsageProvider(instanceId: "kiro#abc123", tokenStore: store, session: makeSession())

        _ = try await provider.fetchSnapshot()

        XCTAssertEqual(URLProtocolStub.requestCount(for: usageURL), 2)
        XCTAssertEqual(URLProtocolStub.requestCount(for: oidcURL), 1)
        XCTAssertEqual(store.load(providerId: "kiro#abc123")?.refreshToken, "refresh")
    }

    func test_missingValidQuotaIsAnErrorRatherThanFabricatedPercentage() async throws {
        let store = InMemoryTokenStore()
        try store.save(token(), providerId: "kiro#abc123")
        URLProtocolStub.stubResponses[usageURL] = (Data(#"{"usageBreakdownList":[{"displayName":"Credits","currentUsage":0,"usageLimit":0,"nextDateReset":1798761600}]}"#.utf8), 200)
        let provider = KiroUsageProvider(instanceId: "kiro#abc123", tokenStore: store, session: makeSession())

        do {
            _ = try await provider.fetchSnapshot()
            XCTFail("expected malformed usage payload")
        } catch let error as ProviderAPIError {
            guard case .malformedResponse(let name) = error else { return XCTFail("unexpected provider error") }
            XCTAssertEqual(name, "Kiro")
        }
    }

    func test_refreshNeverRewritesCredentialReplacedWhileRequestWasInFlight() async throws {
        let original = token(access: "expired-access", refresh: "old-refresh", expiresAt: .distantPast)
        let replacement = token(access: "new-login-access", refresh: "new-login-refresh", expiresAt: .distantFuture)
        let store = ReplacingTokenStore(original: original, replacement: replacement)
        URLProtocolStub.stubResponses[oidcURL] = (Data(#"{"accessToken":"stale-refresh-result","refreshToken":"stale-rotated","expiresIn":3600}"#.utf8), 200)
        URLProtocolStub.stubResponses[usageURL] = (Data(validUsage.utf8), 200)
        let provider = KiroUsageProvider(instanceId: "kiro#abc123", tokenStore: store, session: makeSession())

        do {
            _ = try await provider.fetchSnapshot()
            XCTFail("replaced credentials must cancel the old fetch")
        } catch is CancellationError { }

        XCTAssertEqual(URLProtocolStub.requestCount(for: usageURL), 0)
        XCTAssertEqual(store.saveCount, 0)
        XCTAssertEqual(store.current, replacement)
    }
}

/// Simula logout/relogin entre a leitura do token expirado e o retorno do endpoint de
/// refresh. A implementação não deve sobrescrever esse login novo com resposta antiga.
private final class ReplacingTokenStore: TokenStoring {
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
