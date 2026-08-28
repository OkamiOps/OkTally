import XCTest
@testable import OkTally

final class FakeMiniMaxRemainsFetching: MiniMaxRemainsFetching {
    var responseToReturn: MiniMaxRemainsResponse!
    func fetchRemains(apiKey: String, region: MiniMaxRegion) async throws -> MiniMaxRemainsResponse { responseToReturn }
}

final class MiniMaxUsageProviderTests: XCTestCase {
    func test_fetchSnapshot_mapsFiveHourAndWeekly() async throws {
        let fetcher = FakeMiniMaxRemainsFetching()
        fetcher.responseToReturn = MiniMaxRemainsResponse(models: [
            MiniMaxModelRemains(
                modelName: "MiniMax-M3",
                currentIntervalTotalCount: 1000,
                currentIntervalUsageCount: 400,
                currentWeeklyTotalCount: 5000,
                currentWeeklyUsageCount: 1500,
                currentIntervalRemainingPercent: 60,
                currentWeeklyRemainingPercent: 70,
                currentIntervalStatus: 3,
                currentWeeklyStatus: 3,
                remainsTime: 18_000_000
            ),
            MiniMaxModelRemains(
                modelName: "video",
                currentIntervalTotalCount: 0,
                currentIntervalUsageCount: 0,
                currentWeeklyTotalCount: 0,
                currentWeeklyUsageCount: 0,
                currentIntervalRemainingPercent: 100,
                currentWeeklyRemainingPercent: 100,
                currentIntervalStatus: 3,
                currentWeeklyStatus: 3,
                remainsTime: 0
            )
        ])
        let provider = MiniMaxUsageProvider(apiKeyProvider: { "sk-cp-key" }, region: { .global }, client: fetcher)

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.providerId, "minimax")
        XCTAssertEqual(snapshot.quotas.count, 2)

        guard let fiveHour = snapshot.quotas.first(where: { $0.label == "5h" }) else {
            return XCTFail("expected a 5h quota window")
        }
        XCTAssertEqual(fiveHour.shape.usedPercent ?? -1, 40, accuracy: 0.001)
        XCTAssertNil(fiveHour.renewalCadence)

        guard let weekly = snapshot.quotas.first(where: { $0.label == "weekly" }) else {
            return XCTFail("expected a weekly quota window")
        }
        XCTAssertEqual(weekly.shape.usedPercent ?? -1, 30, accuracy: 0.001)
        XCTAssertEqual(weekly.renewalCadence, .weekly)
    }

    func test_fetchSnapshot_missingAPIKey_throws() async {
        let provider = MiniMaxUsageProvider(apiKeyProvider: { nil }, region: { .global }, client: FakeMiniMaxRemainsFetching())

        do {
            _ = try await provider.fetchSnapshot()
            XCTFail("expected to throw")
        } catch MiniMaxError.missingAPIKey {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func test_isAuthenticated_reflectsKey() async {
        let withKey = MiniMaxUsageProvider(apiKeyProvider: { "key" }, region: { .global }, client: FakeMiniMaxRemainsFetching())
        let withoutKey = MiniMaxUsageProvider(apiKeyProvider: { nil }, region: { .global }, client: FakeMiniMaxRemainsFetching())

        let a = await withKey.isAuthenticated()
        let b = await withoutKey.isAuthenticated()

        XCTAssertTrue(a)
        XCTAssertFalse(b)
    }

    func test_apiClient_decodesFixture() async throws {
        let fixtureURL = Bundle.module.url(forResource: "minimax_remains_response", withExtension: "json", subdirectory: "Fixtures")!
        let data = try Data(contentsOf: fixtureURL)
        URLProtocolStub.stubResponses[URL(string: "https://www.minimax.io/v1/token_plan/remains")!] = (data, 200)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: config)

        let client = MiniMaxAPIClient(session: session)
        let response = try await client.fetchRemains(apiKey: "sk-cp-key", region: .global)

        XCTAssertEqual(response.models.count, 2)
        let first = response.models[0]
        XCTAssertEqual(first.modelName, "MiniMax-M3")
        XCTAssertEqual(first.currentIntervalTotalCount, 1000)
        XCTAssertEqual(first.currentIntervalUsageCount, 400)
        XCTAssertEqual(first.currentWeeklyTotalCount, 5000)
        XCTAssertEqual(first.currentWeeklyUsageCount, 1500)
        XCTAssertEqual(first.remainsTime, 18_000_000)
    }
}
