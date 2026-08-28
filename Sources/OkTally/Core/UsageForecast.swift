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
    let cadence: RenewalCadence
    let currentUsedPercent: Double
    let samples: [UsageHistoryPoint]
    let ratePerDay: Double?
    let safeRatePerDay: Double?
    let exhaustionAt: Date?
    let resetAt: Date
    let gap: TimeInterval?
    let state: UsageForecastState
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
            return unavailable(id: id, current: current, now: now)
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
        current: QuotaWindow,
        now: Date
    ) -> UsageForecast {
        let currentUsedPercent = current.shape.usedPercent
            .flatMap { $0.isFinite ? min(max($0, 0), 100) : nil }
            ?? 0

        // `UsageForecast` retains the nonoptional interface consumed by later UI tasks.
        // In this state neither date is a prediction: `exhaustionAt` and `gap` stay nil,
        // and presentation must use `state` rather than this sentinel reset value.
        return UsageForecast(
            id: id,
            cadence: current.renewalCadence ?? .weekly,
            currentUsedPercent: currentUsedPercent,
            samples: [],
            ratePerDay: nil,
            safeRatePerDay: nil,
            exhaustionAt: nil,
            resetAt: current.shape.resetAt ?? now,
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
