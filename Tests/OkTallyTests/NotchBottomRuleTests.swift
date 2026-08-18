// Tests/OkTallyTests/NotchBottomRuleTests.swift
import XCTest
@testable import OkTally

/// A conta que decide se a barra contínua do notch fechado é VISÍVEL — a parte que nenhum
/// PNG do harness revela, porque o recorte físico não existe na imagem: no framebuffer a
/// barra sempre foi contínua, e mesmo assim o dono via dois tocos, um sob cada asa.
///
/// A regra: o painel compacto desce `compactShelf` pontos abaixo do recorte (patch
/// `compactBottomShelf` no pacote vendorado), e a barra mora nessa prateleira. Estes
/// testes guardam a aritmética que mantém o traço INTEIRO fora da sombra do hardware —
/// quem mexer nas constantes sem refazer a conta quebra aqui, não no olho do dono.
final class NotchBottomRuleTests: XCTestCase {
    /// A borda de baixo da barra fica a `bottomGap` da borda do painel; a de cima, a
    /// `bottomGap + thickness`. TUDO isso precisa caber dentro da prateleira — se a
    /// prateleira for mais rasa, o topo do traço volta para trás do recorte e o miolo
    /// da barra some de novo.
    func testBarLivesEntirelyBelowThePhysicalNotch() {
        let barTopAbovePanelBottom = NotchBottomRule.bottomGap + NotchBottomRule.thickness
        XCTAssertGreaterThanOrEqual(
            NotchBottomRule.compactShelf, barTopAbovePanelBottom,
            "A prateleira (\(NotchBottomRule.compactShelf)pt) é mais rasa que gap+traço "
                + "(\(barTopAbovePanelBottom)pt): o topo da barra fica atrás do recorte físico."
        )
    }

    /// O mesmo invariante, contado a partir do topo da tela, com o notch real do dono
    /// (43pt na tela 2048×1330): o traço inteiro tem de começar ABAIXO dos 43pt.
    func testBarClearsARealNotchHeight() {
        let notchHeight: CGFloat = 43
        let panelHeight = notchHeight + NotchBottomRule.compactShelf
        let barTop = panelHeight - NotchBottomRule.bottomGap - NotchBottomRule.thickness
        XCTAssertGreaterThanOrEqual(
            barTop, notchHeight,
            "Barra começa em y=\(barTop), dentro da faixa do recorte (0…\(notchHeight))."
        )
    }
}
