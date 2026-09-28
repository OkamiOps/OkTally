import XCTest
import SwiftUI
@testable import OkTally

/// Contas extras herdam a identidade visual e as regras do tipo — nada de cor genérica
/// ou de Codex tratado como "outro provedor" só porque o id ganhou sufixo.
final class ProviderPaletteTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AccountDirectoryHolder.current = .empty
    }

    private func rolling(_ used: Double, hours: Double = 5) -> QuotaShape {
        .rollingWindow(used: used, limit: 100, windowStart: Date(),
                       resetAt: Date().addingTimeInterval(hours * 3600))
    }

    func test_palette_extraInstanceSharesKindColorAndGlyph() {
        XCTAssertEqual(ProviderPalette.color(for: "claude#abc123"), ProviderPalette.color(for: "claude"))
        XCTAssertEqual(ProviderPalette.color(for: "cursor-grokbot#abc123"), ProviderPalette.color(for: "cursor-grokbot"))
        XCTAssertEqual(ProviderPalette.glyph(forId: "cursor-grokbot#abc123"), "GB")
        XCTAssertEqual(ProviderPalette.glyph(forId: "codex#abc123"), "X")
    }

    func test_codexWeeklyPriority_appliesToExtraCodexInstance() {
        let quotas = [
            QuotaWindow(label: "GPT-5.3-Codex-Spark (5h)", shape: rolling(90)),
            QuotaWindow(label: "weekly", shape: rolling(40, hours: 7 * 24))
        ]
        XCTAssertEqual(PopoverLayout.primaryWindow(providerId: "codex#abc123", quotas: quotas)?.label, "weekly")
    }

    func test_popoverHero_automaticRepresentsExtraCodexWithGeneralWeekly() {
        let codex = ProviderSnapshot(providerId: "codex#abc123", fetchedAt: Date(), quotas: [
            QuotaWindow(label: "semanal", shape: rolling(44, hours: 7 * 24)),
            QuotaWindow(label: "GPT-5.3-Codex-Spark (5h)", shape: rolling(97))
        ], usageDetail: nil)
        let claude = ProviderSnapshot(providerId: "claude", fetchedAt: Date(), quotas: [
            QuotaWindow(label: "5h", shape: rolling(80))
        ], usageDetail: nil)
        let hero = QuotaSlotResolver.popoverHero(slot: .automatic,
                                                 snapshots: ["codex#abc123": codex, "claude": claude],
                                                 providerOrder: ["claude", "codex#abc123"])
        XCTAssertEqual(hero?.providerId, "claude")
    }
}
