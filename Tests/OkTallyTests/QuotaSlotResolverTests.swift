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
        XCTAssertEqual(segment, MenuBarSegment(glyph: "C", providerId: "claude", text: "78", danger: .ok, remaining: 0.78))
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

    // MARK: - Barra inferior do notch

    /// Em automático a barra é a MAIS APERTADA — inclusive quando isso a faz repetir a
    /// asa esquerda. Ela é o alarme do painel, e alarme é sempre sobre a pior cota.
    func test_bottomBar_automaticIsTheTightest() {
        let bar = QuotaSlotResolver.bottomBar(
            slot: .automatic, pins: [], snapshots: snapshots, providerOrder: order)
        XCTAssertEqual(bar?.providerId, "cursor")
        XCTAssertEqual(bar?.remaining ?? -1, 0.07, accuracy: 0.0001)
    }

    /// Escolha explícita manda, mesmo sendo a mais folgada de todas.
    func test_bottomBar_explicitWindowWins() {
        let bar = QuotaSlotResolver.bottomBar(
            slot: .window(providerId: "claude", windowLabel: "5h"),
            pins: [], snapshots: snapshots, providerOrder: order)
        XCTAssertEqual(bar?.providerId, "claude")
        XCTAssertEqual(bar?.remaining ?? -1, 0.78, accuracy: 0.0001)
    }

    /// Provedor escolhido que sumiu (deslogado, cota que o serviço parou de devolver)
    /// cai para automático em silêncio, igual às asas e ao número da barra de menu.
    func test_bottomBar_orphanChoiceFallsBackToAutomatic() {
        let bar = QuotaSlotResolver.bottomBar(
            slot: .window(providerId: "fantasma", windowLabel: "5h"),
            pins: [], snapshots: snapshots, providerOrder: order)
        XCTAssertEqual(bar?.providerId, "cursor")
    }

    /// Sem nenhuma janela com percentual a barra não existe — um saldo em dólares não
    /// tem teto conhecido, e preenchê-la com qualquer coisa seria inventar um número.
    func test_bottomBar_balanceOnlyDrawsNothing() {
        let onlyBalance = ["openrouter": snapshot("openrouter", [
            QuotaWindow(label: "saldo", shape: .creditBalance(remaining: 12, currency: "USD"))
        ])]
        XCTAssertNil(QuotaSlotResolver.bottomBar(
            slot: .automatic, pins: [], snapshots: onlyBalance, providerOrder: order))
        // E uma escolha explícita de saldo também não vira barra: o problema é a forma da
        // cota, não a origem da escolha.
        XCTAssertNil(QuotaSlotResolver.bottomBar(
            slot: .window(providerId: "openrouter", windowLabel: "saldo"),
            pins: [], snapshots: onlyBalance, providerOrder: order))
    }

    /// Sem dado nenhum, nada.
    func test_bottomBar_noDataDrawsNothing() {
        XCTAssertNil(QuotaSlotResolver.bottomBar(
            slot: .automatic, pins: [], snapshots: [:], providerOrder: order))
    }

    /// Com pinos, a barra escolhe entre os PINOS — igual às asas. Fixar continua sendo o
    /// jeito de dizer "acompanhe estas e ignore o resto".
    func test_bottomBar_automaticRespectsPins() {
        let bar = QuotaSlotResolver.bottomBar(
            slot: .automatic,
            pins: [.init(providerId: "claude", windowLabel: "5h"),
                   .init(providerId: "codex", windowLabel: "semanal")],
            snapshots: snapshots, providerOrder: order)
        // O cursor a 93% usado é o mais apertado do mundo, mas não está fixado.
        XCTAssertEqual(bar?.providerId, "codex")
    }

    // MARK: - Card-herói do popover

    /// Limites específicos do Spark continuam disponíveis, mas não substituem o Weekly
    /// geral como resumo automático do Codex.
    func test_popoverHero_automaticRepresentsCodexWithGeneralWeekly() {
        var withSpark = snapshots
        withSpark["codex"] = snapshot("codex", [
            window("semanal", usedPercent: 44),
            window("GPT-5.3-Codex-Spark (5h)", usedPercent: 97)
        ])
        let hero = QuotaSlotResolver.popoverHero(slot: .automatic, snapshots: withSpark, providerOrder: order)
        XCTAssertEqual(hero?.providerId, "cursor")
    }

    func test_popoverHero_explicitSparkStillWins() {
        var withSpark = snapshots
        withSpark["codex"] = snapshot("codex", [
            window("semanal", usedPercent: 44),
            window("GPT-5.3-Codex-Spark (5h)", usedPercent: 97)
        ])
        let hero = QuotaSlotResolver.popoverHero(
            slot: .window(providerId: "codex", windowLabel: "GPT-5.3-Codex-Spark (5h)"),
            snapshots: withSpark,
            providerOrder: order
        )
        XCTAssertEqual(hero?.providerId, "codex")
        XCTAssertEqual(hero?.window.label, "GPT-5.3-Codex-Spark (5h)")
    }

    /// Escolha explícita manda, mesmo sendo a mais folgada de todas.
    func test_popoverHero_explicitWindowWinsOverTheCritical() {
        let hero = QuotaSlotResolver.popoverHero(
            slot: .window(providerId: "claude", windowLabel: "5h"),
            snapshots: snapshots, providerOrder: order)
        XCTAssertEqual(hero?.providerId, "claude")
        XCTAssertEqual(hero?.window.label, "5h")
    }

    /// Provedor escolhido que sumiu (deslogado, ou o `withData` do popover que já o
    /// filtrou por erro `.notConfigured`) cai para automático em silêncio, igual às
    /// asas e à barra inferior.
    func test_popoverHero_orphanChoiceFallsBackToAutomatic() {
        let hero = QuotaSlotResolver.popoverHero(
            slot: .window(providerId: "sumiu", windowLabel: "5h"),
            snapshots: snapshots, providerOrder: order)
        XCTAssertEqual(hero?.providerId, "cursor")
    }

    /// Janela que sumiu de um provedor que continua logado é o mesmo caso.
    func test_popoverHero_orphanWindowOnLivingProviderFallsBackToAutomatic() {
        let hero = QuotaSlotResolver.popoverHero(
            slot: .window(providerId: "claude", windowLabel: "janela-que-nao-existe"),
            snapshots: snapshots, providerOrder: order)
        XCTAssertEqual(hero?.providerId, "cursor")
    }

    /// Sem dado nenhum, nenhum herói.
    func test_popoverHero_noDataIsNil() {
        XCTAssertNil(QuotaSlotResolver.popoverHero(slot: .automatic, snapshots: [:], providerOrder: order))
    }

    /// Fração igual desempata pelo reset mais próximo, e não pela ordem de um dicionário.
    func test_popoverHero_tieBreaksByNearestReset() {
        let hero = QuotaSlotResolver.popoverHero(
            slot: .automatic,
            snapshots: [
                "claude": snapshot("claude", [window("5h", usedPercent: 60, resetIn: 9 * 3600)]),
                "codex": snapshot("codex", [window("semanal", usedPercent: 60, resetIn: 2 * 3600)])
            ],
            providerOrder: order)
        XCTAssertEqual(hero?.providerId, "codex")
    }

    /// Um saldo em dólares não tem "aperto" comparável a uma porcentagem: ele nunca vira
    /// herói do automático, mesmo sendo a única janela disponível.
    func test_popoverHero_balanceOnlyNeverWinsAutomatic() {
        let onlyBalance = ["openrouter": snapshot("openrouter", [
            QuotaWindow(label: "saldo", shape: .creditBalance(remaining: 12, currency: "USD"))
        ])]
        XCTAssertNil(QuotaSlotResolver.popoverHero(slot: .automatic, snapshots: onlyBalance, providerOrder: order))
    }

    /// Mas uma escolha EXPLÍCITA de saldo é honrada — o card-herói mostra o que o dono
    /// escolheu, mesmo sem barra para desenhar (isso é responsabilidade da view, não do
    /// resolvedor).
    func test_popoverHero_explicitBalanceIsHonored() {
        let onlyBalance = ["openrouter": snapshot("openrouter", [
            QuotaWindow(label: "saldo", shape: .creditBalance(remaining: 12, currency: "USD"))
        ])]
        let hero = QuotaSlotResolver.popoverHero(
            slot: .window(providerId: "openrouter", windowLabel: "saldo"),
            snapshots: onlyBalance, providerOrder: order)
        XCTAssertEqual(hero?.providerId, "openrouter")
        XCTAssertEqual(hero?.window.label, "saldo")
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
