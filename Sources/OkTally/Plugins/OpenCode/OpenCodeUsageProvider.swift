// Sources/OkTally/Plugins/OpenCode/OpenCodeUsageProvider.swift
import Foundation

enum OpenCodeError: Error, Equatable {
    case notDetected
}

extension OpenCodeError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notDetected:
            return "OpenCode não detectado — o banco local de uso (opencode.db) não foi encontrado."
        }
    }
}

/// OpenCode ships no public balance/usage API (confirmed live — see
/// `docs/superpowers/research/plan2-opencode.md`), so this plugin is one of two ESTIMATED
/// providers in Plan 2. It builds one `QuotaShape.estimated` window per Go plan budget
/// (5h / weekly / monthly), sourced from `OpenCodeLocalEstimator`'s read of the local
/// `opencode.db`. The dollar budgets are editable defaults, not authoritative limits.
///
/// When a live HTTP 429 has been observed and parsed via `OpenCodeRateLimitParser`
/// (wired in by the caller through `recordRateLimit`), the matching window is overridden
/// to reflect the authoritative "at limit until `resetAt`" state instead of the estimate,
/// for as long as that reset time remains in the future.
final class OpenCodeUsageProvider: UsageProvider {
    let id = "opencode"
    let displayName = "OpenCode"
    let authMethod: AuthMethod = .apiKey
    let refreshInterval: TimeInterval = 600

    private let apiKeyProvider: () -> String?
    private let estimator: OpenCodeLocalEstimating
    private let goWindowBudgets: [(label: String, hours: Int, budget: Decimal)]
    private var recordedRateLimit: (limitName: String, resetAt: Date?)?

    init(
        apiKeyProvider: @escaping () -> String?,
        estimator: OpenCodeLocalEstimating = OpenCodeLocalEstimator(),
        goWindowBudgets: [(label: String, hours: Int, budget: Decimal)] = [
            ("5h", 5, 12),
            ("weekly", 168, 30),
            ("monthly", 720, 60)
        ]
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.estimator = estimator
        self.goWindowBudgets = goWindowBudgets
    }

    func isAuthenticated() async -> Bool {
        apiKeyProvider() != nil
    }

    /// Called externally when the HTTP layer observes and parses a 429 response via
    /// `OpenCodeRateLimitParser`. Overrides the matching budget window (by `limitName` ==
    /// window label) until `resetAt` passes.
    ///
    /// STATUS: DORMANT — nothing in `Sources/` currently calls this. OkTally doesn't sit
    /// on OpenCode's network path (it only reads the local `opencode.db`), so there is no
    /// live 429 to observe and hand in here today. Left in place, tested, and documented
    /// (see `OpenCodeRateLimitParser`) so a future proxy/observer can wire it up without
    /// redesigning this override mechanism.
    func recordRateLimit(limitName: String, resetAt: Date?) {
        recordedRateLimit = (limitName, resetAt)
    }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        guard apiKeyProvider() != nil else { throw OpenCodeError.notDetected }

        let now = Date()
        var windows: [QuotaWindow] = []

        for window in goWindowBudgets {
            guard let spent = estimator.spentInCurrentWindow(windowHours: window.hours, now: now) else {
                throw OpenCodeError.notDetected
            }

            let limitDouble = (window.budget as NSDecimalNumber).doubleValue
            var shape = QuotaShape.estimated(
                used: (spent as NSDecimalNumber).doubleValue,
                limit: limitDouble,
                basis: .localTokenCount,
                resetAt: nil
            )

            if let recordedRateLimit,
               recordedRateLimit.limitName == window.label,
               let resetAt = recordedRateLimit.resetAt,
               resetAt > now {
                shape = .estimated(used: limitDouble, limit: limitDouble, basis: .reactiveRateLimit, resetAt: resetAt)
            }

            windows.append(QuotaWindow(label: window.label, shape: shape))
        }

        return ProviderSnapshot(providerId: id, fetchedAt: now, quotas: windows, usageDetail: nil)
    }
}
