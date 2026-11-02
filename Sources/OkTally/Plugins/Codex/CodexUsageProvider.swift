// Sources/OkTally/Plugins/Codex/CodexUsageProvider.swift
import Foundation

final class CodexUsageProvider: UsageProvider {
    let id: String
    let displayName = "Codex"
    let authMethod: AuthMethod = .oauthSession
    let refreshInterval: TimeInterval = 300

    private let oauthManager: OAuthManaging
    private let tokenStore: TokenStoring
    private let apiClient: CodexUsageFetching
    /// `nil` in tests. Production reads `~/.codex/auth.json` only after the stored session fails.
    private let cliAuthFile: URL?

    init(
        instanceId: String = AccountKind.codex.rawValue,
        oauthManager: OAuthManaging,
        tokenStore: TokenStoring,
        apiClient: CodexUsageFetching = CodexUsageAPIClient(),
        cliAuthFile: URL? = CodexCLIAuth.defaultURL
    ) {
        self.id = instanceId
        self.oauthManager = oauthManager
        self.tokenStore = tokenStore
        self.apiClient = apiClient
        self.cliAuthFile = cliAuthFile
    }

    func isAuthenticated() async -> Bool {
        tokenStore.load(providerId: id) != nil
    }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        let stored = tokenStore.load(providerId: id)
        let accountId = stored?.extra["account_id"] ?? CodexCLIAuth.accountId(from: stored?.accessToken)
        let email = stored.map { AccountEmailResolver.codexEmail(accessToken: $0.accessToken, extra: $0.extra) } ?? nil
        let usage: CodexUsageResponse
        do {
            usage = try await fetchUsingStoredSession(accountId: accountId)
        } catch {
            // The stored ChatGPT session can die (expired access token the refresh
            // endpoint rejects, or a 401 that never rotates it) while the Codex CLI on
            // this Mac still holds a working login for the same account. Without this,
            // the menu bar keeps the last good percent for hours and looks frozen.
            guard let fallback = await usageFromMatchingCLI(accountId: accountId, email: email) else {
                throw error
            }
            usage = fallback
        }

        var quotas: [QuotaWindow] = []
        // General plan limits (each window labelled by its real duration, not assumed).
        appendWindow(usage.rateLimit?.primaryWindow, defaultLabel: nil, into: &quotas)
        appendWindow(usage.rateLimit?.secondaryWindow, defaultLabel: nil, into: &quotas)
        // Per-feature limits like "GPT-5.3-Codex-Spark" — labelled by their name.
        for extra in usage.additionalRateLimits ?? [] {
            appendWindow(extra.rateLimit?.primaryWindow, defaultLabel: extra.limitName, into: &quotas)
            appendWindow(extra.rateLimit?.secondaryWindow, defaultLabel: extra.limitName, into: &quotas)
        }
        return ProviderSnapshot(
            providerId: id,
            fetchedAt: Date(),
            quotas: quotas,
            usageDetail: nil,
            planLabel: usage.planType.map(Self.planDisplayName)
        )
    }

    /// Stored-session read. A 401/403 retries once after a refresh: the access token can
    /// be rejected before `expiresAt`, and the scheduler would otherwise repeat the dead
    /// token until that date.
    private func fetchUsingStoredSession(accountId: String?) async throws -> CodexUsageResponse {
        let config = CodexOAuth.config.forInstance(id)
        let accessToken = try await oauthManager.validAccessToken(providerId: id, config: config)
        do {
            return try await apiClient.fetchUsage(accessToken: accessToken, accountId: accountId)
        } catch CodexUsageError.badResponse(let code) where code == 401 || code == 403 {
            let refreshed = try await oauthManager.refresh(providerId: id, config: config)
            let refreshedAccount = refreshed.extra["account_id"] ?? accountId
            return try await apiClient.fetchUsage(accessToken: refreshed.accessToken, accountId: refreshedAccount)
        }
    }

    private func usageFromMatchingCLI(accountId: String?, email: String?) async -> CodexUsageResponse? {
        guard let cliAuthFile, let cli = CodexCLIAuth.load(from: cliAuthFile),
              CodexCLIAuth.matches(cli, accountId: accountId, email: email)
        else { return nil }
        return try? await apiClient.fetchUsage(accessToken: cli.accessToken, accountId: cli.accountId ?? accountId)
    }

    /// "pro" → "Pro", "plus" → "Plus"; valores compostos ("chatgpt_team") viram a última
    /// palavra capitalizada.
    static func planDisplayName(_ raw: String) -> String {
        let last = raw.split(separator: "_").last.map(String.init) ?? raw
        return last.prefix(1).uppercased() + last.dropFirst()
    }

    /// Appends one rate-limit window as a rolling-window quota. The label is the feature
    /// name when given (e.g. "GPT-5.3-Codex-Spark"), otherwise derived from the window's
    /// real duration (`limit_window_seconds`) so a weekly window is never mislabelled "5h".
    private func appendWindow(_ window: CodexRateLimitWindow?, defaultLabel: String?, into quotas: inout [QuotaWindow]) {
        guard let window else { return }
        let seconds = window.limitWindowSeconds
        let durationLabel = Self.label(forWindowSeconds: seconds)
        let label: String
        if let name = defaultLabel {
            label = durationLabel.map { "\(name) (\($0))" } ?? name
        } else {
            label = durationLabel ?? "uso"
        }
        let windowSpan = TimeInterval(seconds ?? 0)
        let resetAt = window.resetAt ?? Date()
        quotas.append(QuotaWindow(label: label, shape: .rollingWindow(
            used: window.usedPercent, limit: 100,
            windowStart: resetAt.addingTimeInterval(-windowSpan),
            resetAt: resetAt
        ), renewalCadence: seconds == 604800 ? .weekly : nil))
    }

    private static func label(forWindowSeconds seconds: Int?) -> String? {
        switch seconds {
        case 18000: return "5h"
        case 604800: return "semanal"
        case let s? where s % 86400 == 0: return "\(s / 86400)d"
        case let s? where s % 3600 == 0: return "\(s / 3600)h"
        default: return nil
        }
    }
}
