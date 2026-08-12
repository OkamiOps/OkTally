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
        guard let pricing = pricing(for: usage.modelId) else { return nil }
        return pricing.promptPricePerToken * Decimal(usage.promptTokens)
            + pricing.completionPricePerToken * Decimal(usage.completionTokens)
    }

    /// Total across details; `nil` when no detail matched any known model (so callers can
    /// distinguish "custa $0" de "não sei precificar").
    func estimatedCost(for details: [UsageDetail]) -> Decimal? {
        let costs = details.compactMap { estimatedCost(for: $0) }
        guard !costs.isEmpty else { return nil }
        return costs.reduce(0, +)
    }

    /// Exact id first; local sources (ex.: opencode.db) usam prefixos de provider que não
    /// batem com os do OpenRouter ("xai/…" vs "x-ai/…"), então cai para um match pelo
    /// sufixo "/<idDoModelo>" quando o exato falha.
    private func pricing(for modelId: String) -> ModelPricing? {
        if let exact = cache[modelId] { return exact }
        guard let idPart = modelId.split(separator: "/").last, !idPart.isEmpty else { return nil }
        let suffix = "/" + idPart
        return cache.first { $0.key.hasSuffix(suffix) }?.value
    }
}
