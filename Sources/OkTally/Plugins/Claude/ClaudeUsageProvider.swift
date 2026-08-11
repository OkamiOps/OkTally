import Foundation

final class ClaudeUsageProvider: UsageProvider {
    let id = "claude"
    let displayName = "Claude Code"
    let authMethod: AuthMethod = .oauthSession
    // api.anthropic.com/api/oauth/usage rate-limits aggressively (429) — it tolerates
    // roughly one call per few minutes, so poll every 5 minutes, not every 60s.
    let refreshInterval: TimeInterval = 300

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

        let now = Date()
        var quotas = [
            QuotaWindow(label: "5h", shape: Self.shape(for: usage.fiveHour, windowLength: 5 * 3600, now: now)),
            QuotaWindow(label: "weekly", shape: Self.shape(for: usage.sevenDay, windowLength: 7 * 24 * 3600, now: now))
        ]
        if let opus = usage.sevenDayOpus {
            quotas.append(QuotaWindow(label: "weekly-opus", shape: Self.shape(for: opus, windowLength: 7 * 24 * 3600, now: now)))
        }
        return ProviderSnapshot(providerId: id, fetchedAt: now, quotas: quotas, usageDetail: nil)
    }

    /// The API reports `resets_at: null` for a window that is idle (just reset, or never
    /// used this cycle). That still deserves a card line — it's exactly the "back to
    /// 100%" moment the owner wants to see — so anchor the synthetic window at `now`:
    /// `resetAt = now` sits in the past by render time, which the UI already treats as
    /// "no countdown to show", rather than fabricating a fake future reset.
    private static func shape(for window: ClaudeUsageWindow, windowLength: TimeInterval, now: Date) -> QuotaShape {
        let resetAt = window.resetsAt ?? now
        return .rollingWindow(
            used: window.utilization, limit: 100,
            windowStart: resetAt.addingTimeInterval(-windowLength),
            resetAt: resetAt
        )
    }
}
