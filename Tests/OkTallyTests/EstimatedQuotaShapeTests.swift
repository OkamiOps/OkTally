// Tests/OkTallyTests/EstimatedQuotaShapeTests.swift
import XCTest
@testable import OkTally

final class EstimatedQuotaShapeTests: XCTestCase {
    func test_estimated_usedPercent_withLimit() {
        let shape = QuotaShape.estimated(used: 30, limit: 60, basis: .localTokenCount, resetAt: nil)
        XCTAssertEqual(shape.usedPercent, 50)
    }

    func test_estimated_usedPercent_nilWithoutLimit() {
        let shape = QuotaShape.estimated(used: 30, limit: nil, basis: .reactiveRateLimit, resetAt: nil)
        XCTAssertNil(shape.usedPercent)
    }

    func test_estimated_resetAt_propagates() {
        let reset = Date(timeIntervalSince1970: 5000)
        let shape = QuotaShape.estimated(used: 1, limit: 2, basis: .localTokenCount, resetAt: reset)
        XCTAssertEqual(shape.resetAt, reset)
    }

    func test_estimated_isEstimatedTrue_othersFalse() {
        XCTAssertTrue(QuotaShape.estimated(used: 1, limit: 2, basis: .localTokenCount, resetAt: nil).isEstimated)
        XCTAssertFalse(QuotaShape.rollingWindow(used: 1, limit: 2, windowStart: Date(), resetAt: Date()).isEstimated)
    }

    func test_estimated_codableRoundTrip() throws {
        let shape = QuotaShape.estimated(used: 12, limit: 40, basis: .reactiveRateLimit, resetAt: Date(timeIntervalSince1970: 111))
        let decoded = try JSONDecoder().decode(QuotaShape.self, from: JSONEncoder().encode(shape))
        XCTAssertEqual(decoded, shape)
    }

    func test_formatter_estimated_prefixesTilde() {
        let shape = QuotaShape.estimated(used: 42, limit: 100, basis: .localTokenCount, resetAt: nil)
        XCTAssertEqual(QuotaDisplayFormatter.valueText(for: shape), "~42%")
    }

    func test_formatter_estimated_noLimit_showsUsedWithBasis() {
        let shape = QuotaShape.estimated(used: 3, limit: nil, basis: .reactiveRateLimit, resetAt: nil)
        XCTAssertEqual(QuotaDisplayFormatter.valueText(for: shape), "~ (limite atingido)")
    }

    func test_alertFormatter_estimatedEvent_prefixesBody() {
        let event = AlertEvent(providerId: "mimo", providerDisplayName: "MiMo", windowLabel: "mensal", threshold: .percentage(0.9), currentPercent: 91, currentRemaining: nil, resetAt: nil, isEstimated: true)
        let (_, body) = AlertNotificationFormatter.format(event)
        XCTAssertTrue(body.hasPrefix("Estimado: "))
    }
}
