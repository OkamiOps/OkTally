import XCTest
@testable import OkTally

final class UsageForecastSelectionTests: XCTestCase {
    private let resetAt = Date(timeIntervalSince1970: 1_800_086_400)

    private func forecast(
        providerId: String,
        windowLabel: String,
        gap: TimeInterval? = nil,
        state: UsageForecastState
    ) -> UsageForecast {
        UsageForecast(
            id: ForecastWindowID(providerId: providerId, windowLabel: windowLabel),
            cadence: .weekly,
            currentUsedPercent: 40,
            samples: [],
            ratePerDay: nil,
            safeRatePerDay: nil,
            exhaustionAt: nil,
            resetAt: resetAt,
            gap: gap,
            state: state
        )
    }

    private func dictionary(_ forecasts: [UsageForecast]) -> [ForecastWindowID: UsageForecast] {
        Dictionary(uniqueKeysWithValues: forecasts.map { ($0.id, $0) })
    }

    func test_automaticSelectsLargestPositiveGap() {
        let smallerRisk = forecast(
            providerId: "claude",
            windowLabel: "weekly",
            gap: 2 * 3_600,
            state: .onPace
        )
        let largestRisk = forecast(
            providerId: "cursor",
            windowLabel: "monthly",
            gap: 10 * 3_600,
            state: .slowDown
        )
        let safe = forecast(
            providerId: "codex",
            windowLabel: "weekly",
            gap: -1 * 3_600,
            state: .onPace
        )

        let selected = UsageForecastSelection.select(
            preferred: .automatic,
            forecasts: dictionary([smallerRisk, largestRisk, safe])
        )

        XCTAssertEqual(selected?.id, largestRisk.id)
    }

    func test_automaticSelectsSmallestAbsoluteSlackWhenAllPredictionsAreSafe() {
        let roomy = forecast(
            providerId: "claude",
            windowLabel: "weekly",
            gap: -12 * 3_600,
            state: .canAccelerate
        )
        let tightest = forecast(
            providerId: "cursor",
            windowLabel: "monthly",
            gap: -2 * 3_600,
            state: .canAccelerate
        )

        let selected = UsageForecastSelection.select(
            preferred: .automatic,
            forecasts: dictionary([roomy, tightest])
        )

        XCTAssertEqual(selected?.id, tightest.id)
    }

    func test_automaticSelectsCollectingWindowWithLongestObservedIntervalWithoutNumericForecast() {
        let shorter = forecast(
            providerId: "claude",
            windowLabel: "weekly",
            state: .collecting(observedHours: 2, sampleCount: 6)
        )
        let longer = forecast(
            providerId: "cursor",
            windowLabel: "monthly",
            state: .collecting(observedHours: 2.75, sampleCount: 5)
        )
        let unavailable = forecast(
            providerId: "mimo",
            windowLabel: "monthly",
            state: .unavailable
        )

        let selected = UsageForecastSelection.select(
            preferred: .automatic,
            forecasts: dictionary([shorter, longer, unavailable])
        )

        XCTAssertEqual(selected?.id, longer.id)
    }

    func test_manualExistingTargetWinsOverAutomaticRisk() {
        let automaticRisk = forecast(
            providerId: "claude",
            windowLabel: "weekly",
            gap: 12 * 3_600,
            state: .slowDown
        )
        let preferred = forecast(
            providerId: "cursor",
            windowLabel: "monthly",
            gap: -8 * 3_600,
            state: .canAccelerate
        )

        let selected = UsageForecastSelection.select(
            preferred: .window(providerId: "cursor", windowLabel: "monthly"),
            forecasts: dictionary([automaticRisk, preferred])
        )

        XCTAssertEqual(selected?.id, preferred.id)
    }

    func test_missingManualTargetFallsBackToAutomaticWithoutChangingPreference() {
        let automaticRisk = forecast(
            providerId: "claude",
            windowLabel: "weekly",
            gap: 12 * 3_600,
            state: .slowDown
        )
        let preferred = ForecastSlot.window(providerId: "cursor", windowLabel: "monthly")

        let selected = UsageForecastSelection.select(
            preferred: preferred,
            forecasts: dictionary([automaticRisk])
        )

        XCTAssertEqual(selected?.id, automaticRisk.id)
        XCTAssertEqual(preferred, .window(providerId: "cursor", windowLabel: "monthly"))
    }
}
