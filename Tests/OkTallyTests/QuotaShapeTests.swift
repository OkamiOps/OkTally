// Tests/OkTallyTests/QuotaShapeTests.swift
import XCTest
@testable import OkTally

final class QuotaShapeTests: XCTestCase {
    func test_rollingWindow_usedPercent() {
        let start = Date()
        let reset = start.addingTimeInterval(3600)
        let shape = QuotaShape.rollingWindow(used: 42, limit: 100, windowStart: start, resetAt: reset)
        XCTAssertEqual(shape.usedPercent, 42)
        XCTAssertEqual(shape.resetAt, reset)
    }

    func test_periodicCounter_usedPercent() {
        let reset = Date()
        let shape = QuotaShape.periodicCounter(used: 30, limit: 60, resetAt: reset)
        XCTAssertEqual(shape.usedPercent, 50)
        XCTAssertEqual(shape.resetAt, reset)
    }

    func test_creditBalance_hasNoPercentOrReset() {
        let shape = QuotaShape.creditBalance(remaining: 12.5, currency: "USD")
        XCTAssertNil(shape.usedPercent)
        XCTAssertNil(shape.resetAt)
    }

    func test_meteredOnly_hasNoPercentOrReset() {
        let shape = QuotaShape.meteredOnly(costAccrued: 3.2)
        XCTAssertNil(shape.usedPercent)
        XCTAssertNil(shape.resetAt)
    }

    func test_rollingWindow_codableRoundTrip() throws {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let reset = Date(timeIntervalSince1970: 1_003_600)
        let original = QuotaShape.rollingWindow(used: 10, limit: 20, windowStart: start, resetAt: reset)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(QuotaShape.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_creditBalance_codableRoundTrip() throws {
        let original = QuotaShape.creditBalance(remaining: 7.75, currency: "USD")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(QuotaShape.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_periodicCounter_codableRoundTrip() throws {
        let reset = Date(timeIntervalSince1970: 1_003_600)
        let original = QuotaShape.periodicCounter(used: 15, limit: 30, resetAt: reset)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(QuotaShape.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_meteredOnly_codableRoundTrip() throws {
        let original = QuotaShape.meteredOnly(costAccrued: 4.5)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(QuotaShape.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
