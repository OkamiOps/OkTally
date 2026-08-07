// Sources/OkTally/Plugins/Codex/CodexUsageAPIClient.swift
import Foundation

struct CodexRateLimitWindow: Codable, Equatable {
    let usedPercent: Double
    let resetAt: Date?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case resetAt = "reset_at"
    }
}

struct CodexUsageResponse: Equatable {
    let planType: String?
    let primaryWindow: CodexRateLimitWindow?
    let secondaryWindow: CodexRateLimitWindow?
}

extension CodexUsageResponse: Codable {
    private enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
    }
    private enum RateLimitKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        planType = try container.decodeIfPresent(String.self, forKey: .planType)
        if let rateLimit = try? container.nestedContainer(keyedBy: RateLimitKeys.self, forKey: .rateLimit) {
            primaryWindow = try rateLimit.decodeIfPresent(CodexRateLimitWindow.self, forKey: .primaryWindow)
            secondaryWindow = try rateLimit.decodeIfPresent(CodexRateLimitWindow.self, forKey: .secondaryWindow)
        } else {
            primaryWindow = nil
            secondaryWindow = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(planType, forKey: .planType)
        var rateLimit = container.nestedContainer(keyedBy: RateLimitKeys.self, forKey: .rateLimit)
        try rateLimit.encodeIfPresent(primaryWindow, forKey: .primaryWindow)
        try rateLimit.encodeIfPresent(secondaryWindow, forKey: .secondaryWindow)
    }
}

enum CodexUsageError: Error, LocalizedError {
    case badResponse(Int?)
    var errorDescription: String? {
        switch self {
        case .badResponse(let code):
            return "Codex respondeu com erro (código \(code.map(String.init) ?? "desconhecido"))."
        }
    }
}

protocol CodexUsageFetching {
    func fetchUsage(accessToken: String, accountId: String?) async throws -> CodexUsageResponse
}

final class CodexUsageAPIClient: CodexUsageFetching {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func fetchUsage(accessToken: String, accountId: String?) async throws -> CodexUsageResponse {
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let accountId {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CodexUsageError.badResponse((response as? HTTPURLResponse)?.statusCode)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CodexUsageResponse.self, from: data)
    }
}
