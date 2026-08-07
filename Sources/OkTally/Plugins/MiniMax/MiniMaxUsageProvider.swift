// Sources/OkTally/Plugins/MiniMax/MiniMaxUsageProvider.swift
import Foundation

final class MiniMaxUsageProvider: UsageProvider {
    let id = "minimax"
    let displayName = "MiniMax"
    let authMethod: AuthMethod = .apiKey
    let refreshInterval: TimeInterval = 300

    private let apiKeyProvider: () -> String?
    private let region: () -> MiniMaxRegion
    private let client: MiniMaxRemainsFetching

    init(
        apiKeyProvider: @escaping () -> String?,
        region: @escaping () -> MiniMaxRegion,
        client: MiniMaxRemainsFetching = MiniMaxAPIClient()
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.region = region
        self.client = client
    }

    func isAuthenticated() async -> Bool {
        apiKeyProvider() != nil
    }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        guard let apiKey = apiKeyProvider() else { throw MiniMaxError.missingAPIKey }
        let response = try await client.fetchRemains(apiKey: apiKey, region: region())

        // Worst-case-wins across models: for each label (5h / weekly), keep the window with
        // the highest usedPercent. A model with total_count == 0 ("not entitled", per the
        // research report's video-quota 0/0 edge case) produces usedPercent == nil via
        // QuotaShape's own limit > 0 guard, so it never wins over a real quota window.
        var bestFiveHour: QuotaShape?
        var bestWeekly: QuotaShape?

        for model in response.models {
            let resetAt = Date().addingTimeInterval(TimeInterval(model.remainsTime) / 1000)

            let fiveHour = QuotaShape.rollingWindow(
                used: Double(model.currentIntervalUsageCount),
                limit: Double(model.currentIntervalTotalCount),
                windowStart: resetAt.addingTimeInterval(-5 * 3600),
                resetAt: resetAt
            )
            if (fiveHour.usedPercent ?? -1) > (bestFiveHour?.usedPercent ?? -1) {
                bestFiveHour = fiveHour
            }

            let weekly = QuotaShape.periodicCounter(
                used: Double(model.currentWeeklyUsageCount),
                limit: Double(model.currentWeeklyTotalCount),
                resetAt: resetAt
            )
            if (weekly.usedPercent ?? -1) > (bestWeekly?.usedPercent ?? -1) {
                bestWeekly = weekly
            }
        }

        var quotas: [QuotaWindow] = []
        if let bestFiveHour { quotas.append(QuotaWindow(label: "5h", shape: bestFiveHour)) }
        if let bestWeekly { quotas.append(QuotaWindow(label: "weekly", shape: bestWeekly)) }

        return ProviderSnapshot(providerId: id, fetchedAt: Date(), quotas: quotas, usageDetail: nil)
    }
}
