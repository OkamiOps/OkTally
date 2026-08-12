// Sources/OkTally/UI/QuotaPresentation.swift
import SwiftUI

/// Presentation helpers for rendering a quota window the way the reference design does:
/// a bar of the *remaining* fraction, a "X% restante" label, and a reset countdown.
enum QuotaPresentation {
    /// Remaining fraction (0…1) for windows that have a percentage; nil for pure balances.
    static func remainingFraction(_ shape: QuotaShape) -> Double? {
        guard let used = shape.usedPercent else { return nil }
        return max(0, min(1, (100 - used) / 100))
    }

    /// Primary right-aligned value, e.g. "98% restante" or "37.5 USD".
    static func remainingText(_ shape: QuotaShape) -> String {
        if let used = shape.usedPercent {
            let left = Int((100 - used).rounded())
            let prefix = shape.isEstimated ? "~" : ""
            return prefix + LF("%d%% restante", left)
        }
        switch shape {
        case .creditBalance(let remaining, let currency):
            return "\(format(remaining)) \(currency)"
        case .meteredOnly(let cost):
            return LF("$%@ usado", format(cost))
        default:
            return ""
        }
    }

    /// Reset countdown like "Reseta em 3h 24m"; nil when there's no meaningful future reset.
    static func resetText(_ shape: QuotaShape, now: Date = Date()) -> String? {
        guard let reset = shape.resetAt, reset.timeIntervalSince(now) > 60 else { return nil }
        let fmt = DateComponentsFormatter()
        fmt.unitsStyle = .abbreviated
        fmt.allowedUnits = [.day, .hour, .minute]
        fmt.maximumUnitCount = 2
        guard let s = fmt.string(from: now, to: reset) else { return nil }
        return LF("Reseta em %@", s)
    }

    /// Green when plenty remains, amber mid, red when nearly exhausted.
    static func color(remaining: Double?) -> Color {
        guard let remaining else { return .accentColor }
        if remaining <= 0.10 { return .red }
        if remaining <= 0.30 { return .orange }
        return .green
    }

    /// Worst (lowest-remaining) status color across a provider's windows, for its tab dot.
    static func providerColor(_ snapshot: ProviderSnapshot?) -> Color {
        guard let snapshot else { return .secondary }
        let remainings = snapshot.quotas.compactMap { remainingFraction($0.shape) }
        guard let worst = remainings.min() else { return .secondary }
        return color(remaining: worst)
    }

    private static func format(_ d: Decimal) -> String {
        let n = NSDecimalNumber(decimal: d)
        return String(format: "%.2f", n.doubleValue)
    }
}
