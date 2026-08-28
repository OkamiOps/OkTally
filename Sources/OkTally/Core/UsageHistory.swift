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

    /// Extracts one real quota window from one provider and one renewal cycle. Reset dates
    /// may differ by up to a minute because upstream providers can serialize the same reset
    /// with slightly different precision on successive polls.
    static func series(
        providerId: String,
        windowLabel: String,
        resetAt: Date,
        snapshots: [ProviderSnapshot]
    ) -> [UsageHistoryPoint] {
        let points: [(index: Int, point: UsageHistoryPoint)] = snapshots.enumerated().compactMap { index, snapshot in
            guard snapshot.providerId == providerId,
                  let window = snapshot.quotas.first(where: { window in
                      guard window.label == windowLabel,
                            !window.shape.isEstimated,
                            let sampleResetAt = window.shape.resetAt,
                            window.shape.usedPercent != nil else {
                          return false
                      }
                      return abs(sampleResetAt.timeIntervalSince(resetAt)) <= 60
                  }),
                  let usedPercent = window.shape.usedPercent,
                  usedPercent.isFinite else {
                return nil
            }

            return (
                index,
                UsageHistoryPoint(
                    date: snapshot.fetchedAt,
                    usedPercent: min(max(usedPercent, 0), 100)
                )
            )
        }

        return points
            .sorted { lhs, rhs in
                if lhs.point.date == rhs.point.date {
                    return lhs.index < rhs.index
                }
                return lhs.point.date < rhs.point.date
            }
            .map(\.point)
    }
}
