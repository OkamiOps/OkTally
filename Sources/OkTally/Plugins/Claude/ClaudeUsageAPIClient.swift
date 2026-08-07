import Foundation

struct ClaudeUsageWindow: Codable, Equatable {
    let utilization: Double
    let resetsAt: Date

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

struct ClaudeUsageResponse: Codable, Equatable {
    let fiveHour: ClaudeUsageWindow
    let sevenDay: ClaudeUsageWindow
    let sevenDayOpus: ClaudeUsageWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
    }
}

protocol ClaudeUsageFetching {
    func fetchUsage(accessToken: String) async throws -> ClaudeUsageResponse
}

enum ClaudeUsageError: Error {
    case badResponse(Int?)
}

extension ClaudeUsageError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .badResponse(let statusCode):
            return "Claude respondeu com erro (código \(statusCode.map(String.init) ?? "desconhecido"))."
        }
    }
}

final class ClaudeUsageAPIClient: ClaudeUsageFetching {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func fetchUsage(accessToken: String) async throws -> ClaudeUsageResponse {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("Claude-Code/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ClaudeUsageError.badResponse((response as? HTTPURLResponse)?.statusCode)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ClaudeUsageResponse.self, from: data)
    }
}
