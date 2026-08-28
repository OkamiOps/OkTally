import Foundation

struct GrokBotUsageResponse: Codable, Equatable {
    let usagePercent: Double
    let nextResetTimestampUtc: String
    let hasNonZeroIncludedLimit: Bool
    let hasAvailableUsage: Bool
    let grokPlanLabel: String
}

protocol GrokBotUsageFetching {
    func fetchUsage(accessToken: String) async throws -> GrokBotUsageResponse
}

enum GrokBotUsageError: Error, Equatable, LocalizedError {
    case cursorSessionUnavailable

    var errorDescription: String? {
        switch self {
        case .cursorSessionUnavailable:
            return L("Sessão do Cursor temporariamente indisponível.")
        }
    }
}

final class GrokBotUsageAPIClient: GrokBotUsageFetching {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchUsage(accessToken: String) async throws -> GrokBotUsageResponse {
        var request = URLRequest(url: URL(
            string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetSandUsageStatus"
        )!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CursorUsageError.badResponse((response as? HTTPURLResponse)?.statusCode)
        }
        return try JSONDecoder().decode(GrokBotUsageResponse.self, from: data)
    }
}

final class GrokBotUsageProvider: UsageProvider {
    let id = "cursor-grokbot"
    let displayName = "GrokBot"
    let authMethod: AuthMethod = .localFile(
        path: NSHomeDirectory() + "/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
    )
    let refreshInterval: TimeInterval = 600

    private let tokenReader: CursorTokenReading
    private let client: GrokBotUsageFetching
    private let now: () -> Date

    init(
        tokenReader: CursorTokenReading = CursorTokenReader(),
        client: GrokBotUsageFetching = GrokBotUsageAPIClient(),
        now: @escaping () -> Date = Date.init
    ) {
        self.tokenReader = tokenReader
        self.client = client
        self.now = now
    }

    func isAuthenticated() async -> Bool {
        // GrokBot has no independent credential to configure. Let the fetch perform the
        // Cursor dependency check so a transient SQLite read cannot be promoted by the
        // scheduler to the misleading "not configured" state.
        true
    }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        // Cursor can be writing state.vscdb while OkTally opens its read-only queue.
        // One immediate second read avoids turning that brief race into ten minutes of
        // hidden data (this provider refreshes every 600 seconds).
        guard let token = tokenReader.readAccessToken() ?? tokenReader.readAccessToken() else {
            throw GrokBotUsageError.cursorSessionUnavailable
        }
        let response = try await client.fetchUsage(accessToken: token)
        let fetchedAt = now()
        let resetAt = Self.parseISO8601(response.nextResetTimestampUtc) ?? fetchedAt

        return ProviderSnapshot(
            providerId: id,
            fetchedAt: fetchedAt,
            quotas: [QuotaWindow(
                label: "weekly",
                shape: .periodicCounter(
                    used: response.usagePercent,
                    limit: 100,
                    resetAt: resetAt
                )
            )],
            usageDetail: nil,
            planLabel: response.grokPlanLabel
        )
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
