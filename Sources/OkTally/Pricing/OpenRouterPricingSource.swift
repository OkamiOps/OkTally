import Foundation

protocol PricingSource {
    func fetchModelPricing() async throws -> [ModelPricing]
}

enum PricingSourceError: Error {
    case badResponse(Int?)
}

private struct OpenRouterModelsResponse: Codable {
    struct Model: Codable {
        struct Pricing: Codable {
            let prompt: String
            let completion: String
            let inputCacheRead: String?
            let inputCacheWrite: String?
            let inputCacheWrite1h: String?

            enum CodingKeys: String, CodingKey {
                case prompt, completion
                case inputCacheRead = "input_cache_read"
                case inputCacheWrite = "input_cache_write"
                case inputCacheWrite1h = "input_cache_write_1h"
            }
        }
        let id: String
        let pricing: Pricing
    }
    let data: [Model]
}

final class OpenRouterPricingSource: PricingSource {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func fetchModelPricing() async throws -> [ModelPricing] {
        let url = URL(string: "https://openrouter.ai/api/v1/models")!
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw PricingSourceError.badResponse((response as? HTTPURLResponse)?.statusCode)
        }
        let decoded = try JSONDecoder().decode(OpenRouterModelsResponse.self, from: data)
        return decoded.data.compactMap { model -> ModelPricing? in
            guard let prompt = Decimal(string: model.pricing.prompt),
                  let completion = Decimal(string: model.pricing.completion) else { return nil }
            return ModelPricing(
                modelId: model.id,
                promptPricePerToken: prompt,
                completionPricePerToken: completion,
                cacheReadPricePerToken: model.pricing.inputCacheRead.flatMap { Decimal(string: $0) },
                cacheWritePricePerToken: model.pricing.inputCacheWrite.flatMap { Decimal(string: $0) },
                cacheWrite1hPricePerToken: model.pricing.inputCacheWrite1h.flatMap { Decimal(string: $0) }
            )
        }
    }
}
