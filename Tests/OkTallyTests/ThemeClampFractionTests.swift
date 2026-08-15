import XCTest
@testable import OkTally

/// A guarda de NaN das barras e anéis. O bug que ela existe para impedir é silencioso: em
/// Swift, `min(1, .nan)` devolve `1`, então `max(0, min(1, .nan))` é `1.0` — uma fração
/// inválida desenhava a `ShareBar`/`ProgressRing`/`QuotaCapsuleBar` CHEIAS, ou seja
/// exatamente a leitura oposta ("tudo disponível" quando não se sabe nada).
final class ThemeClampFractionTests: XCTestCase {

    func test_naoConfiavelViraZeroEmVezDeCheio() {
        // A armadilha, provada aqui para que ninguém "simplifique" a guarda de volta.
        XCTAssertEqual(max(0, min(1, Double.nan)), 1.0)

        XCTAssertEqual(Theme.clampFraction(.nan), 0)
        XCTAssertEqual(Theme.clampFraction(.infinity), 0)
        XCTAssertEqual(Theme.clampFraction(-.infinity), 0)
        XCTAssertEqual(Theme.clampFraction(0.0 / 0.0), 0)
    }

    func test_grampeiaNosExtremos() {
        XCTAssertEqual(Theme.clampFraction(-0.5), 0)
        XCTAssertEqual(Theme.clampFraction(1.5), 1)
    }

    func test_preservaOIntervaloValido() {
        XCTAssertEqual(Theme.clampFraction(0), 0)
        XCTAssertEqual(Theme.clampFraction(0.42), 0.42, accuracy: 1e-12)
        XCTAssertEqual(Theme.clampFraction(1), 1)
    }
}
