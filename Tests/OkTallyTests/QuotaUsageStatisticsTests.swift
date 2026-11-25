import XCTest
@testable import OkTally

final class QuotaUsageStatisticsTests: XCTestCase {
    func test_derive_sumsOnlyPositiveDeltasAndIgnoresReset() {
        let now = Date(timeIntervalSince1970: 1_764_120_000) // 2025-11-26 12:00 UTC
        func snap(_ hoursAgo: Double, _ used: Double) -> ProviderSnapshot {
            ProviderSnapshot(
                providerId: "supergrok",
                fetchedAt: now.addingTimeInterval(-hoursAgo * 3600),
                quotas: [QuotaWindow(label: "weekly", shape: .rollingWindow(used: used, limit: 100, windowStart: now, resetAt: now.addingTimeInterval(3600)))],
                usageDetail: nil
            )
        }
        let stats = QuotaUsageStatistics.derive(
            snapshots: [snap(30, 10), snap(29, 15), snap(25, 22), snap(3, 4), snap(1, 9)],
            windowLabel: "weekly",
            now: now
        )

        XCTAssertEqual(stats?.currentUsedPercent, 9)
        XCTAssertEqual(stats?.consumedLast24h, 5)
        XCTAssertEqual(stats?.consumedLast7d, 17)
        XCTAssertEqual(stats?.dailyConsumption.reduce(0) { $0 + $1.percentPoints } ?? 0, 17, accuracy: 0.001)
    }

    func test_derive_returnsNilWhenWindowNeverAppears() {
        let stats = QuotaUsageStatistics.derive(snapshots: [], windowLabel: "weekly")
        XCTAssertNil(stats)
    }
}
