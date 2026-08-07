import Foundation

actor PricingEngine {
    private let source: PricingSource
    private let cacheTTL: TimeInterval
    private var cache: [String: ModelPricing] = [:]
    private var lastFetched: Date?

    init(source: PricingSource, cacheTTL: TimeInterval = 3600) {
        self.source = source
        self.cacheTTL = cacheTTL
    }

    func refreshIfStale() async throws {
        if let lastFetched, Date().timeIntervalSince(lastFetched) < cacheTTL { return }
        let pricing = try await source.fetchModelPricing()
        cache = Dictionary(uniqueKeysWithValues: pricing.map { ($0.modelId, $0) })
        lastFetched = Date()
    }

    func estimatedCost(for usage: UsageDetail) -> Decimal? {
        guard let pricing = cache[usage.modelId] else { return nil }
        return pricing.promptPricePerToken * Decimal(usage.promptTokens)
            + pricing.completionPricePerToken * Decimal(usage.completionTokens)
    }
}
