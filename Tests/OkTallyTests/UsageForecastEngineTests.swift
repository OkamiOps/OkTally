import XCTest
@testable import OkTally

final class UsageForecastEngineTests: XCTestCase {
    /// Fixed so the forecast never depends on the machine clock.
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let hour: TimeInterval = 3_600

    private var risingSamples: [(Double, Double)] {
        [(-6, 10), (-5, 15), (-4, 20), (-3, 25), (-2, 30), (0, 40)]
    }

    private func assertApproximatelyEqual(
        _ actual: Double?,
        _ expected: Double,
        accuracy: Double = 0.0001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actual else {
            return XCTFail("Expected a numeric forecast value", file: file, line: line)
        }
        XCTAssertEqual(actual, expected, accuracy: accuracy, file: file, line: line)
    }

    private func window(
        used: Double,
        resetAt: Date,
        label: String = "weekly",
        cadence: RenewalCadence? = .weekly
    ) -> QuotaWindow {
        QuotaWindow(
            label: label,
            shape: .periodicCounter(used: used, limit: 100, resetAt: resetAt),
            renewalCadence: cadence
        )
    }

    private func snapshot(
        hoursFromNow: Double,
        used: Double,
        resetAt: Date,
        providerId: String = "claude",
        label: String = "weekly"
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            providerId: providerId,
            fetchedAt: now.addingTimeInterval(hoursFromNow * hour),
            quotas: [window(used: used, resetAt: resetAt, label: label)],
            usageDetail: nil
        )
    }

    private func forecast(
        currentUsed: Double = 40,
        resetInHours: Double = 24,
        cadence: RenewalCadence? = .weekly,
        samples: [(Double, Double)]
    ) -> UsageForecast {
        let resetAt = now.addingTimeInterval(resetInHours * hour)
        return UsageForecastEngine.forecast(
            providerId: "claude",
            current: window(used: currentUsed, resetAt: resetAt, cadence: cadence),
            snapshots: samples.map { snapshot(hoursFromNow: $0.0, used: $0.1, resetAt: resetAt) },
            now: now
        )
    }

    func test_forecast_slowDown_whenExhaustionIsMoreThanSixHoursBeforeReset() {
        let forecast = forecast(samples: risingSamples)

        XCTAssertEqual(forecast.id, ForecastWindowID(providerId: "claude", windowLabel: "weekly"))
        XCTAssertEqual(forecast.cadence, .some(.weekly))
        XCTAssertEqual(forecast.currentUsedPercent, 40, accuracy: 0.0001)
        XCTAssertEqual(forecast.samples.count, 6)
        assertApproximatelyEqual(forecast.ratePerDay, 120)
        assertApproximatelyEqual(forecast.safeRatePerDay, 60)
        XCTAssertEqual(forecast.exhaustionAt, now.addingTimeInterval(12 * hour))
        XCTAssertEqual(forecast.resetAt, now.addingTimeInterval(24 * hour))
        assertApproximatelyEqual(forecast.gap, 12 * hour)
        XCTAssertEqual(forecast.state, .slowDown)
    }

    func test_forecast_onPace_whenExhaustionIsWithinSixHoursOfReset() {
        let forecast = forecast(resetInHours: 18, samples: risingSamples)

        assertApproximatelyEqual(forecast.gap, 6 * hour)
        XCTAssertEqual(forecast.state, .onPace)
    }

    func test_forecast_canAccelerate_whenExhaustionIsMoreThanSixHoursAfterReset() {
        let forecast = forecast(resetInHours: 4, samples: risingSamples)

        assertApproximatelyEqual(forecast.gap, -8 * hour)
        XCTAssertEqual(forecast.state, .canAccelerate)
    }

    func test_forecast_noExhaustion_forZeroRateAfterMatureSeries() {
        let forecast = forecast(samples: [(-6, 40), (-5, 40), (-4, 40), (-3, 40), (-2, 40), (0, 40)])

        assertApproximatelyEqual(forecast.ratePerDay, 0)
        XCTAssertNil(forecast.exhaustionAt)
        XCTAssertNil(forecast.gap)
        XCTAssertEqual(forecast.state, .noExhaustion)
    }

    func test_forecast_collectsUntilAtLeastThreeHoursHaveBeenObserved() {
        let forecast = forecast(samples: [(-2, 10), (-1.5, 15), (-1, 20), (-0.5, 25), (-0.25, 30), (0, 40)])

        XCTAssertEqual(forecast.state, .collecting(observedHours: 2, sampleCount: 6))
        XCTAssertNil(forecast.ratePerDay)
        XCTAssertNil(forecast.exhaustionAt)
    }

    func test_forecast_collectsUntilItHasAtLeastSixSamples() {
        let forecast = forecast(samples: [(-4, 10), (-3, 20), (-2, 25), (-1, 30), (0, 40)])

        XCTAssertEqual(forecast.state, .collecting(observedHours: 4, sampleCount: 5))
        XCTAssertNil(forecast.ratePerDay)
        XCTAssertNil(forecast.exhaustionAt)
    }

    func test_forecast_noExhaustion_forSubHalfPointChangeAfterMatureSeries() {
        let forecast = forecast(samples: [(-6, 40), (-5, 40.1), (-4, 40.2), (-3, 40.3), (-2, 40.35), (0, 40.4)])

        XCTAssertEqual(forecast.state, .noExhaustion)
        XCTAssertNil(forecast.exhaustionAt)
        XCTAssertNil(forecast.gap)
    }

    func test_forecast_treatsNegativeCorrectionAsZeroConsumption() {
        let forecast = forecast(samples: [(-6, 60), (-5, 58), (-4, 56), (-3, 54), (-2, 52), (0, 50)])

        assertApproximatelyEqual(forecast.ratePerDay, 0)
        XCTAssertEqual(forecast.state, .noExhaustion)
        XCTAssertNil(forecast.exhaustionAt)
    }

    func test_forecast_sortsSamplesAndIgnoresOtherCyclesFutureAndExpiredHistory() {
        let resetAt = now.addingTimeInterval(24 * hour)
        let current = window(used: 40, resetAt: resetAt)
        var snapshots = risingSamples.reversed().map {
            snapshot(hoursFromNow: $0.0, used: $0.1, resetAt: resetAt)
        }
        snapshots.append(snapshot(hoursFromNow: -4, used: 95, resetAt: resetAt.addingTimeInterval(7 * 24 * hour)))
        snapshots.append(snapshot(hoursFromNow: -25, used: 0, resetAt: resetAt))
        snapshots.append(snapshot(hoursFromNow: 1, used: 100, resetAt: resetAt))

        let forecast = UsageForecastEngine.forecast(
            providerId: "claude",
            current: current,
            snapshots: snapshots,
            now: now
        )

        XCTAssertEqual(forecast.samples.map(\.date), forecast.samples.map(\.date).sorted())
        XCTAssertEqual(forecast.samples.map(\.usedPercent), [10, 15, 20, 25, 30, 40])
        assertApproximatelyEqual(forecast.ratePerDay, 120)
        XCTAssertEqual(forecast.state, .slowDown)
    }

    func test_forecast_isUnavailable_withoutFutureReset() {
        let missingReset = QuotaWindow(
            label: "weekly",
            shape: .creditBalance(remaining: 10, currency: "USD"),
            renewalCadence: .weekly
        )
        let expiredReset = window(used: 40, resetAt: now.addingTimeInterval(-1))

        let missing = UsageForecastEngine.forecast(providerId: "claude", current: missingReset, snapshots: [], now: now)
        let expired = UsageForecastEngine.forecast(providerId: "claude", current: expiredReset, snapshots: [], now: now)

        XCTAssertEqual(missing.state, .unavailable)
        XCTAssertEqual(missing.cadence, .some(.weekly))
        XCTAssertNil(missing.resetAt)
        XCTAssertEqual(expired.state, .unavailable)
        XCTAssertEqual(expired.cadence, .some(.weekly))
        XCTAssertEqual(expired.resetAt, now.addingTimeInterval(-1))
        XCTAssertNotEqual(expired.resetAt, now)
    }

    func test_forecast_doesNotInventCadenceOrResetWhenBothAreAbsent() {
        let noCadenceOrReset = QuotaWindow(
            label: "balance",
            shape: .creditBalance(remaining: 10, currency: "USD")
        )

        let forecast = UsageForecastEngine.forecast(
            providerId: "openrouter",
            current: noCadenceOrReset,
            snapshots: [],
            now: now
        )

        XCTAssertEqual(forecast.state, .unavailable)
        XCTAssertNil(forecast.cadence)
        XCTAssertNil(forecast.resetAt)
        XCTAssertNil(forecast.ratePerDay)
        XCTAssertNil(forecast.safeRatePerDay)
        XCTAssertNil(forecast.exhaustionAt)
        XCTAssertNil(forecast.gap)
    }

    func test_forecast_isUnavailable_forMissingCadenceEstimatedAndNonPercentageWindows() {
        let resetAt = now.addingTimeInterval(24 * hour)
        let missingCadence = window(used: 40, resetAt: resetAt, cadence: nil)
        let estimated = QuotaWindow(
            label: "weekly",
            shape: .estimated(used: 40, limit: 100, basis: .localTokenCount, resetAt: resetAt),
            renewalCadence: .weekly
        )
        let metered = QuotaWindow(
            label: "weekly",
            shape: .meteredOnly(costAccrued: 40),
            renewalCadence: .weekly
        )

        let missingCadenceForecast = UsageForecastEngine.forecast(providerId: "claude", current: missingCadence, snapshots: [], now: now)

        XCTAssertEqual(missingCadenceForecast.state, .unavailable)
        XCTAssertNil(missingCadenceForecast.cadence)
        XCTAssertEqual(missingCadenceForecast.resetAt, resetAt)
        XCTAssertEqual(UsageForecastEngine.forecast(providerId: "claude", current: estimated, snapshots: [], now: now).state, .unavailable)
        XCTAssertEqual(UsageForecastEngine.forecast(providerId: "claude", current: metered, snapshots: [], now: now).state, .unavailable)
    }

    func test_forecast_acceptsMonthlyRealPercentageWindow() {
        let forecast = forecast(cadence: .monthly, samples: risingSamples)

        XCTAssertEqual(forecast.cadence, .some(.monthly))
        XCTAssertEqual(forecast.state, .slowDown)
    }

    func test_forecast_clampsFullyConsumedAndOverLimitCurrentUsage() {
        for currentUsed in [100.0, 125.0] {
            let forecast = forecast(
                currentUsed: currentUsed,
                samples: [(-6, 70), (-5, 76), (-4, 82), (-3, 88), (-2, 94), (0, 100)]
            )

            XCTAssertEqual(forecast.currentUsedPercent, 100, accuracy: 0.0001)
            assertApproximatelyEqual(forecast.safeRatePerDay, 0)
            XCTAssertEqual(forecast.exhaustionAt, now)
            XCTAssertEqual(forecast.state, .slowDown)
        }
    }
}
