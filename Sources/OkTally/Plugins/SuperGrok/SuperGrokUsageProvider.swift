// Sources/OkTally/Plugins/SuperGrok/SuperGrokUsageProvider.swift
import Foundation

/// SuperGrok (xAI Grok Build / coding-agent) plugin.
///
/// Investigation-gate outcome: **Path A**. The literal OAuth `client_id`
/// research left as an open question was found in two independent,
/// working open-source OAuth client implementations — not reverse-engineered
/// or invented here. See docs/superpowers/research/plan2-supergrok.md,
/// "Implementation pin" section, for the full citation trail.
///
/// Login uses the OAuth 2.0 Device Authorization Grant (RFC 8628) against
/// `auth.x.ai` (`DeviceCodeFlow` + `SuperGrokOAuth.config`); ongoing refresh
/// reuses `OAuthManager`'s standard `refresh_token` grant. Usage comes from
/// the unofficial `cli-chat-proxy.grok.com/v1/billing?format=credits`
/// endpoint (`SuperGrokAPIClient`), which reports the Grok Build weekly
/// credit pool as a percentage (`creditUsagePercent`), mapped here to
/// `rollingWindow("weekly", used: percent, limit: 100)`.
final class SuperGrokUsageProvider: UsageProvider {
    let id = SuperGrokOAuth.providerId
    let displayName = "SuperGrok"
    let authMethod: AuthMethod = .oauthSession
    let refreshInterval: TimeInterval = 300

    private let oauthManager: OAuthManaging
    private let tokenStore: TokenStoring
    private let apiClient: SuperGrokUsageFetching
    private let now: () -> Date

    init(
        oauthManager: OAuthManaging,
        tokenStore: TokenStoring,
        apiClient: SuperGrokUsageFetching = SuperGrokAPIClient(),
        now: @escaping () -> Date = Date.init
    ) {
        self.oauthManager = oauthManager
        self.tokenStore = tokenStore
        self.apiClient = apiClient
        self.now = now
    }

    func isAuthenticated() async -> Bool {
        tokenStore.load(providerId: id) != nil
    }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        let accessToken = try await oauthManager.validAccessToken(providerId: id, config: SuperGrokOAuth.refreshConfig)
        let usage = try await apiClient.fetchUsage(accessToken: accessToken)

        // Proto/JSON on the xAI side omits `creditUsagePercent` at 0% usage
        // rather than sending an explicit 0 (documented behavior per the
        // research); an absent value means 0%, not "unknown".
        let usedPercent = usage.creditUsagePercent ?? 0
        let resetAt = usage.resetAt ?? now()
        let windowStart = resetAt.addingTimeInterval(-7 * 24 * 3600)

        let window = QuotaWindow(
            label: "weekly",
            shape: .rollingWindow(used: usedPercent, limit: 100, windowStart: windowStart, resetAt: resetAt),
            renewalCadence: .weekly
        )
        return ProviderSnapshot(providerId: id, fetchedAt: now(), quotas: [window], usageDetail: nil)
    }
}
