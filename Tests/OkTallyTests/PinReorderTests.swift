import XCTest
@testable import OkTally

final class PinReorderTests: XCTestCase {
    private let order = ["A", "B", "C", "D"]

    func test_arrastarParaCima_insereNaPosicaoDoAlvo() {
        XCTAssertEqual(PinReorder.reordered(order, dragging: "D", onto: "B"), ["A", "D", "B", "C"])
    }

    /// Regressão: com o índice do alvo calculado depois da remoção, isto dava
    /// ["B","A","C","D"] — o item parava um slot antes do alvo.
    func test_arrastarParaBaixo_naoParaUmSlotAntes() {
        XCTAssertEqual(PinReorder.reordered(order, dragging: "A", onto: "C"), ["B", "C", "A", "D"])
    }

    /// Regressão: a última posição era inalcançável — repetir o arrasto não mudava mais nada.
    func test_arrastarParaAUltimaLinha_chegaAoFim() {
        XCTAssertEqual(PinReorder.reordered(order, dragging: "A", onto: "D"), ["B", "C", "D", "A"])
    }

    func test_soltarSobreSiMesmo_naoMuda() {
        XCTAssertNil(PinReorder.reordered(order, dragging: "B", onto: "B"))
    }

    func test_identificadorDesconhecido_naoMuda() {
        XCTAssertNil(PinReorder.reordered(order, dragging: "Z", onto: "B"))
        XCTAssertNil(PinReorder.reordered(order, dragging: "A", onto: "Z"))
    }
}
