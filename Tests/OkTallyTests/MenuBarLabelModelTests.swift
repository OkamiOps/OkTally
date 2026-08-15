import XCTest
@testable import OkTally

final class MenuBarLabelModelTests: XCTestCase {
    private func snapshot(_ id: String, _ quotas: [QuotaWindow]) -> ProviderSnapshot {
        ProviderSnapshot(providerId: id, fetchedAt: Date(), quotas: quotas, usageDetail: nil)
    }
    private func window(_ label: String, usedPercent: Double, resetIn: TimeInterval = 3600) -> QuotaWindow {
        QuotaWindow(label: label, shape: .rollingWindow(
            used: usedPercent, limit: 100, windowStart: Date(), resetAt: Date().addingTimeInterval(resetIn)))
    }

    func test_pinnedPercentWindow_showsRemainingWithProviderGlyph() {
        let segment = MenuBarLabelModel.criticalSegment(
            pins: [.init(providerId: "claude", windowLabel: "5h")],
            snapshots: ["claude": snapshot("claude", [window("5h", usedPercent: 22)])],
            hasAnyError: false)
        XCTAssertEqual(segment, MenuBarSegment(glyph: "C", providerId: "claude", text: "78", danger: .ok))
    }

    func test_dangerLevels_matchQuotaPresentationThresholds() {
        XCTAssertEqual(MenuBarLabelModel.danger(remaining: 0.31), .ok)
        XCTAssertEqual(MenuBarLabelModel.danger(remaining: 0.30), .warn)
        XCTAssertEqual(MenuBarLabelModel.danger(remaining: 0.10), .critical)
    }

    func test_pinnedBalance_showsCompactValue() {
        let w = QuotaWindow(label: "balance", shape: .creditBalance(remaining: Decimal(19.82), currency: "USD"))
        let segment = MenuBarLabelModel.criticalSegment(
            pins: [.init(providerId: "openrouter", windowLabel: "balance")],
            snapshots: ["openrouter": snapshot("openrouter", [w])],
            hasAnyError: false)
        XCTAssertEqual(segment.text, "19.8$")
        XCTAssertEqual(segment.danger, .neutral)
    }

    func test_orphanPin_isOmitted() {
        let segment = MenuBarLabelModel.criticalSegment(
            pins: [.init(providerId: "gone", windowLabel: "x"),
                   .init(providerId: "claude", windowLabel: "5h")],
            snapshots: ["claude": snapshot("claude", [window("5h", usedPercent: 95)])],
            hasAnyError: false)
        XCTAssertEqual(segment, MenuBarSegment(glyph: "C", providerId: "claude", text: "5", danger: .critical))
    }

    /// A barra carrega UM número — e é o do PINO mais apertado, não o da janela mais
    /// apertada do mundo. Fixar é o jeito do dono dizer "acompanhe estas": se um provedor
    /// não-fixado pudesse sequestrar a barra, o pino não significaria nada.
    func test_pins_win_overTighterUnpinnedWindow() {
        let segment = MenuBarLabelModel.criticalSegment(
            pins: [.init(providerId: "claude", windowLabel: "5h")],
            snapshots: ["claude": snapshot("claude", [window("5h", usedPercent: 20)]),
                        "cursor": snapshot("cursor", [window("percent", usedPercent: 99)])],
            hasAnyError: false)
        XCTAssertEqual(segment.providerId, "claude")
        XCTAssertEqual(segment.text, "80")
    }

    /// Entre os pinos, a barra escolhe o mais apertado — os outros quatro números que
    /// ficavam ao lado dele foram para o painel do notch.
    func test_manyPins_onlyTheTightestReachesTheBar() {
        let segment = MenuBarLabelModel.criticalSegment(
            pins: [.init(providerId: "claude", windowLabel: "5h"),
                   .init(providerId: "codex", windowLabel: "semanal"),
                   .init(providerId: "cursor", windowLabel: "percent")],
            snapshots: ["claude": snapshot("claude", [window("5h", usedPercent: 22)]),
                        "codex": snapshot("codex", [window("semanal", usedPercent: 44)]),
                        "cursor": snapshot("cursor", [window("percent", usedPercent: 93)])],
            hasAnyError: false)
        XCTAssertEqual(segment, MenuBarSegment(glyph: "▹", providerId: "cursor", text: "7", danger: .critical))
    }

    /// Empate de sobra desempata pelo reset mais próximo: entre duas cotas igualmente
    /// apertadas, mostrar a que volta logo é menos útil do que mostrar a que ainda vai
    /// doer por horas — o critério aqui é a mais próxima, que é a que o dono consegue
    /// esperar acabar.
    func test_tieOnRemaining_breaksByNearestReset() {
        let segment = MenuBarLabelModel.criticalSegment(
            pins: [.init(providerId: "claude", windowLabel: "5h"),
                   .init(providerId: "codex", windowLabel: "semanal")],
            snapshots: ["claude": snapshot("claude", [window("5h", usedPercent: 60, resetIn: 9 * 3600)]),
                        "codex": snapshot("codex", [window("semanal", usedPercent: 60, resetIn: 2 * 3600)])],
            hasAnyError: false)
        XCTAssertEqual(segment.providerId, "codex")
    }

    /// Sem pino, a barra varre tudo. E o resultado NÃO pode depender da ordem em que o
    /// dicionário de snapshots entrega as chaves.
    func test_noPins_automatic_worstWindowAcrossProviders() {
        let snapshots = ["claude": snapshot("claude", [window("5h", usedPercent: 22)]),
                         "codex": snapshot("codex", [window("semanal", usedPercent: 80)])]
        XCTAssertEqual(MenuBarLabelModel.criticalSegment(pins: [], snapshots: snapshots, hasAnyError: false),
                       MenuBarSegment(glyph: "X", providerId: "codex", text: "20", danger: .warn))
    }

    /// Um saldo em dólares não tem "aperto" comparável a uma porcentagem, então ele só
    /// chega na barra quando é tudo o que existe.
    func test_balance_losesToAnyPercentageWindow() {
        let balance = QuotaWindow(label: "balance", shape: .creditBalance(remaining: Decimal(0.5), currency: "USD"))
        let segment = MenuBarLabelModel.criticalSegment(
            pins: [],
            snapshots: ["openrouter": snapshot("openrouter", [balance]),
                        "claude": snapshot("claude", [window("5h", usedPercent: 3)])],
            hasAnyError: false)
        XCTAssertEqual(segment.providerId, "claude")
        XCTAssertEqual(segment.text, "97")
    }

    func test_noPins_noData_errorShowsBang_elseOK() {
        XCTAssertEqual(MenuBarLabelModel.criticalSegment(pins: [], snapshots: [:], hasAnyError: true),
                       MenuBarSegment(glyph: nil, providerId: nil, text: "!", danger: .neutral))
        XCTAssertEqual(MenuBarLabelModel.criticalSegment(pins: [], snapshots: [:], hasAnyError: false),
                       MenuBarSegment(glyph: nil, providerId: nil, text: "OK", danger: .neutral))
    }

    func test_glyphs_areDistinctAcrossProviders() {
        let ids = ["claude", "codex", "supergrok", "cursor", "openrouter", "minimax", "opencode", "mimo"]
        let glyphs = ids.map { ProviderPalette.glyph(forId: $0) }
        XCTAssertEqual(Set(glyphs).count, ids.count, "menu bar glyphs must be distinct: \(glyphs)")
    }

    /// O símbolo da marca precisa SAIR do bundle em runtime — se o `Package.swift` ou o
    /// `Scripts/build_app.sh` deixarem os PNGs para trás, a barra perde a identidade e
    /// ninguém percebe até abrir o app.
    func test_menuBarSymbol_isInTheResourceBundle() throws {
        let symbol = try XCTUnwrap(BrandAssets.menuBarSymbol, "MenuBarTemplate.png não chegou ao Bundle.module")
        XCTAssertTrue(symbol.isTemplate)
        XCTAssertEqual(symbol.size, NSSize(width: 18, height: 18))
        // As três escalas: sem elas o traço de 18px sairia reamostrado num Retina 2×/3×.
        XCTAssertEqual(symbol.representations.count, 3)
    }
}
