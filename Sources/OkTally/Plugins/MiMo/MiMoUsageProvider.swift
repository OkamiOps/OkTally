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
    private let calendar: Calendar

    init(
        allowanceProvider: @escaping () -> Double?,
        usedCreditsProvider: @escaping () -> Double,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.allowanceProvider = allowanceProvider
        self.usedCreditsProvider = usedCreditsProvider
        self.now = now
        self.calendar = calendar
    }

    func isAuthenticated() async -> Bool {
        allowanceProvider() != nil
    }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        let shape = QuotaShape.estimated(
            used: usedCreditsProvider(),
            limit: allowanceProvider(),
            basis: .localTokenCount,
            resetAt: nextMonthStart(after: now())
        )
        let window = QuotaWindow(label: "mensal", shape: shape)
        return ProviderSnapshot(providerId: id, fetchedAt: now(), quotas: [window], usageDetail: nil)
    }

    /// The first instant of the month following `date` — the monthly Token Plan reset.
    private func nextMonthStart(after date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let firstOfThisMonth = calendar.date(from: components),
              let nextMonth = calendar.date(byAdding: .month, value: 1, to: firstOfThisMonth) else {
            return date
        }
        return nextMonth
    }
}
