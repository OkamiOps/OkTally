// Sources/OkTally/Core/UsageHistory.swift
import Foundation

struct UsageHistoryPoint: Equatable {
    let date: Date
    let usedPercent: Double
}

/// Turns persisted snapshots into a plottable series. "Worst" mirrors the popover's card
/// logic: at each point in time, the window closest to its limit is the one the owner
/// cares about, so the series tracks max used% across windows.
enum UsageHistory {
    static func worstUsedSeries(_ snapshots: [ProviderSnapshot]) -> [UsageHistoryPoint] {
        snapshots.compactMap { snapshot in
            let worst = snapshot.quotas.compactMap { $0.shape.usedPercent }.max()
            return worst.map { UsageHistoryPoint(date: snapshot.fetchedAt, usedPercent: $0) }
        }
    }
}
