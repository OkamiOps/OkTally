import Foundation

final class ClaudeUsageProvider: UsageProvider {
    let id = "claude"
    let displayName = "Claude Code"
    let authMethod: AuthMethod = .keychain(service: "Claude Code-credentials")
    let refreshInterval: TimeInterval = 60

    private let credentialProvider: ClaudeCredentialProvider
    private let apiClient: ClaudeUsageFetching

    init(
        credentialProvider: ClaudeCredentialProvider = ClaudeCredentialProvider(),
        apiClient: ClaudeUsageFetching = ClaudeUsageAPIClient()
    ) {
        self.credentialProvider = credentialProvider
        self.apiClient = apiClient
    }

    func isAuthenticated() async -> Bool {
        (try? credentialProvider.loadCredentials()) != nil
    }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        let credentials = try credentialProvider.loadCredentials()
        let usage = try await apiClient.fetchUsage(accessToken: credentials.accessToken)

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
