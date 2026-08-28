// Sources/OkTally/Core/UsageForecast.swift
import Foundation

struct ForecastWindowID: Hashable, Equatable {
    let providerId: String
    let windowLabel: String
}

enum UsageForecastState: Equatable {
    case slowDown
    case onPace
    case canAccelerate
    case noExhaustion
    case collecting(observedHours: Double, sampleCount: Int)
    case unavailable
}

struct UsageForecast: Equatable {
    let id: ForecastWindowID
    let cadence: RenewalCadence?
    let currentUsedPercent: Double
    let samples: [UsageHistoryPoint]
    let ratePerDay: Double?
    let safeRatePerDay: Double?
    let exhaustionAt: Date?
    let resetAt: Date?
    let gap: TimeInterval?
    let state: UsageForecastState
}

/// Resolves the forecast target without knowing about persistence or SwiftUI.
///
/// A manual target wins whenever it is still present. Automatic selection is deliberately
/// based on projected time, rather than current percentage, because two windows with the
/// same remaining percentage can have radically different reset deadlines and pace.
enum UsageForecastSelection {
    static func select(
        preferred: ForecastSlot,
        forecasts: [ForecastWindowID: UsageForecast]
    ) -> UsageForecast? {
        if case let .window(providerId, windowLabel) = preferred,
           let explicit = forecasts[ForecastWindowID(providerId: providerId, windowLabel: windowLabel)] {
            return explicit
        }

        let candidates = forecasts.values.filter { forecast in
            if case .unavailable = forecast.state { return false }
            return true
        }

        let numeric = candidates.filter { $0.gap != nil }
        if let largestShortfall = numeric
            .filter({ ($0.gap ?? 0) > 0 })
            .sorted(by: largestPositiveGapFirst)
            .first {
            return largestShortfall
        }

        if let tightestSafeForecast = numeric
            .sorted(by: smallestAbsoluteGapFirst)
            .first {
            return tightestSafeForecast
        }

        // A mature zero/near-zero rate is a stronger conclusion than an immature series.
        // The collecting fallback below is specifically for the case where no window has
        // accumulated enough history for a numeric (or no-exhaustion) conclusion.
        if let noExhaustion = candidates
            .filter({ if case .noExhaustion = $0.state { return true }; return false })
            .sorted(by: stableIDOrder)
            .first {
            return noExhaustion
        }

        if let longestObserved = candidates
            .filter({ if case .collecting = $0.state { return true }; return false })
            .sorted(by: longestObservedFirst)
            .first {
            return longestObserved
        }

        return candidates.sorted(by: stableIDOrder).first
    }

    private static func largestPositiveGapFirst(_ lhs: UsageForecast, _ rhs: UsageForecast) -> Bool {
        let left = lhs.gap ?? -.infinity
        let right = rhs.gap ?? -.infinity
        if left != right { return left > right }
        return stableIDOrder(lhs, rhs)
    }

    private static func smallestAbsoluteGapFirst(_ lhs: UsageForecast, _ rhs: UsageForecast) -> Bool {
        let left = abs(lhs.gap ?? .infinity)
        let right = abs(rhs.gap ?? .infinity)
        if left != right { return left < right }
        return stableIDOrder(lhs, rhs)
    }

    private static func longestObservedFirst(_ lhs: UsageForecast, _ rhs: UsageForecast) -> Bool {
        let left = observedHours(in: lhs)
        let right = observedHours(in: rhs)
        if left != right { return left > right }
        let leftSamples = sampleCount(in: lhs)
        let rightSamples = sampleCount(in: rhs)
        if leftSamples != rightSamples { return leftSamples > rightSamples }
        return stableIDOrder(lhs, rhs)
    }

    private static func observedHours(in forecast: UsageForecast) -> Double {
        if case let .collecting(observedHours, _) = forecast.state { return observedHours }
        return 0
    }

    private static func sampleCount(in forecast: UsageForecast) -> Int {
        if case let .collecting(_, sampleCount) = forecast.state { return sampleCount }
        return 0
    }

    private static func stableIDOrder(_ lhs: UsageForecast, _ rhs: UsageForecast) -> Bool {
        if lhs.id.providerId != rhs.id.providerId {
            return lhs.id.providerId < rhs.id.providerId
        }
        return lhs.id.windowLabel < rhs.id.windowLabel
    }
}

/// Pure 24-hour pace calculation for one explicitly renewable quota window.
enum UsageForecastEngine {
    private static let historyWindow: TimeInterval = 24 * 60 * 60
    private static let minimumObservedHours = 3.0
    private static let minimumSampleCount = 6
    private static let minimumConsumedPercent = 0.5
    private static let paceTolerance: TimeInterval = 6 * 60 * 60

    static func forecast(
        providerId: String,
        current: QuotaWindow,
        snapshots: [ProviderSnapshot],
        now: Date
    ) -> UsageForecast {
        let id = ForecastWindowID(providerId: providerId, windowLabel: current.label)

        guard let eligible = eligible(current: current, now: now) else {
            return unavailable(id: id, current: current)
        }

        let samples = UsageHistory.series(
            providerId: providerId,
            windowLabel: current.label,
            resetAt: eligible.resetAt,
            snapshots: snapshots
        )
        .filter { point in
            point.date >= now.addingTimeInterval(-historyWindow) && point.date <= now
        }

        guard let earliest = samples.first, let latest = samples.last else {
            return collecting(
                id: id,
                eligible: eligible,
                samples: samples,
                observedHours: 0
            )
        }

        let observedHours = max(0, latest.date.timeIntervalSince(earliest.date) / 3_600)
        guard observedHours >= minimumObservedHours, samples.count >= minimumSampleCount else {
            return collecting(
                id: id,
                eligible: eligible,
                samples: samples,
                observedHours: observedHours
            )
        }

        let consumedPercent = max(0, latest.usedPercent - earliest.usedPercent)
        let ratePerDay = consumedPercent / observedHours * 24
        let remainingPercent = max(0, 100 - latest.usedPercent)
        let hoursToReset = eligible.resetAt.timeIntervalSince(now) / 3_600
        let safeRatePerDay = remainingPercent / hoursToReset * 24

        guard consumedPercent >= minimumConsumedPercent else {
            return UsageForecast(
                id: id,
                cadence: eligible.cadence,
                currentUsedPercent: eligible.currentUsedPercent,
                samples: samples,
                ratePerDay: ratePerDay,
                safeRatePerDay: safeRatePerDay,
                exhaustionAt: nil,
                resetAt: eligible.resetAt,
                gap: nil,
                state: .noExhaustion
            )
        }

        let ratePerHour = consumedPercent / observedHours
        let exhaustionAt = now.addingTimeInterval(remainingPercent / ratePerHour * 3_600)
        let gap = eligible.resetAt.timeIntervalSince(exhaustionAt)

        let state: UsageForecastState
        if gap > paceTolerance {
            state = .slowDown
        } else if gap < -paceTolerance {
            state = .canAccelerate
        } else {
            state = .onPace
        }

        return UsageForecast(
            id: id,
            cadence: eligible.cadence,
            currentUsedPercent: eligible.currentUsedPercent,
            samples: samples,
            ratePerDay: ratePerDay,
            safeRatePerDay: safeRatePerDay,
            exhaustionAt: exhaustionAt,
            resetAt: eligible.resetAt,
            gap: gap,
            state: state
        )
    }

    /// Shared eligibility rule for the AppModel's picker and persisted-history pass.
    /// Keeping it next to the engine prevents the UI from offering a window the engine
    /// will later publish as unavailable.
    static func isEligible(current: QuotaWindow, now: Date) -> Bool {
        eligible(current: current, now: now) != nil
    }

    private static func eligible(current: QuotaWindow, now: Date) -> EligibleWindow? {
        guard let cadence = current.renewalCadence,
              !current.shape.isEstimated,
              let usedPercent = current.shape.usedPercent,
              usedPercent.isFinite,
              let resetAt = current.shape.resetAt,
              resetAt > now else {
            return nil
        }

        return EligibleWindow(
            cadence: cadence,
            currentUsedPercent: min(max(usedPercent, 0), 100),
            resetAt: resetAt
        )
    }

    private static func collecting(
        id: ForecastWindowID,
        eligible: EligibleWindow,
        samples: [UsageHistoryPoint],
        observedHours: Double
    ) -> UsageForecast {
        UsageForecast(
            id: id,
            cadence: eligible.cadence,
            currentUsedPercent: eligible.currentUsedPercent,
            samples: samples,
            ratePerDay: nil,
            safeRatePerDay: nil,
            exhaustionAt: nil,
            resetAt: eligible.resetAt,
            gap: nil,
            state: .collecting(observedHours: observedHours, sampleCount: samples.count)
        )
    }

    private static func unavailable(
        id: ForecastWindowID,
        current: QuotaWindow
    ) -> UsageForecast {
        let currentUsedPercent = current.shape.usedPercent
            .flatMap { $0.isFinite ? min(max($0, 0), 100) : nil }
            ?? 0

        return UsageForecast(
            id: id,
            cadence: current.renewalCadence,
            currentUsedPercent: currentUsedPercent,
            samples: [],
            ratePerDay: nil,
            safeRatePerDay: nil,
            exhaustionAt: nil,
            resetAt: current.shape.resetAt,
            gap: nil,
            state: .unavailable
        )
    }
}

private struct EligibleWindow {
    let cadence: RenewalCadence
    let currentUsedPercent: Double
    let resetAt: Date
}
