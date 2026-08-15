import XCTest
@testable import OkTally

/// O rótulo da barra de menu é uma `NSImage` NÃO-template (é a única forma de os números
/// coloridos sobreviverem), então o macOS NÃO adapta a cor por nós: o que sai do
/// `ImageRenderer` é literalmente o que aparece na barra.
///
/// A versão anterior tentava resolver isso com um cinza médio fixo (0.58) para as duas
/// barras. Estes testes existem para que a próxima pessoa que pensar nisso veja o número:
/// contra a barra escura aquele cinza dá ~5:1 enquanto os ícones vizinhos do sistema dão
/// ~17:1 — daí o "praticamente oculto" do dono.
final class MenuBarInkTests: XCTestCase {
    /// A barra de menu real do macOS: quase preta no escuro, quase branca no claro.
    private let darkBar = 0.12
    private let lightBar = 0.95

    func test_ink_isHighContrastOnBothBars() {
        XCTAssertGreaterThan(
            MenuBarInk.contrastRatio(MenuBarInk.white(onDarkBar: true), darkBar), 12,
            "o símbolo tem que pertencer à fileira de ícones brancos do sistema, não sussurrar ao lado dela")
        XCTAssertGreaterThan(
            MenuBarInk.contrastRatio(MenuBarInk.white(onDarkBar: false), lightBar), 12)
    }

    /// A regressão concreta: o cinza fixo antigo teria contraste MUITO menor na barra
    /// escura do que a tinta atual.
    func test_oldFixedGray_wasFarWeakerThanTheCurrentInk() {
        let old = MenuBarInk.contrastRatio(0.58, darkBar)
        let now = MenuBarInk.contrastRatio(MenuBarInk.white(onDarkBar: true), darkBar)
        XCTAssertLessThan(old, 7)
        XCTAssertGreaterThan(now, old * 2)
    }

    /// Contraste é simétrico e a fórmula é a da WCAG: branco contra preto é 21:1.
    func test_contrastRatio_matchesWCAGReferencePoints() {
        XCTAssertEqual(MenuBarInk.contrastRatio(1, 0), 21, accuracy: 0.01)
        XCTAssertEqual(MenuBarInk.contrastRatio(0, 1), 21, accuracy: 0.01)
        XCTAssertEqual(MenuBarInk.contrastRatio(0.5, 0.5), 1, accuracy: 0.0001)
    }
}
