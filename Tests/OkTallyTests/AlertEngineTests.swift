// Tests/OkTallyTests/AlertEngineTests.swift
import XCTest
@testable import OkTally

final class AlertEngineTests: XCTestCase {
    let engine = AlertEngine()

    private func snapshot(percent: Double, label: String = "5h", resetAt: Date = Date()) -> ProviderSnapshot {
        ProviderSnapshot(
            providerId: "claude",
            fetchedAt: Date(),
            quotas: [QuotaWindow(label: label, shape: .rollingWindow(used: percent, limit: 100, windowStart: Date(), resetAt: resetAt))],
            usageDetail: nil
        )
    }

    func test_firstObservationAboveThreshold_firesAlert() {
        let current = snapshot(percent: 75)
        let events = engine.evaluate(providerId: "claude", providerDisplayName: "Claude Code", previous: nil, current: current, thresholds: [:])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.threshold, .percentage(0.7))
        XCTAssertEqual(events.first?.currentPercent, 75)
    }

    func test_stayingAboveThreshold_doesNotRefire() {
        let previous = snapshot(percent: 75)
        let current = snapshot(percent: 78)
        let events = engine.evaluate(providerId: "claude", providerDisplayName: "Claude Code", previous: previous, current: current, thresholds: [:])
        XCTAssertTrue(events.isEmpty)
    }

    func test_crossingMultipleThresholds_firesEachOnce() {
        let previous = snapshot(percent: 60)
        let current = snapshot(percent: 95)
        let events = engine.evaluate(providerId: "claude", providerDisplayName: "Claude Code", previous: previous, current: current, thresholds: [:])
        XCTAssertEqual(Set(events.map { $0.threshold }), Set([.percentage(0.7), .percentage(0.9)]))
    }

    func test_lowBalanceCrossingDownward_firesAlert() {
        let previous = ProviderSnapshot(providerId: "openrouter", fetchedAt: Date(), quotas: [QuotaWindow(label: "balance", shape: .creditBalance(remaining: 10, currency: "USD"))], usageDetail: nil)
        let current = ProviderSnapshot(providerId: "openrouter", fetchedAt: Date(), quotas: [QuotaWindow(label: "balance", shape: .creditBalance(remaining: 3, currency: "USD"))], usageDetail: nil)
        let events = engine.evaluate(providerId: "openrouter", providerDisplayName: "OpenRouter", previous: previous, current: current, thresholds: [:])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.currentRemaining, 3)
    }

    func test_meteredOnly_neverFires() {
        let current = ProviderSnapshot(providerId: "x", fetchedAt: Date(), quotas: [QuotaWindow(label: "spend", shape: .meteredOnly(costAccrued: 999))], usageDetail: nil)
        let events = engine.evaluate(providerId: "x", providerDisplayName: "X", previous: nil, current: current, thresholds: [:])
        XCTAssertTrue(events.isEmpty)
    }

    func test_customThresholdOverridesDefault() {
        let current = snapshot(percent: 55)
        let events = engine.evaluate(providerId: "claude", providerDisplayName: "Claude Code", previous: nil, current: current, thresholds: ["5h": [.percentage(0.5)]])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.threshold, .percentage(0.5))
    }
}
