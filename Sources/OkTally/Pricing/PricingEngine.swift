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
        // Cache pricing vem da mesma tabela pública. Se algum modelo não o expuser,
        // cair no preço de input normal é um fallback explícito, sem inventar desconto.
        let cacheReadPrice = pricing.cacheReadPricePerToken ?? pricing.promptPricePerToken
        let cacheWritePrice = pricing.cacheWritePricePerToken ?? pricing.promptPricePerToken
        let cacheWrite1hPrice = pricing.cacheWrite1hPricePerToken ?? cacheWritePrice
        return pricing.promptPricePerToken * Decimal(usage.promptTokens)
            + pricing.completionPricePerToken * Decimal(usage.completionTokens)
            + cacheReadPrice * Decimal(usage.cacheReadTokens ?? 0)
            + cacheWritePrice * Decimal(usage.cacheWriteTokens ?? 0)
            + cacheWrite1hPrice * Decimal(usage.cacheWrite1hTokens ?? 0)
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
        if let exactSuffix = cache.first(where: { $0.key.hasSuffix(suffix) && !$0.key.contains(":batch") })?.value {
            return exactSuffix
        }
        // IDs locais não são normalizados como os do catálogo: Claude local usa
        // `claude-opus-4-8`, OpenRouter `anthropic/claude-opus-4.8`. Comparar a forma
        // alfanumérica cobre esse drift sem depender de uma tabela fixa de aliases.
        let wanted = canonicalModelKey(stripDateSuffix(String(idPart)))
        return cache.first {
            !$0.key.contains(":batch") && canonicalModelKey(stripDateSuffix(String($0.key.split(separator: "/").last ?? ""))) == wanted
        }?.value
    }

    /// Alguns runtimes anexam a data do snapshot (`claude-haiku-4-5-20251001`), enquanto
    /// o catálogo publica a família (`claude-haiku-4.5`). A data não muda a família de
    /// preço, então só um sufixo `-yyyyMMdd` é removido.
    private func stripDateSuffix(_ id: String) -> String {
        guard id.count > 9 else { return id }
        let suffix = id.suffix(8)
        let separatorIndex = id.index(id.endIndex, offsetBy: -9)
        guard suffix.allSatisfy(\.isNumber), id[separatorIndex] == "-" else { return id }
        return String(id.dropLast(9))
    }

    private func canonicalModelKey(_ id: String) -> String {
        String(id.lowercased().filter { $0.isLetter || $0.isNumber })
    }
}
