// Tests/OkTallyTests/NotchBottomRuleTests.swift
import XCTest
@testable import OkTally

/// A conta que decide se a barra contínua do notch fechado é VISÍVEL — a parte que nenhum
/// PNG (nem `screencapture`!) revela: o framebuffer tem os pixels atrás do recorte, o
/// painel de LED não. O dono provou com uma foto do hardware que a primeira prateleira,
/// calculada sobre o `safeAreaInsets.top` DECLARADO, ainda deixava a barra dentro do furo:
/// em resolução escalada o furo físico ocupa mais pontos do que o macOS admite.
///
/// Estes testes guardam as duas contas de `NotchPhysicalCutout`: quanto o furo mede de
/// verdade no modo atual, e quanto o painel precisa descer para a barra inteira ficar
/// abaixo dele.
final class NotchBottomRuleTests: XCTestCase {
    /// Anatomia da barra a partir das constantes reais — se alguém mudar espessura ou
    /// respiro, as contas abaixo acompanham em vez de mentir.
    private var barBand: CGFloat { NotchBottomRule.bottomGap + NotchBottomRule.thickness }

    // MARK: - Altura física do furo

    /// Modo padrão (lógica = nativa ÷ 2): o declarado é verdade e a conta devolve ele.
    func testDefaultModeMatchesDeclaredSafeArea() {
        let physical = NotchPhysicalCutout.height(
            logicalScreenHeight: 982, nativePanelRows: 1964, safeTop: 38
        )
        XCTAssertEqual(physical, 38, accuracy: 0.01)
    }

    /// A tela do dono no dia da foto: 2048×1330 escalado num painel de 1964 linhas,
    /// `safeAreaInsets.top` declarando 43. O furo real: 38 × 1330 ÷ 982 ≈ 51,5pt —
    /// 8,5pt mais fundo que o declarado. Foi exatamente nessa faixa que a barra da
    /// primeira prateleira morreu.
    func testScaledModeCutoutIsDeeperThanDeclared() {
        let physical = NotchPhysicalCutout.height(
            logicalScreenHeight: 1330, nativePanelRows: 1964, safeTop: 43
        )
        XCTAssertEqual(physical, 51.46, accuracy: 0.05)
        XCTAssertGreaterThan(physical, 43 + 8, "o furo escalado invade >8pt além do declarado")
    }

    /// Sem modo nativo na lista (painel desconhecido) a resposta honesta é o declarado —
    /// nunca um chute que poderia ser MENOR que ele.
    func testUnknownPanelFallsBackToDeclared() {
        XCTAssertEqual(
            NotchPhysicalCutout.height(logicalScreenHeight: 1330, nativePanelRows: nil, safeTop: 43),
            43
        )
    }

    /// O furo nunca é raso demais: se o modelo der menos que o declarado (painel exótico),
    /// o declarado é o piso.
    func testDeclaredIsTheFloor() {
        let physical = NotchPhysicalCutout.height(
            logicalScreenHeight: 500, nativePanelRows: 1964, safeTop: 43
        )
        XCTAssertEqual(physical, 43)
    }

    // MARK: - Prateleira

    /// O invariante que a foto do dono cobrou: TODO o traço (respiro da borda +
    /// espessura + folga do modelo) abaixo do furo físico. A borda de cima da barra fica
    /// em `safeTop + shelf − barBand`; ela precisa passar do furo com a folga inteira.
    func testBarClearsThePhysicalCutoutOnTheOwnersScreen() {
        let safeTop: CGFloat = 43
        let physical = NotchPhysicalCutout.height(
            logicalScreenHeight: 1330, nativePanelRows: 1964, safeTop: safeTop
        )
        let shelf = NotchPhysicalCutout.shelf(physicalHeight: physical, safeTop: safeTop)
        let barTop = safeTop + shelf - barBand
        XCTAssertGreaterThanOrEqual(
            barTop, physical + NotchPhysicalCutout.clearance - 1,
            "barra em y=\(barTop) sem folga sobre o furo de \(physical)pt"
        )
    }

    /// No modo padrão a prateleira volta ao tamanho discreto (~10pt): overlap zero,
    /// sobra só a anatomia da barra e a folga.
    func testDefaultModeShelfStaysShallow() {
        let shelf = NotchPhysicalCutout.shelf(physicalHeight: 38, safeTop: 38)
        XCTAssertEqual(shelf, (barBand + NotchPhysicalCutout.clearance).rounded(.up))
        XCTAssertLessThanOrEqual(shelf, 10)
    }
}
