// Sources/OkTally/Core/AlertEngine.swift
import Foundation

struct AlertEngine {
    func evaluate(
        providerId: String,
        providerDisplayName: String,
        previous: ProviderSnapshot?,
        current: ProviderSnapshot,
        thresholds: [String: [AlertThreshold]]
    ) -> [AlertEvent] {
        var events: [AlertEvent] = []
        for window in current.quotas {
            let previousWindow = previous?.quotas.first { $0.label == window.label }
            let windowThresholds = thresholds[window.label] ?? Self.defaultThresholds(for: window.shape)
            for threshold in windowThresholds {
                if let event = evaluateOne(
                    threshold: threshold,
                    window: window,
                    previousWindow: previousWindow,
                    providerId: providerId,
                    providerDisplayName: providerDisplayName
                ) {
                    events.append(event)
                }
            }
        }
        return events
    }

    private func evaluateOne(
        threshold: AlertThreshold,
        window: QuotaWindow,
        previousWindow: QuotaWindow?,
        providerId: String,
        providerDisplayName: String
    ) -> AlertEvent? {
        switch threshold {
        case .percentage(let pct):
            guard let currentPercent = window.shape.usedPercent else { return nil }
            let thresholdPercent = pct * 100
            let previousPercent = previousWindow?.shape.usedPercent
            let wasBelowOrFirstObservation = previousPercent == nil || previousPercent! < thresholdPercent
            guard wasBelowOrFirstObservation, currentPercent >= thresholdPercent else { return nil }
            return AlertEvent(
                providerId: providerId,
                providerDisplayName: providerDisplayName,
                windowLabel: window.label,
                threshold: threshold,
                currentPercent: currentPercent,
                currentRemaining: nil,
                resetAt: window.shape.resetAt,
                isEstimated: window.shape.isEstimated
            )
        case .lowBalance(let limit):
            guard case .creditBalance(let remaining, _) = window.shape else { return nil }
            var previousRemaining: Decimal?
            if case .creditBalance(let r, _) = previousWindow?.shape { previousRemaining = r }
            let wasAboveOrFirstObservation = previousRemaining == nil || previousRemaining! >= limit
            guard wasAboveOrFirstObservation, remaining < limit else { return nil }
            return AlertEvent(
                providerId: providerId,
                providerDisplayName: providerDisplayName,
                windowLabel: window.label,
                threshold: threshold,
                currentPercent: nil,
                currentRemaining: remaining,
                resetAt: nil,
                isEstimated: window.shape.isEstimated
            )
        }
    }

    static func defaultThresholds(for shape: QuotaShape) -> [AlertThreshold] {
        switch shape {
        case .rollingWindow, .periodicCounter, .estimated:
            return AlertThreshold.defaultPercentageThresholds
        case .creditBalance:
            return [AlertThreshold.defaultLowBalanceThreshold]
        case .meteredOnly:
            return []
        }
    }
}
