import XCTest
@testable import OkTally

/// As regras de "qual cota vai em qual lugar". Elas decidem o que o dono vê o dia
/// inteiro no notch e na barra, e nenhuma delas precisa de tela para ser verificada.
final class QuotaSlotResolverTests: XCTestCase {
    private func snapshot(_ id: String, _ quotas: [QuotaWindow]) -> ProviderSnapshot {
        ProviderSnapshot(providerId: id, fetchedAt: Date(), quotas: quotas, usageDetail: nil)
    }
    private func window(_ label: String, usedPercent: Double, resetIn: TimeInterval = 3600) -> QuotaWindow {
        QuotaWindow(label: label, shape: .rollingWindow(
            used: usedPercent, limit: 100, windowStart: Date(), resetAt: Date().addingTimeInterval(resetIn)))
    }
    private let order = ["claude", "codex", "cursor", "openrouter"]
    private var snapshots: [String: ProviderSnapshot] {
        ["claude": snapshot("claude", [window("5h", usedPercent: 22)]),
         "codex": snapshot("codex", [window("semanal", usedPercent: 44)]),
         "cursor": snapshot("cursor", [window("percent", usedPercent: 93)])]
    }

    // MARK: - Persistência

    /// A ida e volta pela string é o contrato com o `PreferencesStore`. Vazio é
    /// automático, e lixo também — nunca um quarto estado.
    func test_storedRoundTrip() {
        XCTAssertEqual(QuotaSlot(stored: QuotaSlot.automatic.stored), .automatic)
        let explicit = QuotaSlot.window(providerId: "claude", windowLabel: "5h")
        XCTAssertEqual(QuotaSlot(stored: explicit.stored), explicit)
        XCTAssertEqual(QuotaSlot(stored: nil), .automatic)
        XCTAssertEqual(QuotaSlot(stored: ""), .automatic)
        XCTAssertEqual(QuotaSlot(stored: "sem-separador"), .automatic)
    }

    /// Rótulo com o separador dentro não pode partir o par ao meio: `maxSplits: 1`
    /// garante que só o PRIMEIRO separador conta.
    func test_stored_labelKeepsEverythingAfterTheFirstSeparator() {
        XCTAssertEqual(QuotaSlot(stored: "claude\u{1}a\u{1}b"),
                       .window(providerId: "claude", windowLabel: "a\u{1}b"))
    }

    // MARK: - Asas

    /// Em automático as duas asas nunca mostram a mesma cota: gastar os dois lugares para
    /// dizer uma coisa só é o pior resultado possível de um painel com dois lugares.
    func test_bothWingsAutomatic_showTightestThenNext() {
        let wings = QuotaSlotResolver.wings(
            leading: .automatic, trailing: .automatic,
            pins: [], snapshots: snapshots, providerOrder: order)
        XCTAssertEqual(wings.leading?.providerId, "cursor")
        XCTAssertEqual(wings.trailing?.providerId, "codex")
    }

    /// Escolha explícita manda — inclusive quando ela é mais folgada que tudo o mais.
    func test_explicitWindow_winsOverTightest() {
        let wings = QuotaSlotResolver.wings(
            leading: .window(providerId: "claude", windowLabel: "5h"), trailing: .automatic,
            pins: [], snapshots: snapshots, providerOrder: order)
        XCTAssertEqual(wings.leading?.providerId, "claude")
        XCTAssertEqual(wings.leading?.window.label, "5h")
        // E a asa automática do outro lado desvia da escolhida.
        XCTAssertEqual(wings.trailing?.providerId, "cursor")
    }

    /// Se o dono pediu a MESMA cota dos dois lados, é isso que ele vê. A regra de não
    /// repetir existe para o automático não desperdiçar um lugar, não para vetar uma
    /// escolha deliberada.
    func test_sameWindowOnBothSides_isHonoredWhenExplicit() {
        let same = QuotaSlot.window(providerId: "claude", windowLabel: "5h")
        let wings = QuotaSlotResolver.wings(
            leading: same, trailing: same,
            pins: [], snapshots: snapshots, providerOrder: order)
        XCTAssertEqual(wings.leading?.providerId, "claude")
        XCTAssertEqual(wings.trailing?.providerId, "claude")
    }

    /// Provedor deslogado: o slot cai para automático em silêncio, sem asa vazia.
    func test_orphanChoice_fallsBackToAutomatic() {
        let wings = QuotaSlotResolver.wings(
            leading: .window(providerId: "sumiu", windowLabel: "5h"), trailing: .automatic,
            pins: [], snapshots: snapshots, providerOrder: order)
        XCTAssertEqual(wings.leading?.providerId, "cursor")
        XCTAssertEqual(wings.trailing?.providerId, "codex")
    }

    /// Janela que sumiu de um provedor que continua logado é o mesmo caso.
    func test_orphanWindowOnLivingProvider_fallsBackToAutomatic() {
        let wings = QuotaSlotResolver.wings(
            leading: .window(providerId: "claude", windowLabel: "janela-que-nao-existe"), trailing: .automatic,
            pins: [], snapshots: snapshots, providerOrder: order)
        XCTAssertEqual(wings.leading?.providerId, "cursor")
    }

    /// Um provedor só: a esquerda mostra e a direita fica vazia em vez de repetir.
    func test_singleCandidate_leavesTrailingEmpty() {
        let wings = QuotaSlotResolver.wings(
            leading: .automatic, trailing: .automatic,
            pins: [], snapshots: ["claude": snapshot("claude", [window("5h", usedPercent: 22)])],
            providerOrder: order)
        XCTAssertEqual(wings.leading?.providerId, "claude")
        XCTAssertNil(wings.trailing)
    }

    func test_noData_bothWingsEmpty() {
        let wings = QuotaSlotResolver.wings(
            leading: .automatic, trailing: .automatic,
            pins: [], snapshots: [:], providerOrder: order)
        XCTAssertNil(wings.leading)
        XCTAssertNil(wings.trailing)
    }

    /// Com pinos, o automático escolhe DENTRE os pinos: fixar continua significando
    /// "acompanhe estas", e uma cota não fixada não sequestra a asa.
    func test_automatic_ranksWithinPinsWhenPinsExist() {
        let wings = QuotaSlotResolver.wings(
            leading: .automatic, trailing: .automatic,
            pins: [.init(providerId: "claude", windowLabel: "5h"),
                   .init(providerId: "codex", windowLabel: "semanal")],
            snapshots: snapshots, providerOrder: order)
        XCTAssertEqual(wings.leading?.providerId, "codex")
        XCTAssertEqual(wings.trailing?.providerId, "claude")
    }

    /// Saldo em dólares não tem "aperto" comparável a uma porcentagem: ele vai para o fim
    /// da fila em vez de ser lido como 0% e ocupar a asa esquerda como emergência do dia.
    func test_ranked_balancesSinkToTheEnd() {
        let balance = QuotaWindow(label: "balance", shape: .creditBalance(remaining: Decimal(19.82), currency: "USD"))
        let ranked = QuotaSlotResolver.ranked(
            pins: [], snapshots: ["openrouter": snapshot("openrouter", [balance]),
                                          "claude": snapshot("claude", [window("5h", usedPercent: 22)])],
            providerOrder: order)
        XCTAssertEqual(ranked.map(\.providerId), ["claude", "openrouter"])
    }

    /// A ordem das candidatas não pode depender da ordem em que o dicionário entrega as
    /// chaves: duas cotas empatadas trocariam de asa a cada recomposição.
    func test_ranked_tieBreaksByNearestReset() {
        let ranked = QuotaSlotResolver.ranked(
            pins: [], snapshots: [
                "claude": snapshot("claude", [window("5h", usedPercent: 60, resetIn: 9 * 3600)]),
                "codex": snapshot("codex", [window("semanal", usedPercent: 60, resetIn: 2 * 3600)])],
            providerOrder: order)
        XCTAssertEqual(ranked.map(\.providerId), ["codex", "claude"])
    }

    // MARK: - Barra de menu

    func test_menuBarSlot_explicitWindowBeatsTheCritical() {
        let segment = MenuBarLabelModel.segment(
            slot: .window(providerId: "claude", windowLabel: "5h"),
            pins: [], snapshots: snapshots, hasAnyError: false)
        XCTAssertEqual(segment, MenuBarSegment(glyph: "C", providerId: "claude", text: "78", danger: .ok))
    }

    func test_menuBarSlot_automaticKeepsTheCriticalRule() {
        let segment = MenuBarLabelModel.segment(
            slot: .automatic, pins: [], snapshots: snapshots, hasAnyError: false)
        XCTAssertEqual(segment.providerId, "cursor")
        XCTAssertEqual(segment.text, "7")
    }

    func test_menuBarSlot_orphanChoiceFallsBackToTheCritical() {
        let segment = MenuBarLabelModel.segment(
            slot: .window(providerId: "sumiu", windowLabel: "5h"),
            pins: [], snapshots: snapshots, hasAnyError: false)
        XCTAssertEqual(segment.providerId, "cursor")
    }

    /// Sem dado nenhum a barra continua dizendo o que sempre disse — a escolha explícita
    /// não pode transformar "OK" num rótulo em branco.
    func test_menuBarSlot_noDataKeepsTheStatusText() {
        XCTAssertEqual(MenuBarLabelModel.segment(slot: .window(providerId: "x", windowLabel: "y"),
                                                 pins: [], snapshots: [:], hasAnyError: true).text, "!")
        XCTAssertEqual(MenuBarLabelModel.segment(slot: .automatic,
                                                 pins: [], snapshots: [:], hasAnyError: false).text, "OK")
    }

    // MARK: - Lista das Preferências

    /// A lista do `Picker` segue a ordem do registry, não a de aperto: uma lista que se
    /// reordena sozinha entre duas aberturas do menu é impossível de usar.
    func test_availableWindows_followRegistryOrder() {
        let slots = QuotaSlotResolver.availableWindows(snapshots: snapshots, providerOrder: order)
        XCTAssertEqual(slots, [
            .window(providerId: "claude", windowLabel: "5h"),
            .window(providerId: "codex", windowLabel: "semanal"),
            .window(providerId: "cursor", windowLabel: "percent")
        ])
    }

    /// Provedor que o registry não conhece ainda assim aparece — no fim e por id, em vez
    /// de sumir da lista em silêncio.
    func test_availableWindows_unknownProviderGoesLast() {
        var all = snapshots
        all["zzz"] = snapshot("zzz", [window("mensal", usedPercent: 1)])
        let slots = QuotaSlotResolver.availableWindows(snapshots: all, providerOrder: order)
        XCTAssertEqual(slots.last, .window(providerId: "zzz", windowLabel: "mensal"))
    }
}
