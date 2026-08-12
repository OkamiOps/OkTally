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
        let analytics = try XCTUnwrap(CodexAnalytics(profileJSON: Data(json.utf8)))

        XCTAssertEqual(analytics.lifetimeTokens, 2_200_000_000)
        XCTAssertEqual(analytics.peakDailyTokens, 385_400_000)
        XCTAssertEqual(analytics.currentStreakDays, 6)
        XCTAssertEqual(analytics.longestStreakDays, 8)
        XCTAssertEqual(analytics.longestRunningTurnSeconds, 2673)
        XCTAssertEqual(analytics.dailyBuckets, [
            CodexDailyTokens(day: "2026-08-10", tokens: 1000),
            CodexDailyTokens(day: "2026-08-11", tokens: 79_900_000),
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
        let analytics = try XCTUnwrap(CodexAnalytics(profileJSON: Data(json.utf8)))
        XCTAssertEqual(analytics.dailyBuckets, [CodexDailyTokens(day: "2026-08-09", tokens: 1000)])
    }

    func test_parse_missingStats_returnsNil() {
        XCTAssertNil(CodexAnalytics(profileJSON: Data("{}".utf8)))
        XCTAssertNil(CodexAnalytics(profileJSON: Data(#"{"stats": {}}"#.utf8)))
    }

    func test_compactTokens() {
        XCTAssertEqual(CodexAnalytics.compactTokens(950), "950")
        XCTAssertEqual(CodexAnalytics.compactTokens(1200), "1.2K")
        XCTAssertEqual(CodexAnalytics.compactTokens(3_400_000), "3.4M")
        XCTAssertEqual(CodexAnalytics.compactTokens(2_200_000_000), "2.2B")
        XCTAssertEqual(CodexAnalytics.compactTokens(2_000_000), "2M")
    }

    func test_durationLabel() {
        XCTAssertEqual(CodexAnalytics.durationLabel(2673), "44m 33s")
        XCTAssertEqual(CodexAnalytics.durationLabel(3700), "1h 1m")
        XCTAssertEqual(CodexAnalytics.durationLabel(42), "42s")
    }

    func test_tokensLast30Days_sumsMostRecentBuckets() {
        let buckets = (1...40).map { CodexDailyTokens(day: String(format: "2026-07-%02d", $0), tokens: 10) }
        let analytics = CodexAnalytics(
            lifetimeTokens: nil, peakDailyTokens: nil, currentStreakDays: nil,
            longestStreakDays: nil, longestRunningTurnSeconds: nil, dailyBuckets: buckets
        )
        XCTAssertEqual(analytics.tokensLast30Days, 300)
    }

    func test_heatLevels_quartileBands_zeroOmitted() {
        let buckets = [
            CodexDailyTokens(day: "d0", tokens: 0),
            CodexDailyTokens(day: "d1", tokens: 10),
            CodexDailyTokens(day: "d2", tokens: 20),
            CodexDailyTokens(day: "d3", tokens: 30),
            CodexDailyTokens(day: "d4", tokens: 40),
        ]
        let analytics = CodexAnalytics(
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
