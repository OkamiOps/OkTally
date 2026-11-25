import Foundation

struct GrokBotUsageResponse: Equatable {
    let usagePercent: Double
    let nextResetTimestampUtc: String?
    let hasNonZeroIncludedLimit: Bool?
    let hasAvailableUsage: Bool?
    let grokPlanLabel: String?

    init(usagePercent: Double, nextResetTimestampUtc: String?, hasNonZeroIncludedLimit: Bool?, hasAvailableUsage: Bool?, grokPlanLabel: String?) {
        self.usagePercent = usagePercent
        self.nextResetTimestampUtc = nextResetTimestampUtc
        self.hasNonZeroIncludedLimit = hasNonZeroIncludedLimit
        self.hasAvailableUsage = hasAvailableUsage
        self.grokPlanLabel = grokPlanLabel
    }

    /// Mesmo motivo do Cursor: `GetSandUsageStatus` é interno e sem contrato estável.
    /// Aceita percentual usado direto ou deriva de uma fração restante futura.
    init(data: Data) throws {
        guard let root = TolerantJSON.object(data: data) else { throw ProviderAPIError.malformedResponse("GrokBot") }
        let direct = TolerantJSON.number(in: root, camel: "usagePercent")
            ?? TolerantJSON.number(in: root, camel: "percentUsed")
            ?? TolerantJSON.number(in: root, camel: "totalPercentUsed")
        let derived = TolerantJSON.number(in: root, camel: "remainingFraction")
            .map { (1 - $0) * 100 }
        guard let usagePercent = direct ?? derived else { throw ProviderAPIError.malformedResponse("GrokBot") }
        self.usagePercent = usagePercent
        self.nextResetTimestampUtc = TolerantJSON.string(in: root, camel: "nextResetTimestampUtc")
            ?? TolerantJSON.string(in: root, camel: "resetTime")
            ?? TolerantJSON.string(in: root, camel: "resetAt")
        self.hasNonZeroIncludedLimit = TolerantJSON.bool(TolerantJSON.value(in: root, camel: "hasNonZeroIncludedLimit"))
        self.hasAvailableUsage = TolerantJSON.bool(TolerantJSON.value(in: root, camel: "hasAvailableUsage"))
        self.grokPlanLabel = TolerantJSON.string(in: root, camel: "grokPlanLabel")
    }
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
        return try GrokBotUsageResponse(data: data)
    }
}

final class GrokBotUsageProvider: UsageProvider {
    let id: String
    let displayName = "GrokBot"
    let authMethod: AuthMethod = .localFile(
        path: NSHomeDirectory() + "/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
    )
    let refreshInterval: TimeInterval = 600

    private let tokenReader: CursorTokenReading
    private let client: GrokBotUsageFetching
    private let now: () -> Date

    init(
        instanceId: String = AccountKind.grokbot.rawValue,
        tokenReader: CursorTokenReading = CursorTokenReader(),
        client: GrokBotUsageFetching = GrokBotUsageAPIClient(),
        now: @escaping () -> Date = Date.init
    ) {
        self.id = instanceId
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
            // Sessão própria vencida pede "Reconectar"; a do IDE indisponível é passageira.
            throw tokenReader.unavailableError() ?? GrokBotUsageError.cursorSessionUnavailable
        }
        let response = try await client.fetchUsage(accessToken: token)
        let fetchedAt = now()
        let resetAt = response.nextResetTimestampUtc.flatMap(Self.parseISO8601) ?? fetchedAt

        return ProviderSnapshot(
            providerId: id,
            fetchedAt: fetchedAt,
            quotas: [QuotaWindow(
                label: "weekly",
                shape: .periodicCounter(
                    used: response.usagePercent,
                    limit: 100,
                    resetAt: resetAt
                ),
                renewalCadence: .weekly
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
