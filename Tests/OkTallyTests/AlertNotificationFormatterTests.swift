// Tests/OkTallyTests/AlertNotificationFormatterTests.swift
import XCTest
@testable import OkTally

final class AlertNotificationFormatterTests: XCTestCase {
    func test_percentageEvent_formatsTitleAndBody() {
        let event = AlertEvent(
            providerId: "claude",
            providerDisplayName: "Claude Code",
            windowLabel: "5h",
            threshold: .percentage(0.9),
            currentPercent: 92,
            currentRemaining: nil,
            resetAt: nil,
            isEstimated: false
        )
        let (title, body) = AlertNotificationFormatter.format(event)
        XCTAssertEqual(title, "Claude Code — 5h")
        XCTAssertTrue(body.contains("92%"))
    }

    func test_lowBalanceEvent_formatsBody() {
        let event = AlertEvent(
            providerId: "openrouter",
            providerDisplayName: "OpenRouter",
            windowLabel: "balance",
            threshold: .lowBalance(5),
            currentPercent: nil,
            currentRemaining: 3.25,
            resetAt: nil,
            isEstimated: false
        )
        let (title, body) = AlertNotificationFormatter.format(event)
        XCTAssertEqual(title, "OpenRouter — balance")
        XCTAssertTrue(body.contains("3.25"))
    }
}
