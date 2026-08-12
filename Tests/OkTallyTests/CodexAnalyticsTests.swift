// Tests/OkTallyTests/CodexAnalyticsTests.swift
import XCTest
@testable import OkTally

final class CodexAnalyticsTests: XCTestCase {
    func test_parse_snakeCaseWithBucketArray() throws {
        let json = """
        {
            "stats": {
                "lifetime_tokens": 2200000000,
                "peak_daily_tokens": 385400000,
                "current_streak_days": 6,
                "longest_streak_days": 8,
                "longest_running_turn_sec": 2673,
                "daily_usage_buckets": [
                    {"date": "2026-08-10", "tokens": 1000},
                    {"date": "2026-08-11", "tokens": 79900000}
                ]
            }
        }
        """
        let analytics = try XCTUnwrap(TokenAnalytics(codexProfileJSON: Data(json.utf8)))

        XCTAssertEqual(analytics.lifetimeTokens, 2_200_000_000)
        XCTAssertEqual(analytics.peakDailyTokens, 385_400_000)
        XCTAssertEqual(analytics.currentStreakDays, 6)
        XCTAssertEqual(analytics.longestStreakDays, 8)
        XCTAssertEqual(analytics.longestRunningTurnSeconds, 2673)
        XCTAssertEqual(analytics.dailyBuckets, [
            DailyTokens(day: "2026-08-10", tokens: 1000),
            DailyTokens(day: "2026-08-11", tokens: 79_900_000),
        ])
        XCTAssertEqual(analytics.tokens(onDay: "2026-08-11"), 79_900_000)
    }

    func test_parse_bucketDictionary_andInputOutputFallback() throws {
        let json = """
        {
            "stats": {
                "dailyUsageBuckets": {
                    "2026-08-09T00:00:00Z": {"input_tokens": 600, "output_tokens": 400}
                }
            }
        }
        """
        let analytics = try XCTUnwrap(TokenAnalytics(codexProfileJSON: Data(json.utf8)))
        XCTAssertEqual(analytics.dailyBuckets, [DailyTokens(day: "2026-08-09", tokens: 1000)])
    }

    func test_parse_missingStats_returnsNil() {
        XCTAssertNil(TokenAnalytics(codexProfileJSON: Data("{}".utf8)))
        XCTAssertNil(TokenAnalytics(codexProfileJSON: Data(#"{"stats": {}}"#.utf8)))
    }

    func test_compactTokens() {
        XCTAssertEqual(TokenAnalytics.compactTokens(950), "950")
        XCTAssertEqual(TokenAnalytics.compactTokens(1200), "1.2K")
        XCTAssertEqual(TokenAnalytics.compactTokens(3_400_000), "3.4M")
        XCTAssertEqual(TokenAnalytics.compactTokens(2_200_000_000), "2.2B")
        XCTAssertEqual(TokenAnalytics.compactTokens(2_000_000), "2M")
    }

    func test_durationLabel() {
        XCTAssertEqual(TokenAnalytics.durationLabel(2673), "44m 33s")
        XCTAssertEqual(TokenAnalytics.durationLabel(3700), "1h 1m")
        XCTAssertEqual(TokenAnalytics.durationLabel(42), "42s")
    }

    func test_tokensLast30Days_sumsMostRecentBuckets() {
        let buckets = (1...40).map { DailyTokens(day: String(format: "2026-07-%02d", $0), tokens: 10) }
        let analytics = TokenAnalytics(
            lifetimeTokens: nil, peakDailyTokens: nil, currentStreakDays: nil,
            longestStreakDays: nil, longestRunningTurnSeconds: nil, dailyBuckets: buckets
        )
        XCTAssertEqual(analytics.tokensLast30Days, 300)
    }

    func test_heatLevels_quartileBands_zeroOmitted() {
        let buckets = [
            DailyTokens(day: "d0", tokens: 0),
            DailyTokens(day: "d1", tokens: 10),
            DailyTokens(day: "d2", tokens: 20),
            DailyTokens(day: "d3", tokens: 30),
            DailyTokens(day: "d4", tokens: 40),
        ]
        let analytics = TokenAnalytics(
            lifetimeTokens: nil, peakDailyTokens: nil, currentStreakDays: nil,
            longestStreakDays: nil, longestRunningTurnSeconds: nil, dailyBuckets: buckets
        )
        let levels = analytics.heatLevels()
        XCTAssertNil(levels["d0"])
        XCTAssertEqual(levels["d1"], 1)
        XCTAssertEqual(levels["d4"], 4)
        XCTAssertEqual(Set(levels.values).subtracting([1, 2, 3, 4]), [])
    }
}
