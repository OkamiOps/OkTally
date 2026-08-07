import Foundation

final class ClaudeUsageProvider: UsageProvider {
    let id = "claude"
    let displayName = "Claude Code"
    let authMethod: AuthMethod = .oauthSession
    let refreshInterval: TimeInterval = 60

    private let oauthManager: OAuthManaging
    private let tokenStore: TokenStoring
    private let apiClient: ClaudeUsageFetching
    private let legacyCredentialProvider: ClaudeCredentialProvider?

    init(
        oauthManager: OAuthManaging,
        tokenStore: TokenStoring,
        apiClient: ClaudeUsageFetching = ClaudeUsageAPIClient(),
        legacyCredentialProvider: ClaudeCredentialProvider? = ClaudeCredentialProvider()
    ) {
        self.oauthManager = oauthManager
        self.tokenStore = tokenStore
        self.apiClient = apiClient
        self.legacyCredentialProvider = legacyCredentialProvider
    }

    func isAuthenticated() async -> Bool {
        tokenStore.load(providerId: id) != nil
    }

    @discardableResult
    func importLegacyCredentialsIfAvailable() -> Bool {
        guard tokenStore.load(providerId: id) == nil,
              let credentials = try? legacyCredentialProvider?.loadCredentials() else { return false }
        let token = OAuthToken(
            accessToken: credentials.accessToken,
            refreshToken: credentials.refreshToken,
            expiresAt: credentials.expiresAt,
            extra: [:]
        )
        return (try? tokenStore.save(token, providerId: id)) != nil
    }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        let accessToken = try await oauthManager.validAccessToken(providerId: id, config: ClaudeOAuth.config)
        let usage = try await apiClient.fetchUsage(accessToken: accessToken)

        var quotas = [
            QuotaWindow(label: "5h", shape: .rollingWindow(
                used: usage.fiveHour.utilization, limit: 100,
                windowStart: usage.fiveHour.resetsAt.addingTimeInterval(-5 * 3600),
                resetAt: usage.fiveHour.resetsAt
            )),
            QuotaWindow(label: "weekly", shape: .rollingWindow(
                used: usage.sevenDay.utilization, limit: 100,
                windowStart: usage.sevenDay.resetsAt.addingTimeInterval(-7 * 24 * 3600),
                resetAt: usage.sevenDay.resetsAt
            ))
        ]
        if let opus = usage.sevenDayOpus {
            quotas.append(QuotaWindow(label: "weekly-opus", shape: .rollingWindow(
                used: opus.utilization, limit: 100,
                windowStart: opus.resetsAt.addingTimeInterval(-7 * 24 * 3600),
                resetAt: opus.resetsAt
            )))
        }
        return ProviderSnapshot(providerId: id, fetchedAt: Date(), quotas: quotas, usageDetail: nil)
    }
}
