// Tests/OkTallyTests/UsageHistoryTests.swift
import XCTest
@testable import OkTally

final class UsageHistoryTests: XCTestCase {
    private func snapshot(at t: TimeInterval, windows: [QuotaWindow]) -> ProviderSnapshot {
        ProviderSnapshot(providerId: "claude", fetchedAt: Date(timeIntervalSince1970: t), quotas: windows, usageDetail: nil)
    }

    private func percentWindow(used: Double, label: String = "5h") -> QuotaWindow {
        QuotaWindow(label: label, shape: .rollingWindow(used: used, limit: 100, windowStart: Date(timeIntervalSince1970: 0), resetAt: Date(timeIntervalSince1970: 99999)))
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
}
