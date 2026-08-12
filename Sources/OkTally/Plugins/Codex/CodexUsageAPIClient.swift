// Sources/OkTally/Plugins/Codex/CodexUsageAPIClient.swift
import Foundation

/// One rate-limit window from wham/usage. `limitWindowSeconds` says whether it's a 5h
/// (18000) or weekly (604800) window; `reset_at` is epoch seconds.
struct CodexRateLimitWindow: Equatable {
    let usedPercent: Double
    let limitWindowSeconds: Int?
    let resetAt: Date?

    init(usedPercent: Double, limitWindowSeconds: Int? = nil, resetAt: Date?) {
        self.usedPercent = usedPercent
        self.limitWindowSeconds = limitWindowSeconds
        self.resetAt = resetAt
    }
}

extension CodexRateLimitWindow: Codable {
    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAt = "reset_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        usedPercent = try c.decode(Double.self, forKey: .usedPercent)
        limitWindowSeconds = try c.decodeIfPresent(Int.self, forKey: .limitWindowSeconds)
        // `reset_at` is epoch seconds here, but tolerate millis / ISO strings too.
        if let epoch = try? c.decode(Double.self, forKey: .resetAt) {
            resetAt = epoch > 1_000_000_000_000 ? Date(timeIntervalSince1970: epoch / 1000)
                                                : Date(timeIntervalSince1970: epoch)
        } else if let iso = try? c.decode(String.self, forKey: .resetAt) {
            resetAt = ISO8601DateFormatter().date(from: iso)
        } else {
            resetAt = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(usedPercent, forKey: .usedPercent)
        try c.encodeIfPresent(limitWindowSeconds, forKey: .limitWindowSeconds)
        try c.encodeIfPresent(resetAt.map { $0.timeIntervalSince1970 }, forKey: .resetAt)
    }
}

struct CodexRateLimit: Codable, Equatable {
    let primaryWindow: CodexRateLimitWindow?
    let secondaryWindow: CodexRateLimitWindow?

    enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

/// A named extra limit (e.g. "GPT-5.3-Codex-Spark") from `additional_rate_limits`.
struct CodexAdditionalLimit: Codable, Equatable {
    let limitName: String?
    let rateLimit: CodexRateLimit?

    enum CodingKeys: String, CodingKey {
        case limitName = "limit_name"
        case rateLimit = "rate_limit"
    }
}

struct CodexUsageResponse: Codable, Equatable {
    let planType: String?
    let rateLimit: CodexRateLimit?
    let additionalRateLimits: [CodexAdditionalLimit]?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case additionalRateLimits = "additional_rate_limits"
    }

    init(planType: String?, rateLimit: CodexRateLimit?, additionalRateLimits: [CodexAdditionalLimit]? = nil) {
        self.planType = planType
        self.rateLimit = rateLimit
        self.additionalRateLimits = additionalRateLimits
    }
}

enum CodexUsageError: Error, LocalizedError {
    case badResponse(Int?)
    var errorDescription: String? {
        switch self {
        case .badResponse(let code):
            return LF("Codex respondeu com erro (código %@).", code.map(String.init) ?? L("desconhecido"))
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
        do {
            return try JSONDecoder().decode(CodexUsageResponse.self, from: data)
        } catch {
            // Undocumented schema — on drift, dump the raw body (no credentials in a usage
            // response) so the real shape can be inspected, then rethrow.
            let dir = NSHomeDirectory() + "/Library/Application Support/OkTally"
            try? data.write(to: URL(fileURLWithPath: dir + "/codex-usage-debug.json"))
            throw error
        }
    }
}
