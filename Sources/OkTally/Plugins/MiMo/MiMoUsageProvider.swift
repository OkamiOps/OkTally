// Sources/OkTally/Plugins/MiMo/MiMoUsageProvider.swift
import Foundation

/// Xiaomi MiMo Token Plan plugin.
///
/// MiMo has no API-key route to quota — the console's "Plan usage" bar comes from
/// `POST /api/v1/usage/token-plan/list`, gated behind the Xiaomi SSO + STS `api-platform`
/// cookie session (see `docs/superpowers/research/plan2-mimo.md`). The only way to read it
/// programmatically is from inside that session, so this plugin fetches through the shared
/// `MiMoWebSession` web view where the user logged in. Falls back to the manual estimate
/// when there's no session.
final class MiMoUsageProvider: UsageProvider {
    let id = "mimo"
    let displayName = "MiMo"
    let authMethod: AuthMethod = .oauthSession
    let refreshInterval: TimeInterval = 600

    private let sessionStore: MiMoSessionStoring
    private let usageFetcher: MiMoUsageFetching?
    private let allowanceProvider: () -> Double?
    private let usedCreditsProvider: () -> Double
    private let now: () -> Date

    init(
        sessionStore: MiMoSessionStoring,
        usageFetcher: MiMoUsageFetching? = nil,
        allowanceProvider: @escaping () -> Double?,
        usedCreditsProvider: @escaping () -> Double,
        now: @escaping () -> Date = Date.init
    ) {
        self.sessionStore = sessionStore
        self.usageFetcher = usageFetcher
        self.allowanceProvider = allowanceProvider
        self.usedCreditsProvider = usedCreditsProvider
        self.now = now
    }

    func isAuthenticated() async -> Bool {
        sessionStore.isLoggedIn || allowanceProvider() != nil
    }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        if sessionStore.isLoggedIn, let usageFetcher {
            do {
                return try await liveSnapshot(usageFetcher: usageFetcher)
            } catch MiMoConsoleError.notLoggedIn {
                sessionStore.isLoggedIn = false // prompt re-login; fall back to manual
            }
        }
        return manualSnapshot()
    }

    private func liveSnapshot(usageFetcher: MiMoUsageFetching) async throws -> ProviderSnapshot {
        let data = try await usageFetcher.fetchUsageJSON()
        if let text = String(data: data, encoding: .utf8), text.contains("\"code\":401") {
            throw MiMoConsoleError.notLoggedIn
        }
        let resp = try JSONDecoder().decode(MiMoUsageResponse.self, from: data)
        // `percent` is a fraction (0.0622 == 6.22%), so ×100 for a 0–100 rolling window.
        var quotas: [QuotaWindow] = []
        if let month = resp.data?.monthUsage?.percent {
            quotas.append(QuotaWindow(label: "mensal", shape: .rollingWindow(
                used: month * 100, limit: 100, windowStart: now(), resetAt: now())))
        }
        if let plan = resp.data?.usage?.percent {
            quotas.append(QuotaWindow(label: "plano", shape: .rollingWindow(
                used: plan * 100, limit: 100, windowStart: now(), resetAt: now())))
        }
        return ProviderSnapshot(providerId: id, fetchedAt: now(), quotas: quotas, usageDetail: nil)
    }

    private func manualSnapshot() -> ProviderSnapshot {
        let shape = QuotaShape.estimated(
            used: usedCreditsProvider(), limit: allowanceProvider(),
            basis: .localTokenCount, resetAt: nil
        )
        return ProviderSnapshot(providerId: id, fetchedAt: now(), quotas: [QuotaWindow(label: "mensal", shape: shape)], usageDetail: nil)
    }
}
