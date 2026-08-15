import XCTest
@testable import OkTally

final class TrendSeriesTests: XCTestCase {
    /// 2026-08-15 12:00 UTC, fixo — nada aqui pode depender do relógio real.
    private let now = Date(timeIntervalSince1970: 1_776_254_400)

    private func day(_ offset: Int) -> String {
        let date = Calendar(identifier: .gregorian).date(byAdding: .day, value: -offset, to: now)!
        return TokenAnalytics.dayKey(date)
    }

    private func analytics(_ pairs: [(Int, Int)]) -> TokenAnalytics {
        TokenAnalytics(dailyBuckets: pairs.map { DailyTokens(day: day($0.0), tokens: $0.1) })
    }

    func test_points_keepsOnlyDaysInsideTheWindow() {
        let source = ["codex": analytics([(0, 100), (29, 200), (45, 999)])]
        let points = TrendSeries.points(byProvider: source, window: .days30, now: now)
        XCTAssertEqual(points.count, 2)
        XCTAssertFalse(points.contains { $0.day == day(45) })
    }

    func test_points_tagsEachPointWithItsProvider() {
        let source = [
            "codex": analytics([(1, 10)]),
            "claude": analytics([(1, 20)]),
        ]
        let points = TrendSeries.points(byProvider: source, window: .days30, now: now)
        XCTAssertEqual(Set(points.map(\.providerId)), ["codex", "claude"])
        XCTAssertEqual(points.first { $0.providerId == "claude" }?.tokens, 20)
    }

    func test_points_areSortedByDayAscending() {
        let source = ["codex": analytics([(3, 30), (1, 10), (2, 20)])]
        let days = TrendSeries.points(byProvider: source, window: .days30, now: now).map(\.day)
        XCTAssertEqual(days, days.sorted())
    }

    func test_dailyTotals_fillsMissingDaysWithZero() {
        // Sem o preenchimento o gráfico de área "pula" o dia sem uso e mente sobre o ritmo.
        let totals = TrendSeries.dailyTotals(analytics([(0, 50), (2, 70)]), lastDays: 3, now: now)
        XCTAssertEqual(totals.count, 3)
        XCTAssertEqual(totals.map(\.tokens), [70, 0, 50])
    }

    func test_delta_returnsSignedFraction() {
        XCTAssertEqual(TrendSeries.delta(current: 150, previous: 100), 0.5)
        XCTAssertEqual(TrendSeries.delta(current: 50, previous: 100), -0.5)
    }

    func test_delta_isNilWhenPreviousIsZero() {
        // Crescer a partir de zero não é "+∞ %" — é ausência de comparação.
        XCTAssertNil(TrendSeries.delta(current: 10, previous: 0))
    }

    func test_share_sumsTokensPerProviderDescending() {
        let source = [
            "codex": analytics([(0, 300), (1, 100)]),
            "claude": analytics([(0, 50)]),
        ]
        let share = TrendSeries.share(byProvider: source, lastDays: 30, now: now)
        XCTAssertEqual(share.map(\.providerId), ["codex", "claude"])
        XCTAssertEqual(share.first?.tokens, 400)
    }

    func test_share_omitsProvidersWithoutTokens() {
        let source = ["codex": analytics([(0, 10)]), "mimo": analytics([])]
        let share = TrendSeries.share(byProvider: source, lastDays: 30, now: now)
        XCTAssertEqual(share.map(\.providerId), ["codex"])
    }
}
