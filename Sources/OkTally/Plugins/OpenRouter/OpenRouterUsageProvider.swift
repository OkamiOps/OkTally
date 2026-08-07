// Sources/OkTally/Plugins/OpenRouter/OpenRouterUsageProvider.swift
import Foundation

final class OpenRouterUsageProvider: UsageProvider {
    let id = "openrouter"
    let displayName = "OpenRouter"
    let authMethod: AuthMethod = .apiKey
    let refreshInterval: TimeInterval = 600

    private let apiKeyProvider: () -> String?
    private let creditsClient: OpenRouterCreditsFetching

    init(apiKeyProvider: @escaping () -> String?, creditsClient: OpenRouterCreditsFetching = OpenRouterAPIClient()) {
        self.apiKeyProvider = apiKeyProvider
        self.creditsClient = creditsClient
    }

    func isAuthenticated() async -> Bool {
        apiKeyProvider() != nil
    }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        guard let apiKey = apiKeyProvider() else { throw OpenRouterError.missingAPIKey }
        let response = try await creditsClient.fetchCredits(apiKey: apiKey)
        let remaining = Decimal(response.data.totalCredits - response.data.totalUsage)
        let window = QuotaWindow(label: "balance", shape: .creditBalance(remaining: remaining, currency: "USD"))
        return ProviderSnapshot(providerId: id, fetchedAt: Date(), quotas: [window], usageDetail: nil)
    }
}
