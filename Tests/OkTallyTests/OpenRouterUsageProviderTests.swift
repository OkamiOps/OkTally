import XCTest
@testable import OkTally

final class FakeOpenRouterCreditsFetching: OpenRouterCreditsFetching {
    var responseToReturn: OpenRouterCreditsResponse!
    func fetchCredits(apiKey: String) async throws -> OpenRouterCreditsResponse { responseToReturn }
}

final class OpenRouterUsageProviderTests: XCTestCase {
    func test_fetchSnapshot_computesRemainingBalance() async throws {
        let fetcher = FakeOpenRouterCreditsFetching()
        fetcher.responseToReturn = OpenRouterCreditsResponse(data: .init(totalCredits: 50, totalUsage: 12.5))
        let provider = OpenRouterUsageProvider(apiKeyProvider: { "key123" }, creditsClient: fetcher)

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.providerId, "openrouter")
        XCTAssertEqual(snapshot.quotas.count, 1)
        guard case .creditBalance(let remaining, let currency) = snapshot.quotas[0].shape else {
            return XCTFail("expected creditBalance shape")
        }
        XCTAssertEqual(remaining, 37.5)
        XCTAssertEqual(currency, "USD")
    }

    func test_fetchSnapshot_withoutAPIKey_throwsMissingAPIKey() async {
        let provider = OpenRouterUsageProvider(apiKeyProvider: { nil }, creditsClient: FakeOpenRouterCreditsFetching())

        do {
            _ = try await provider.fetchSnapshot()
            XCTFail("expected to throw")
        } catch OpenRouterError.missingAPIKey {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func test_isAuthenticated_reflectsAPIKeyPresence() async {
        let withKey = OpenRouterUsageProvider(apiKeyProvider: { "key" }, creditsClient: FakeOpenRouterCreditsFetching())
        let withoutKey = OpenRouterUsageProvider(apiKeyProvider: { nil }, creditsClient: FakeOpenRouterCreditsFetching())

        let a = await withKey.isAuthenticated()
        let b = await withoutKey.isAuthenticated()

        XCTAssertTrue(a)
        XCTAssertFalse(b)
    }

    func test_apiClient_decodesFixture() async throws {
        let fixtureURL = Bundle.module.url(forResource: "openrouter_credits_response", withExtension: "json", subdirectory: "Fixtures")!
        let data = try Data(contentsOf: fixtureURL)
        URLProtocolStub.stubResponses[URL(string: "https://openrouter.ai/api/v1/credits")!] = (data, 200)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: config)

        let client = OpenRouterAPIClient(session: session)
        let response = try await client.fetchCredits(apiKey: "key123")

        XCTAssertEqual(response.data.totalCredits, 50.0)
        XCTAssertEqual(response.data.totalUsage, 12.5)
    }
}
