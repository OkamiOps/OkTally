// Tests/OkTallyTests/UsageHistoryTests.swift
import XCTest
@testable import OkTally

final class UsageHistoryTests: XCTestCase {
    private func snapshot(
        at t: TimeInterval,
        providerId: String = "claude",
        windows: [QuotaWindow]
    ) -> ProviderSnapshot {
        ProviderSnapshot(providerId: providerId, fetchedAt: Date(timeIntervalSince1970: t), quotas: windows, usageDetail: nil)
    }

    private func percentWindow(
        used: Double,
        label: String = "5h",
        resetAt: Date = Date(timeIntervalSince1970: 99_999)
    ) -> QuotaWindow {
        QuotaWindow(label: label, shape: .rollingWindow(used: used, limit: 100, windowStart: Date(timeIntervalSince1970: 0), resetAt: resetAt))
    }

    func test_worstUsedSeries_takesMaxUsedPercentAcrossWindows_inOrder() {
        let series = UsageHistory.worstUsedSeries([
            snapshot(at: 100, windows: [percentWindow(used: 10), percentWindow(used: 40, label: "weekly")]),
            snapshot(at: 200, windows: [percentWindow(used: 55)]),
        ])

        XCTAssertEqual(series.count, 2)
        XCTAssertEqual(series[0].date, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(series[0].usedPercent, 40, accuracy: 0.0001)
        XCTAssertEqual(series[1].date, Date(timeIntervalSince1970: 200))
        XCTAssertEqual(series[1].usedPercent, 55, accuracy: 0.0001)
    }

    func test_worstUsedSeries_skipsSnapshotsWithoutPercentWindows() {
        let balanceOnly = snapshot(at: 100, windows: [
            QuotaWindow(label: "balance", shape: .creditBalance(remaining: 12, currency: "USD"))
        ])
        let series = UsageHistory.worstUsedSeries([
            balanceOnly,
            snapshot(at: 200, windows: [percentWindow(used: 30)]),
        ])

        XCTAssertEqual(series.count, 1)
        XCTAssertEqual(series[0].date, Date(timeIntervalSince1970: 200))
        XCTAssertEqual(series[0].usedPercent, 30, accuracy: 0.0001)
    }

    func test_worstUsedSeries_emptyInput_returnsEmpty() {
        XCTAssertEqual(UsageHistory.worstUsedSeries([]), [])
    }

    func test_series_matchesExactProviderLabelAndCycle_sortsAndPreservesRepeatedSamples() {
        let resetAt = Date(timeIntervalSince1970: 50_000)
        let series = UsageHistory.series(
            providerId: "claude",
            windowLabel: "weekly",
            resetAt: resetAt,
            snapshots: [
                snapshot(at: 300, windows: [percentWindow(used: 30, label: "weekly", resetAt: resetAt.addingTimeInterval(60))]),
                snapshot(at: 200, windows: [percentWindow(used: 20, label: "weekly", resetAt: resetAt)]),
                snapshot(at: 100, windows: [percentWindow(used: 10, label: "weekly", resetAt: resetAt.addingTimeInterval(-60))]),
                snapshot(at: 250, windows: [percentWindow(used: 20, label: "weekly", resetAt: resetAt)]),
                snapshot(at: 150, windows: [percentWindow(used: 99, label: "weekly", resetAt: resetAt.addingTimeInterval(61))]),
                snapshot(at: 175, windows: [percentWindow(used: 88, label: "5h", resetAt: resetAt)]),
                snapshot(at: 225, providerId: "cursor", windows: [percentWindow(used: 77, label: "weekly", resetAt: resetAt)]),
            ]
        )

        XCTAssertEqual(
            series,
            [
                UsageHistoryPoint(date: Date(timeIntervalSince1970: 100), usedPercent: 10),
                UsageHistoryPoint(date: Date(timeIntervalSince1970: 200), usedPercent: 20),
                UsageHistoryPoint(date: Date(timeIntervalSince1970: 250), usedPercent: 20),
                UsageHistoryPoint(date: Date(timeIntervalSince1970: 300), usedPercent: 30),
            ]
        )
    }
}
