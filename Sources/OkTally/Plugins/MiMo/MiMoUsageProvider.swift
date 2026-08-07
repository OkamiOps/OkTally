// Sources/OkTally/Plugins/MiMo/MiMoUsageProvider.swift
import Foundation

/// Xiaomi MiMo Token Plan plugin.
///
/// Confirmed by reading the source of MiMo's own official CLI (`XiaomiMiMo/MiMo-Code`)
/// and OpenClaw's Xiaomi provider plugin (see
/// `docs/superpowers/research/plan2-mimo.md`): there is no API-key-authenticated route
/// that returns quota/usage data. The console's usage pages are gated behind a separate
/// cookie-session SSO (`account.xiaomi.com`) that only the website itself can use, and
/// the inference gateway explicitly scrubs every response header except `content-type`
/// and `cache-control` — so there is nothing to fetch over the network, not even a
/// rate-limit header to infer from.
///
/// Instead this plugin renders a manually-maintained estimate: the owner enters their
/// monthly Token Plan allowance (in Credits) and keeps the used-Credits figure updated
/// in Preferences. Automatic usage accumulation (e.g. via traffic observation) is out of
/// scope until a proxy/observer design exists.
final class MiMoUsageProvider: UsageProvider {
    let id = "mimo"
    let displayName = "MiMo"
    let authMethod: AuthMethod = .apiKey
    let refreshInterval: TimeInterval = 3600

    private let allowanceProvider: () -> Double?
    private let usedCreditsProvider: () -> Double
    private let now: () -> Date

    init(
        allowanceProvider: @escaping () -> Double?,
        usedCreditsProvider: @escaping () -> Double,
        now: @escaping () -> Date = Date.init
    ) {
        self.allowanceProvider = allowanceProvider
        self.usedCreditsProvider = usedCreditsProvider
        self.now = now
    }

    func isAuthenticated() async -> Bool {
        allowanceProvider() != nil
    }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        let shape = QuotaShape.estimated(
            used: usedCreditsProvider(),
            limit: allowanceProvider(),
            basis: .localTokenCount,
            // Deliberately nil: research confirms a monthly reset but not the reset
            // day (calendar month-start vs. subscription anniversary is unverified).
            // As an estimated provider, we'd rather show no reset date than assert
            // one that could be wrong.
            resetAt: nil
        )
        let window = QuotaWindow(label: "mensal", shape: shape)
        return ProviderSnapshot(providerId: id, fetchedAt: now(), quotas: [window], usageDetail: nil)
    }
}
