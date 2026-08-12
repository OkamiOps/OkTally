// Sources/OkTally/Plugins/OpenRouter/OpenRouterAPIClient.swift
import Foundation

struct OpenRouterCreditsResponse: Codable, Equatable {
    struct DataField: Codable, Equatable {
        let totalCredits: Decimal
        let totalUsage: Decimal
        enum CodingKeys: String, CodingKey {
            case totalCredits = "total_credits"
            case totalUsage = "total_usage"
        }
    }
    let data: DataField
}

protocol OpenRouterCreditsFetching {
    func fetchCredits(apiKey: String) async throws -> OpenRouterCreditsResponse
}

enum OpenRouterError: Error, Equatable {
    case badResponse(Int?)
    case missingAPIKey
}

extension OpenRouterError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return L("Configure sua chave de API do OpenRouter nas Preferências.")
        case .badResponse(let statusCode):
            return LF("OpenRouter respondeu com erro (código %@).", statusCode.map(String.init) ?? L("desconhecido"))
        }
    }
}

final class OpenRouterAPIClient: OpenRouterCreditsFetching {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func fetchCredits(apiKey: String) async throws -> OpenRouterCreditsResponse {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/credits")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw OpenRouterError.badResponse((response as? HTTPURLResponse)?.statusCode)
        }
        return try JSONDecoder().decode(OpenRouterCreditsResponse.self, from: data)
    }
}
