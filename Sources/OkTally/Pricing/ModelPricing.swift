import Foundation

struct ModelPricing: Equatable {
    let modelId: String
    let promptPricePerToken: Decimal
    let completionPricePerToken: Decimal
}
