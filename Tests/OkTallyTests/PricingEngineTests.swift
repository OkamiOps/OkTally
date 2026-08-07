import XCTest
@testable import OkTally

final class FakePricingSource: PricingSource {
    var pricingToReturn: [ModelPricing] = []
    private(set) var fetchCount = 0
    func fetchModelPricing() async throws -> [ModelPricing] {
        fetchCount += 1
        return pricingToReturn
    }
}

final class PricingEngineTests: XCTestCase {
    func test_refreshIfStale_fetchesOnceThenCaches() async throws {
        let source = FakePricingSource()
        source.pricingToReturn = [ModelPricing(modelId: "m1", promptPricePerToken: 0.000003, completionPricePerToken: 0.000015)]
        let engine = PricingEngine(source: source, cacheTTL: 3600)

        try await engine.refreshIfStale()
        try await engine.refreshIfStale()

        XCTAssertEqual(source.fetchCount, 1)
    }

    func test_estimatedCost_computesPromptPlusCompletion() async throws {
        let source = FakePricingSource()
        source.pricingToReturn = [ModelPricing(modelId: "m1", promptPricePerToken: 0.000003, completionPricePerToken: 0.000015)]
        let engine = PricingEngine(source: source)
        try await engine.refreshIfStale()

        let usage = UsageDetail(modelId: "m1", promptTokens: 1000, completionTokens: 500)
        let cost = await engine.estimatedCost(for: usage)

        XCTAssertEqual(cost, Decimal(0.003) + Decimal(0.0075))
    }

    func test_estimatedCost_unknownModel_returnsNil() async throws {
        let source = FakePricingSource()
        let engine = PricingEngine(source: source)
        try await engine.refreshIfStale()

        let usage = UsageDetail(modelId: "unknown/model", promptTokens: 10, completionTokens: 10)
        let cost = await engine.estimatedCost(for: usage)

        XCTAssertNil(cost)
    }

    func test_openRouterPricingSource_decodesFixture() async throws {
        let fixtureURL = Bundle.module.url(forResource: "openrouter_models_response", withExtension: "json", subdirectory: "Fixtures")!
        let data = try Data(contentsOf: fixtureURL)
        URLProtocolStub.stubResponses[URL(string: "https://openrouter.ai/api/v1/models")!] = (data, 200)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: config)

        let source = OpenRouterPricingSource(session: session)
        let pricing = try await source.fetchModelPricing()

        XCTAssertEqual(pricing.count, 2)
        XCTAssertEqual(pricing.first?.modelId, "anthropic/claude-3.5-sonnet")
    }
}
