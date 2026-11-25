import XCTest
@testable import OkTally

final class CursorAnalyticsFetcherTests: XCTestCase {
    func test_analytics_sumsDailyCategoriesAndParsesMeteredCost() {
        let dayMs = Int64(TokenAnalytics.date(fromDay: "2026-11-20")!.timeIntervalSince1970 * 1000)
        let daily = Data((["dailySpend":[
            ["day":"\(dayMs)","category":"grok-4.7-high-fast","totalTokens":"100"],
            ["day":"\(dayMs)","category":"grok-bot-default","totalTokens":"40"],
            ["day":"\(dayMs)","category":"empty","totalTokens":"0"]
        ]] as [String: Any]).jsonData())
        let aggregated = Data(#"{"totalCostCents":169097.256025,"totalInputTokens":"1000"}"#.utf8)

        let analytics = CursorAnalyticsFetcher.analytics(aggregatedData: aggregated, dailyData: daily)

        XCTAssertEqual(analytics?.dailyBuckets, [DailyTokens(day: "2026-11-20", tokens: 140)])
        XCTAssertEqual((analytics?.cost?.amountUSD ?? 0) as Decimal, Decimal(169097.256025) / 100)
        XCTAssertEqual(analytics?.cost?.kind, .metered)
        XCTAssertEqual(analytics?.cost?.period, .billingCycle)
    }

    func test_analytics_acceptsCostWithoutDailyRows() {
        let aggregated = Data(#"{"totalCostCents":"1250"}"#.utf8)
        let analytics = CursorAnalyticsFetcher.analytics(aggregatedData: aggregated, dailyData: nil)
        XCTAssertEqual(analytics?.cost?.amountUSD, Decimal(12.5))
        XCTAssertEqual(analytics?.dailyBuckets, [])
    }

    func test_analytics_rejectsEmptyPayloads() {
        XCTAssertNil(CursorAnalyticsFetcher.analytics(aggregatedData: Data("{}".utf8), dailyData: Data("{}".utf8)))
        XCTAssertNil(CursorAnalyticsFetcher.analytics(aggregatedData: nil, dailyData: nil))
    }
    func test_billingWindowMs_acceptsStringEncodedInt64() {
        let data = Data(#"{"startDateEpochMillis":"1790000000000","endDateEpochMillis":"1792000000000"}"#.utf8)

        let window = CursorAnalyticsFetcher.billingWindowMs(data: data)

        XCTAssertEqual(window?.start, 1_790_000_000_000)
        XCTAssertEqual(window?.end, 1_792_000_000_000)
    }

    func test_analytics_mergesDailyChunksAndSumsSameDay() {
        let dayMs = Int64(TokenAnalytics.date(fromDay: "2026-11-20")!.timeIntervalSince1970 * 1000)
        let first = Data((["dailySpend":[["day":"\(dayMs)","category":"a","totalTokens":"100"]]] as [String: Any]).jsonData())
        let second = Data((["dailySpend":[["day":"\(dayMs)","category":"b","totalTokens":"23"]]] as [String: Any]).jsonData())

        let analytics = CursorAnalyticsFetcher.analytics(aggregatedData: nil, dailyDataList: [first, second])

        XCTAssertEqual(analytics?.dailyBuckets, [DailyTokens(day: "2026-11-20", tokens: 123)])
    }

}

private extension Dictionary where Key == String, Value == Any {
    func jsonData() -> Data {
        (try? JSONSerialization.data(withJSONObject: self)) ?? Data()
    }
}
