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

        XCTAssertEqual(response.data.totalCredits, Decimal(50))
        XCTAssertEqual(response.data.totalUsage, Decimal(12.5))
    }

    func test_fetchSnapshot_precisionSurvivesRealisticDecimalValues() async throws {
        // Decode through JSONDecoder (like the real API path) rather than constructing
        // DataField with Swift float literals: Decimal's ExpressibleByFloatLiteral
        // conformance itself round-trips through Double, which would reintroduce the
        // exact residue this test is meant to catch before the code under test even runs.
        let json = #"{ "data": { "total_credits": 123.456789, "total_usage": 45.123456 } }"#.data(using: .utf8)!
        let response = try JSONDecoder().decode(OpenRouterCreditsResponse.self, from: json)
        let fetcher = FakeOpenRouterCreditsFetching()
        fetcher.responseToReturn = response
        let provider = OpenRouterUsageProvider(apiKeyProvider: { "key123" }, creditsClient: fetcher)

        let snapshot = try await provider.fetchSnapshot()

        guard case .creditBalance(let remaining, _) = snapshot.quotas[0].shape else {
            return XCTFail("expected creditBalance shape")
        }
        XCTAssertEqual(remaining, Decimal(string: "78.333333")!)
    }
}
