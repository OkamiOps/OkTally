import XCTest
import UniformTypeIdentifiers
@testable import OkTally

/// O arrasto dos pinos não pode ser exercitado por teste (é fiação do SwiftUI), então o
/// que dá para garantir é o contrato do payload: o identificador do tipo e o round-trip
/// do valor. Se o `stored` não sobreviver à codificação, o drop não acha o pino e o
/// arrasto vira um gesto que não faz nada.
final class MenuBarPinTransferTests: XCTestCase {
    func test_usaUmTipoProprioENaoTextoCru() {
        // Texto cru fazia qualquer string de outro app marcar a linha como alvo válido.
        XCTAssertEqual(UTType.menuBarPin.identifier, "com.oktally.app.menubarpin")
        XCTAssertFalse(UTType.menuBarPin.conforms(to: .plainText))
    }

    func test_roundTripPreservaOIdentificadorDoPino() throws {
        // O separador \u{1} do `MenuBarPin.stored` é o caso que mais provavelmente
        // quebraria numa codificação descuidada.
        let original = MenuBarPinTransfer(stored: "claude\u{1}5h")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MenuBarPinTransfer.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.stored, "claude\u{1}5h")
    }

    func test_oIdentificadorSobrevivendoAlimentaOPinReorder() throws {
        // Prova a ponta que importa: o valor que chega do drop é aceito pelo reordenador.
        let pins = ["claude\u{1}5h", "codex\u{1}weekly", "cursor\u{1}cycle"]
        let dropped = try JSONDecoder().decode(
            MenuBarPinTransfer.self,
            from: try JSONEncoder().encode(MenuBarPinTransfer(stored: pins[0]))
        )
        XCTAssertEqual(
            PinReorder.reordered(pins, dragging: dropped.stored, onto: pins[2]),
            ["codex\u{1}weekly", "cursor\u{1}cycle", "claude\u{1}5h"]
        )
    }
}
