import XCTest
@testable import OkTally

final class FakeGrokBotUsageFetching: GrokBotUsageFetching {
    var responseToReturn: GrokBotUsageResponse!
    private(set) var receivedAccessToken: String?

    func fetchUsage(accessToken: String) async throws -> GrokBotUsageResponse {
        receivedAccessToken = accessToken
        return responseToReturn
    }
}

final class SequencedCursorTokenReading: CursorTokenReading {
    private var values: [String?]

    init(_ values: [String?]) {
        self.values = values
    }

    func readAccessToken() -> String? {
        guard !values.isEmpty else { return nil }
        return values.removeFirst()
    }
}

final class GrokBotUsageProviderTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.stubResponses = [:]
        URLProtocolStub.resetRequestCounts()
        super.tearDown()
    }

    func test_fetchSnapshot_reusesCursorTokenAndMapsDedicatedWeeklyQuota() async throws {
        let reader = FakeCursorTokenReading()
        reader.tokenToReturn = "cursor-session-token"
        let fetcher = FakeGrokBotUsageFetching()
        fetcher.responseToReturn = GrokBotUsageResponse(
            usagePercent: 19.086533,
            nextResetTimestampUtc: "2026-08-31T00:31:02.272Z",
            hasNonZeroIncludedLimit: true,
            hasAvailableUsage: true,
            grokPlanLabel: "Grok Bot Plan"
        )
        let fetchedAt = Date(timeIntervalSince1970: 2_000_000)
        let provider = GrokBotUsageProvider(tokenReader: reader, client: fetcher, now: { fetchedAt })

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(provider.id, "cursor-grokbot")
        XCTAssertEqual(provider.displayName, "GrokBot")
        XCTAssertEqual(fetcher.receivedAccessToken, "cursor-session-token")
        XCTAssertEqual(snapshot.providerId, "cursor-grokbot")
        XCTAssertEqual(snapshot.fetchedAt, fetchedAt)
        XCTAssertEqual(snapshot.planLabel, "Grok Bot Plan")
        XCTAssertEqual(snapshot.quotas, [QuotaWindow(
            label: "weekly",
            shape: .periodicCounter(
                used: 19.086533,
                limit: 100,
                resetAt: Date(timeIntervalSince1970: 1_788_136_262.272)
            )
        )])
    }

    func test_apiClient_readsCurrentCursorGrokBotContract() async throws {
        let fixture = try Data(contentsOf: Bundle.module.url(
            forResource: "grokbot_usage_response",
            withExtension: "json",
            subdirectory: "Fixtures"
        )!)
        let url = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetSandUsageStatus")!
        URLProtocolStub.stubResponses[url] = (fixture, 200)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]

        let response = try await GrokBotUsageAPIClient(
            session: URLSession(configuration: config)
        ).fetchUsage(accessToken: "cursor-session-token")

        XCTAssertEqual(URLProtocolStub.requestCount(for: url), 1)
        XCTAssertEqual(response.usagePercent, 19.086533)
        XCTAssertEqual(response.nextResetTimestampUtc, "2026-08-31T00:31:02.272Z")
        XCTAssertTrue(response.hasNonZeroIncludedLimit)
        XCTAssertTrue(response.hasAvailableUsage)
        XCTAssertEqual(response.grokPlanLabel, "Grok Bot Plan")
    }

    func test_scheduler_survivesTransientCursorTokenReadInsteadOfMarkingGrokBotUnconfigured() async {
        let reader = SequencedCursorTokenReading([nil, "cursor-session-token"])
        let fetcher = FakeGrokBotUsageFetching()
        fetcher.responseToReturn = GrokBotUsageResponse(
            usagePercent: 22.156489,
            nextResetTimestampUtc: "2026-08-31T00:31:02.272Z",
            hasNonZeroIncludedLimit: true,
            hasAvailableUsage: true,
            grokPlanLabel: "Grok Bot Plan"
        )
        let provider = GrokBotUsageProvider(tokenReader: reader, client: fetcher)
        let registry = PluginRegistry()
        registry.register(provider)
        let storage = FakeStorage()
        let scheduler = Scheduler(
            registry: registry,
            storage: storage,
            alertEngine: AlertEngine(),
            alertDispatcher: AlertDispatcher(sender: FakeNotificationSender())
        )

        let results = await scheduler.fetchAll()

        guard case .success(let snapshot) = results.first?.outcome else {
            return XCTFail("expected GrokBot snapshot instead of notConfigured")
        }
        XCTAssertEqual(snapshot.providerId, "cursor-grokbot")
        XCTAssertEqual(storage.saveCount, 1)
        XCTAssertNil(scheduler.lastError["cursor-grokbot"])
    }
}
