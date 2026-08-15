import XCTest
import CoreGraphics
@testable import OkTally

final class HeatmapLayoutTests: XCTestCase {
    private func metrics(_ width: CGFloat, maxWeeks: Int = 53) -> HeatmapMetrics {
        HeatmapLayout.metrics(availableWidth: width, gap: 2, minCell: 8, maxCell: 16, maxWeeks: maxWeeks)
    }

    func test_fillsTheAvailableWidth() {
        // O bug original: célula fixa de 10 pt deixava metade do card vazia.
        let m = metrics(600)
        let used = CGFloat(m.weeks) * m.cell + CGFloat(m.weeks - 1) * 2
        XCTAssertEqual(used, 600, accuracy: m.cell)
    }

    func test_cellNeverExceedsMax() {
        XCTAssertLessThanOrEqual(metrics(2000).cell, 16)
    }

    func test_cellNeverGoesBelowMin() {
        XCTAssertGreaterThanOrEqual(metrics(120).cell, 8)
    }

    func test_narrowWidthDropsWeeksInsteadOfShrinkingPastMin() {
        let narrow = metrics(120)
        let wide = metrics(600)
        XCTAssertLessThan(narrow.weeks, wide.weeks)
    }

    func test_neverExceedsMaxWeeks() {
        XCTAssertLessThanOrEqual(metrics(4000, maxWeeks: 53).weeks, 53)
    }

    func test_alwaysYieldsAtLeastOneWeek() {
        XCTAssertGreaterThanOrEqual(metrics(0).weeks, 1)
        XCTAssertGreaterThanOrEqual(metrics(-50).weeks, 1)
    }
}
