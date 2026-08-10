import XCTest
@testable import OkTally

final class MenuBarLabelModelTests: XCTestCase {
    private func snapshot(_ id: String, _ quotas: [QuotaWindow]) -> ProviderSnapshot {
        ProviderSnapshot(providerId: id, fetchedAt: Date(), quotas: quotas, usageDetail: nil)
    }
    private func window(_ label: String, usedPercent: Double) -> QuotaWindow {
        QuotaWindow(label: label, shape: .rollingWindow(
            used: usedPercent, limit: 100, windowStart: Date(), resetAt: Date().addingTimeInterval(3600)))
    }

    func test_pinnedPercentWindow_showsRemainingWithProviderGlyph() {
        let segs = MenuBarLabelModel.segments(
            pins: [.init(providerId: "claude", windowLabel: "5h")],
            snapshots: ["claude": snapshot("claude", [window("5h", usedPercent: 22)])],
            hasAnyError: false)
        XCTAssertEqual(segs, [MenuBarSegment(glyph: "C", providerId: "claude", text: "78", danger: .ok)])
    }

    func test_dangerLevels_matchQuotaPresentationThresholds() {
        XCTAssertEqual(MenuBarLabelModel.danger(remaining: 0.31), .ok)
        XCTAssertEqual(MenuBarLabelModel.danger(remaining: 0.30), .warn)
        XCTAssertEqual(MenuBarLabelModel.danger(remaining: 0.10), .critical)
    }

    func test_pinnedBalance_showsCompactValue() {
        let w = QuotaWindow(label: "balance", shape: .creditBalance(remaining: Decimal(19.82), currency: "USD"))
        let segs = MenuBarLabelModel.segments(
            pins: [.init(providerId: "openrouter", windowLabel: "balance")],
            snapshots: ["openrouter": snapshot("openrouter", [w])],
            hasAnyError: false)
        XCTAssertEqual(segs.first?.text, "19.8$")
        XCTAssertEqual(segs.first?.danger, .neutral)
    }

    func test_orphanPin_isOmitted() {
        let segs = MenuBarLabelModel.segments(
            pins: [.init(providerId: "gone", windowLabel: "x"),
                   .init(providerId: "claude", windowLabel: "5h")],
            snapshots: ["claude": snapshot("claude", [window("5h", usedPercent: 95)])],
            hasAnyError: false)
        XCTAssertEqual(segs, [MenuBarSegment(glyph: "C", providerId: "claude", text: "5", danger: .critical)])
    }

    func test_noPins_automatic_worstWindowNoGlyph() {
        let segs = MenuBarLabelModel.segments(
            pins: [],
            snapshots: ["claude": snapshot("claude", [window("5h", usedPercent: 22)]),
                        "codex": snapshot("codex", [window("semanal", usedPercent: 80)])],
            hasAnyError: false)
        XCTAssertEqual(segs, [MenuBarSegment(glyph: nil, providerId: nil, text: "20", danger: .warn)])
    }

    func test_noPins_noData_errorShowsBang_elseOK() {
        XCTAssertEqual(MenuBarLabelModel.segments(pins: [], snapshots: [:], hasAnyError: true),
                       [MenuBarSegment(glyph: nil, providerId: nil, text: "!", danger: .neutral)])
        XCTAssertEqual(MenuBarLabelModel.segments(pins: [], snapshots: [:], hasAnyError: false),
                       [MenuBarSegment(glyph: nil, providerId: nil, text: "OK", danger: .neutral)])
    }

    func test_glyphs_areDistinctAcrossProviders() {
        let ids = ["claude", "codex", "supergrok", "cursor", "openrouter", "minimax", "opencode", "mimo"]
        let glyphs = ids.map { ProviderPalette.glyph(forId: $0) }
        XCTAssertEqual(Set(glyphs).count, ids.count, "menu bar glyphs must be distinct: \(glyphs)")
    }
}
