// Tests/OkTallyTests/MenuBarStateCalculatorTests.swift
import XCTest
@testable import OkTally

final class MenuBarStateCalculatorTests: XCTestCase {
    private func snapshot(percent: Double) -> ProviderSnapshot {
        ProviderSnapshot(
            providerId: "p",
            fetchedAt: Date(),
            quotas: [QuotaWindow(label: "w", shape: .rollingWindow(used: percent, limit: 100, windowStart: Date(), resetAt: Date()))],
            usageDetail: nil
        )
    }

    func test_worstState_picksHighestPercentAcrossSnapshots() {
        let state = MenuBarStateCalculator.worstState(snapshots: [snapshot(percent: 30), snapshot(percent: 82)], hasAnyError: false)
        XCTAssertEqual(state.percent, 82)
    }

    func test_worstState_noSnapshots_noPercent() {
        let state = MenuBarStateCalculator.worstState(snapshots: [], hasAnyError: false)
        XCTAssertNil(state.percent)
    }

    func test_colorName_thresholds() {
        XCTAssertEqual(MenuBarStateCalculator.colorName(for: MenuBarState(percent: 50, hasError: false)), "green")
        XCTAssertEqual(MenuBarStateCalculator.colorName(for: MenuBarState(percent: 75, hasError: false)), "yellow")
        XCTAssertEqual(MenuBarStateCalculator.colorName(for: MenuBarState(percent: 95, hasError: false)), "red")
        XCTAssertEqual(MenuBarStateCalculator.colorName(for: MenuBarState(percent: nil, hasError: false)), "green")
        XCTAssertEqual(MenuBarStateCalculator.colorName(for: MenuBarState(percent: nil, hasError: true)), "gray")
    }

    func test_labelText_formatsPercentOrFallback() {
        XCTAssertEqual(MenuBarStateCalculator.labelText(for: MenuBarState(percent: 82.6, hasError: false)), "83%")
        XCTAssertEqual(MenuBarStateCalculator.labelText(for: MenuBarState(percent: nil, hasError: false)), "OK")
        XCTAssertEqual(MenuBarStateCalculator.labelText(for: MenuBarState(percent: nil, hasError: true)), "!")
    }
}
