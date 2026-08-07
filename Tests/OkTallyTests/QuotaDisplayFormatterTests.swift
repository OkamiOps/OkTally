// Tests/OkTallyTests/QuotaDisplayFormatterTests.swift
import XCTest
@testable import OkTally

final class QuotaDisplayFormatterTests: XCTestCase {
    func test_rollingWindow_showsPercent() {
        let shape = QuotaShape.rollingWindow(used: 42, limit: 100, windowStart: Date(), resetAt: Date())
        XCTAssertEqual(QuotaDisplayFormatter.valueText(for: shape), "42%")
    }

    func test_creditBalance_showsAmountAndCurrency() {
        let shape = QuotaShape.creditBalance(remaining: 37.5, currency: "USD")
        XCTAssertEqual(QuotaDisplayFormatter.valueText(for: shape), "37.5 USD")
    }

    func test_meteredOnly_showsDollarCost() {
        let shape = QuotaShape.meteredOnly(costAccrued: 3.2)
        XCTAssertEqual(QuotaDisplayFormatter.valueText(for: shape), "$3.2")
    }
}
