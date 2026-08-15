// Tests/OkTallyTests/PopoverLayoutTests.swift
import XCTest
@testable import OkTally

final class PopoverLayoutTests: XCTestCase {
    private func rolling(_ used: Double, hours: Double = 5) -> QuotaShape {
        .rollingWindow(used: used, limit: 100, windowStart: Date(),
                       resetAt: Date().addingTimeInterval(hours * 3600))
    }

    func test_orderedWindows_putsTightestFirst() {
        let windows = [
            QuotaWindow(label: "weekly", shape: rolling(10)),
            QuotaWindow(label: "5h", shape: rolling(80)),
            QuotaWindow(label: "monthly", shape: rolling(40))
        ]
        XCTAssertEqual(PopoverLayout.orderedWindows(windows).map(\.label), ["5h", "monthly", "weekly"])
    }

    /// A balance has no "tightness" to compare — it must not be treated as 0% left and
    /// steal the row's bar from a real percentage window.
    func test_orderedWindows_sinksBalancesToTheEnd() {
        let windows = [
            QuotaWindow(label: "balance", shape: .creditBalance(remaining: 19.82, currency: "USD")),
            QuotaWindow(label: "5h", shape: rolling(90))
        ]
        XCTAssertEqual(PopoverLayout.orderedWindows(windows).map(\.label), ["5h", "balance"])
    }

    func test_orderedWindows_isStableForEqualRemaining() {
        let windows = [
            QuotaWindow(label: "a", shape: rolling(50)),
            QuotaWindow(label: "b", shape: rolling(50))
        ]
        XCTAssertEqual(PopoverLayout.orderedWindows(windows).map(\.label), ["a", "b"])
    }

    /// The popover prints the number once (36pt) and the word "restante" beside it, so
    /// the value helper must not carry the word itself.
    func test_remainingValueText_isJustTheNumber() {
        XCTAssertEqual(QuotaPresentation.remainingValueText(rolling(74)), "26%")
        XCTAssertEqual(
            QuotaPresentation.remainingValueText(
                .estimated(used: 38.4, limit: 100, basis: .localTokenCount, resetAt: nil)),
            "~62%")
        XCTAssertEqual(
            QuotaPresentation.remainingValueText(.creditBalance(remaining: 19.82, currency: "USD")),
            "19.82 USD")
    }

    /// The dense rows use the bare countdown; the hero keeps the full sentence. Both come
    /// from the same clock so they can never disagree.
    func test_resetCompactText_hasNoSentenceAround() throws {
        let now = Date()
        let shape = QuotaShape.rollingWindow(used: 10, limit: 100, windowStart: now,
                                             resetAt: now.addingTimeInterval(3 * 3600 + 25 * 60))
        let compact = try XCTUnwrap(QuotaPresentation.resetCompactText(shape, now: now))
        XCTAssertFalse(compact.contains("Reseta"))
        XCTAssertFalse(compact.contains("Resets"))
        let full = try XCTUnwrap(QuotaPresentation.resetText(shape, now: now))
        XCTAssertTrue(full.hasSuffix(compact), "\(full) deveria terminar com \(compact)")
    }

    func test_resetCompactText_nilWhenResetIsPastOrImminent() {
        let now = Date()
        XCTAssertNil(QuotaPresentation.resetCompactText(
            .rollingWindow(used: 10, limit: 100, windowStart: now, resetAt: now.addingTimeInterval(-60)), now: now))
        XCTAssertNil(QuotaPresentation.resetCompactText(
            .creditBalance(remaining: 1, currency: "USD"), now: now))
    }
}
