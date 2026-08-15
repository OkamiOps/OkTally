import XCTest
import AppKit
@testable import OkTally

/// O símbolo da marca vem de UM arquivo, e este teste é a garantia de que ele está lá.
///
/// Existe porque o `BrandMark` deixou de ter plano B: a versão anterior redesenhava a
/// marca em SwiftUI quando o PNG não aparecia, e foi exatamente esse desenho — três
/// traços com uma diagonal inventada — que o dono viu no notch e chamou de logo
/// "alterado". Sem substituto, o que protege a identidade é o empacotamento; sem teste, o
/// empacotamento quebraria em silêncio e a marca sumiria da barra e do notch de uma vez.
final class BrandAssetsTests: XCTestCase {

    func test_symbolIsInTheBundle() throws {
        let symbol = try XCTUnwrap(BrandAssets.symbol, "MenuBarTemplate.png não está no bundle")
        XCTAssertTrue(symbol.isTemplate, "o símbolo precisa ser template para aceitar tintura")
        // As três escalas: sem elas o `ImageRenderer` reamostraria o PNG de 18px num
        // Retina de 2× ou 3× e o traço sairia borrado.
        XCTAssertEqual(symbol.representations.count, 3)
    }

    /// `BrandMark(size:)` promete "a marca sai com esta altura". A promessa depende de
    /// medir a margem do canvas do PNG — se a medição falhar ela devolve 1, e aí o
    /// símbolo volta a sair ~25% menor do que o texto ao lado.
    func test_symbolHeightRatio_measuresTheGlyphAndNotTheCanvas() {
        let ratio = BrandAssets.symbolHeightRatio
        XCTAssertGreaterThan(ratio, 0.5, "medição absurda — o glifo não é tão pequeno assim")
        XCTAssertLessThan(ratio, 1.0, "o canvas do símbolo tem margem; 1 significa medição falhada")
    }

    /// O desenho não é quadrado: forçá-lo num quadro quadrado sem `aspectRatio(.fit)` é
    /// uma das formas de "alterar" a marca. O teste ancora a proporção do arquivo para
    /// que uma regeração distorcida não passe despercebida.
    func test_symbolProportionMatchesTheBrand() throws {
        let symbol = try XCTUnwrap(BrandAssets.symbol)
        let rep = try XCTUnwrap(symbol.representations.max(by: { $0.pixelsHigh < $1.pixelsHigh }))
        XCTAssertEqual(Double(rep.pixelsWide) / Double(rep.pixelsHigh), 1.0, accuracy: 0.01,
                       "o canvas do asset é quadrado; o glifo dentro dele é que não é")
    }
}
