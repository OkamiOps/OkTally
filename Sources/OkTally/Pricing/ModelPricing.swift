import Foundation

struct ModelPricing: Equatable {
    let modelId: String
    let promptPricePerToken: Decimal
    let completionPricePerToken: Decimal
    let cacheReadPricePerToken: Decimal?
    let cacheWritePricePerToken: Decimal?
    let cacheWrite1hPricePerToken: Decimal?

    init(
        modelId: String,
        promptPricePerToken: Decimal,
        completionPricePerToken: Decimal,
        cacheReadPricePerToken: Decimal? = nil,
        cacheWritePricePerToken: Decimal? = nil,
        cacheWrite1hPricePerToken: Decimal? = nil
    ) {
        self.modelId = modelId
        self.promptPricePerToken = promptPricePerToken
        self.completionPricePerToken = completionPricePerToken
        self.cacheReadPricePerToken = cacheReadPricePerToken
        self.cacheWritePricePerToken = cacheWritePricePerToken
        self.cacheWrite1hPricePerToken = cacheWrite1hPricePerToken
    }
}
