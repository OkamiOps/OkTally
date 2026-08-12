// Tests/OkTallyTests/TokenAnalyticsTests.swift
import XCTest
@testable import OkTally

final class TokenAnalyticsTests: XCTestCase {
    private func analytics(_ buckets: [DailyTokens]) -> TokenAnalytics {
        TokenAnalytics(dailyBuckets: buckets)
    }

    func test_effectiveLifetimeAndPeak_deriveFromBuckets() {
        let a = analytics([
            DailyTokens(day: "2026-08-01", tokens: 100),
            DailyTokens(day: "2026-08-02", tokens: 300),
        ])
        XCTAssertEqual(a.effectiveLifetimeTokens, 400)
        XCTAssertEqual(a.effectivePeakDailyTokens, 300)
    }

    func test_effectiveValues_preferStoredWhenPresent() {
        let a = TokenAnalytics(
            lifetimeTokens: 9999,
            peakDailyTokens: 500,
            dailyBuckets: [DailyTokens(day: "2026-08-01", tokens: 1)]
        )
        XCTAssertEqual(a.effectiveLifetimeTokens, 9999)
        XCTAssertEqual(a.effectivePeakDailyTokens, 500)
    }

    func test_effectiveCurrentStreak_countsBackFromTodayOrYesterday() {
        let now = TokenAnalytics.date(fromDay: "2026-08-12")!.addingTimeInterval(10 * 3600)
        // Uso ontem e anteontem, nada hoje → streak 2 (semântica GitHub).
        let a = analytics([
            DailyTokens(day: "2026-08-10", tokens: 5),
            DailyTokens(day: "2026-08-11", tokens: 5),
        ])
        XCTAssertEqual(a.effectiveCurrentStreakDays(now: now), 2)

        // Buraco antes de ontem quebra o streak.
        let broken = analytics([
            DailyTokens(day: "2026-08-08", tokens: 5),
            DailyTokens(day: "2026-08-11", tokens: 5),
        ])
        XCTAssertEqual(broken.effectiveCurrentStreakDays(now: now), 1)

        // Último uso há 3 dias → streak 0.
        let stale = analytics([DailyTokens(day: "2026-08-09", tokens: 5)])
        XCTAssertEqual(stale.effectiveCurrentStreakDays(now: now), 0)
    }

    func test_effectiveLongestStreak_findsLongestConsecutiveRun() {
        let a = analytics([
            DailyTokens(day: "2026-08-01", tokens: 1),
            DailyTokens(day: "2026-08-02", tokens: 1),
            DailyTokens(day: "2026-08-03", tokens: 1),
            DailyTokens(day: "2026-08-07", tokens: 1),
            DailyTokens(day: "2026-08-08", tokens: 1),
        ])
        XCTAssertEqual(a.effectiveLongestStreakDays, 3)
    }

    func test_aggregate_sumsBucketsByDay_andLifetimes() {
        let codex = TokenAnalytics(
            lifetimeTokens: 1000,
            dailyBuckets: [DailyTokens(day: "2026-08-11", tokens: 100)]
        )
        let claude = analytics([
            DailyTokens(day: "2026-08-11", tokens: 50),
            DailyTokens(day: "2026-08-12", tokens: 30),
        ])
        let merged = try! XCTUnwrap(TokenAnalytics.aggregate([codex, claude]))

        XCTAssertEqual(merged.dailyBuckets, [
            DailyTokens(day: "2026-08-11", tokens: 150),
            DailyTokens(day: "2026-08-12", tokens: 30),
        ])
        // 1000 (lifetime real do Codex) + 80 (soma coletada do Claude).
        XCTAssertEqual(merged.effectiveLifetimeTokens, 1080)
    }

    func test_aggregate_emptyInput_returnsNil() {
        XCTAssertNil(TokenAnalytics.aggregate([]))
        XCTAssertNil(TokenAnalytics.aggregate([analytics([])]))
    }
}
