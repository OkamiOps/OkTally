// Sources/OkTally/Plugins/Codex/CodexUsageProvider.swift
import Foundation

final class CodexUsageProvider: UsageProvider {
    let id = "codex"
    let displayName = "Codex"
    let authMethod: AuthMethod = .oauthSession
    let refreshInterval: TimeInterval = 300

    private let oauthManager: OAuthManaging
    private let tokenStore: TokenStoring
    private let apiClient: CodexUsageFetching

    init(oauthManager: OAuthManaging, tokenStore: TokenStoring, apiClient: CodexUsageFetching = CodexUsageAPIClient()) {
        self.oauthManager = oauthManager
        self.tokenStore = tokenStore
        self.apiClient = apiClient
    }

    func isAuthenticated() async -> Bool {
        tokenStore.load(providerId: id) != nil
    }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        let accessToken = try await oauthManager.validAccessToken(providerId: id, config: CodexOAuth.config)
        let accountId = tokenStore.load(providerId: id)?.extra["account_id"]
        let usage = try await apiClient.fetchUsage(accessToken: accessToken, accountId: accountId)

        var quotas: [QuotaWindow] = []
        if let primary = usage.primaryWindow {
            quotas.append(QuotaWindow(label: "5h", shape: .rollingWindow(
                used: primary.usedPercent, limit: 100,
                windowStart: (primary.resetAt ?? Date()).addingTimeInterval(-5 * 3600),
                resetAt: primary.resetAt ?? Date()
            )))
        }
        if let secondary = usage.secondaryWindow {
            quotas.append(QuotaWindow(label: "weekly", shape: .rollingWindow(
                used: secondary.usedPercent, limit: 100,
                windowStart: (secondary.resetAt ?? Date()).addingTimeInterval(-7 * 24 * 3600),
                resetAt: secondary.resetAt ?? Date()
            )))
        }
        return ProviderSnapshot(providerId: id, fetchedAt: Date(), quotas: quotas, usageDetail: nil)
    }
}
