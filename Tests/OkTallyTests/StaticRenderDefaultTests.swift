import XCTest
import SwiftUI
@testable import OkTally

/// `isStaticRender` decide, em silêncio, se o app usa Liquid Glass ou cai no material —
/// e se usa o `Picker` nativo ou um substituto estático. O padrão precisa ser `false`:
/// invertê-lo entregaria o app inteiro com o caminho de renderização de PNG, sem nenhum
/// teste ou imagem para acusar (sob `ImageRenderer` o vidro nunca aparece de qualquer
/// jeito, então os assets não conseguem flagrar essa regressão).
final class StaticRenderDefaultTests: XCTestCase {
    func test_oAppNaoRodaNoCaminhoDeRenderEstatico() {
        XCTAssertFalse(EnvironmentValues().isStaticRender)
    }
}
