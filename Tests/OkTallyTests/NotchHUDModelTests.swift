import XCTest
import AppKit
@testable import OkTally

final class NotchHUDModelTests: XCTestCase {
    private func snapshot(_ id: String, _ quotas: [QuotaWindow]) -> ProviderSnapshot {
        ProviderSnapshot(providerId: id, fetchedAt: Date(), quotas: quotas, usageDetail: nil)
    }
    private func window(_ label: String, usedPercent: Double) -> QuotaWindow {
        QuotaWindow(label: label, shape: .rollingWindow(
            used: usedPercent, limit: 100, windowStart: Date(), resetAt: Date().addingTimeInterval(3600)))
    }
    private let order = ["claude", "codex", "cursor", "openrouter"]

    /// Com pinos, o painel obedece à ordem em que foram fixados — a mesma que as
    /// Preferências deixam arrastar. Reordenar por aperto aqui faria os tracinhos
    /// trocarem de lugar sozinhos ao longo do dia, e o dono perderia a referência de
    /// posição que o arrasto acabou de construir.
    func test_pins_keepPinOrder() {
        let entries = NotchHUDModel.entries(
            pins: [.init(providerId: "codex", windowLabel: "semanal"),
                   .init(providerId: "claude", windowLabel: "5h")],
            snapshots: ["claude": snapshot("claude", [window("5h", usedPercent: 90)]),
                        "codex": snapshot("codex", [window("semanal", usedPercent: 10)])],
            providerOrder: order)
        XCTAssertEqual(entries.map(\.providerId), ["codex", "claude"])
        XCTAssertEqual(entries.map(\.danger), [.ok, .critical])
    }

    /// Sem pinos, o painel se auto-preenche: uma janela por provedor, das mais apertadas
    /// para as mais folgadas.
    func test_automatic_oneWindowPerProvider_tightestFirst() {
        let entries = NotchHUDModel.entries(
            pins: [],
            snapshots: ["claude": snapshot("claude", [window("5h", usedPercent: 20),
                                                      window("weekly", usedPercent: 95)]),
                        "codex": snapshot("codex", [window("semanal", usedPercent: 50)])],
            providerOrder: order)
        // O Claude entra pela janela SEMANAL (a mais apertada dele, 5% restante) e não
        // pela de 5h; e entra na frente do Codex por causa disso.
        XCTAssertEqual(entries.map(\.providerId), ["claude", "codex"])
        XCTAssertEqual(entries.first?.windowLabel, "weekly")
        // Um provedor não ocupa duas linhas: senão o Claude sozinho comeria dois dos
        // cinco lugares e esconderia um provedor inteiro.
        XCTAssertEqual(entries.filter { $0.providerId == "claude" }.count, 1)
    }

    /// Saldos não têm porcentagem para comparar; vão para o fim em vez de serem tratados
    /// como 0% (que os colocaria no topo como se fossem a emergência do dia).
    func test_automatic_balancesSinkToTheEnd() {
        let balance = QuotaWindow(label: "balance", shape: .creditBalance(remaining: Decimal(19.82), currency: "USD"))
        let entries = NotchHUDModel.entries(
            pins: [],
            snapshots: ["openrouter": snapshot("openrouter", [balance]),
                        "codex": snapshot("codex", [window("semanal", usedPercent: 50)])],
            providerOrder: order)
        XCTAssertEqual(entries.map(\.providerId), ["codex", "openrouter"])
        XCTAssertNil(entries.last?.remaining)
        XCTAssertEqual(entries.last?.danger, .neutral)
    }

    /// `snapshots` é um dicionário: sem a ordem do registry como desempate, dois
    /// provedores com a mesma sobra trocariam de lugar entre recomposições e os tracinhos
    /// dançariam sozinhos.
    func test_automatic_isStableAcrossDictionaryOrder() {
        let snapshots = ["claude": snapshot("claude", [window("5h", usedPercent: 40)]),
                         "codex": snapshot("codex", [window("semanal", usedPercent: 40)]),
                         "cursor": snapshot("cursor", [window("percent", usedPercent: 40)])]
        let first = NotchHUDModel.entries(pins: [], snapshots: snapshots, providerOrder: order)
        for _ in 0..<20 {
            XCTAssertEqual(NotchHUDModel.entries(pins: [], snapshots: snapshots, providerOrder: order), first)
        }
        XCTAssertEqual(first.map(\.providerId), ["claude", "codex", "cursor"])
    }

    /// Um provedor que o registry ainda não listou aparece no fim em vez de sumir em
    /// silêncio — dado na tela é melhor do que dado que evaporou.
    func test_providerOutsideRegistryOrder_stillAppears() {
        let entries = NotchHUDModel.entries(
            pins: [],
            snapshots: ["desconhecido": snapshot("desconhecido", [window("x", usedPercent: 10)])],
            providerOrder: order)
        XCTAssertEqual(entries.map(\.providerId), ["desconhecido"])
    }

    /// O teto existe para o painel fechado caber ao lado do notch e para o expandido não
    /// virar uma segunda janela.
    func test_entries_areCappedAtMaxEntries() {
        var snapshots: [String: ProviderSnapshot] = [:]
        for index in 0..<9 {
            let id = "p\(index)"
            snapshots[id] = snapshot(id, [window("w", usedPercent: Double(index) * 10)])
        }
        let entries = NotchHUDModel.entries(pins: [], snapshots: snapshots,
                                            providerOrder: snapshots.keys.sorted())
        XCTAssertEqual(entries.count, NotchHUDModel.maxEntries)
    }

    /// Fechado e expandido desenham a MESMA lista. Se divergissem, o tracinho que o olho
    /// estava seguindo viraria outra linha durante a animação de expansão.
    func test_orphanPins_areDroppedWithoutShiftingTheRest() {
        let entries = NotchHUDModel.entries(
            pins: [.init(providerId: "sumiu", windowLabel: "x"),
                   .init(providerId: "claude", windowLabel: "5h")],
            snapshots: ["claude": snapshot("claude", [window("5h", usedPercent: 30)])],
            providerOrder: order)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.id, "claude\u{1}5h")
    }

    /// A identidade não pode ser só o rótulo: "weekly" existe em vários provedores, e ids
    /// repetidos fariam o `ForEach` do painel desenhar uma linha só.
    func test_entryIds_areUniqueAcrossProvidersSharingALabel() {
        let entries = NotchHUDModel.entries(
            pins: [.init(providerId: "claude", windowLabel: "weekly"),
                   .init(providerId: "codex", windowLabel: "weekly")],
            snapshots: ["claude": snapshot("claude", [window("weekly", usedPercent: 10)]),
                        "codex": snapshot("codex", [window("weekly", usedPercent: 20)])],
            providerOrder: order)
        XCTAssertEqual(Set(entries.map(\.id)).count, 2)
    }

    /// Sem notch não há painel. A regra é a da tela EMBUTIDA: monitor externo e MacBook
    /// de tampa fechada caem fora, e a barra de menu segue sozinha.
    @MainActor
    func test_notchScreen_requiresSafeAreaAndAuxiliaryAreas() {
        let screen = NotchHUDController.notchScreen()
        if let screen {
            XCTAssertGreaterThan(screen.safeAreaInsets.top, 0)
            XCTAssertNotNil(screen.auxiliaryTopLeftArea)
            XCTAssertNotNil(screen.auxiliaryTopRightArea)
        } else {
            // Sem tela com notch (CI, monitor externo): o contrato é justamente devolver
            // nil, e o app não pode explodir por causa disso.
            XCTAssertTrue(NSScreen.screens.allSatisfy { $0.safeAreaInsets.top == 0 || $0.auxiliaryTopLeftArea == nil })
        }
    }
}
