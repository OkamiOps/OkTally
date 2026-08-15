import XCTest
import UniformTypeIdentifiers
import CoreTransferable
@testable import OkTally

/// O gesto de arrastar é fiação do SwiftUI e não pode ser exercitado por teste. O que dá
/// para provar é o payload: que o `Transferable` expõe o tipo próprio (e não texto cru),
/// que o valor sobrevive ao `NSItemProvider` — o caminho que o arrasto realmente usa — e
/// que o identificador no código não divergiu do declarado no `Info.plist`.
///
/// Uma versão anterior destes testes afirmava `UTType(exportedAs: "…").identifier == "…"`
/// e fazia round-trip com `JSONEncoder` na mão: passava mesmo com o `contentType` trocado
/// e com o `Info.plist` esvaziado. Estes aqui falham nos dois casos.
final class MenuBarPinTransferTests: XCTestCase {
    private let expectedIdentifier = "com.oktally.app.menubarpin"

    func test_oTransferableExpoeOTipoProprioENaoTextoCru() {
        XCTAssertEqual(MenuBarPinTransfer.exportedContentTypes().map(\.identifier), [expectedIdentifier])
        XCTAssertEqual(MenuBarPinTransfer.importedContentTypes().map(\.identifier), [expectedIdentifier])
    }

    func test_oItemProviderRegistraSomenteOTipoProprio() {
        let provider = NSItemProvider()
        provider.register(MenuBarPinTransfer(stored: "claude\u{1}5h"))
        XCTAssertEqual(provider.registeredTypeIdentifiers, [expectedIdentifier])
    }

    func test_oIdentificadorDoPinoSobreviveAoItemProvider() {
        // O separador \u{1} do `MenuBarPin.stored` é o que mais provavelmente quebraria.
        let provider = NSItemProvider()
        provider.register(MenuBarPinTransfer(stored: "claude\u{1}5h"))

        let chegou = expectation(description: "loadTransferable")
        var recebido: MenuBarPinTransfer?
        _ = provider.loadTransferable(type: MenuBarPinTransfer.self) { result in
            recebido = try? result.get()
            chegou.fulfill()
        }
        wait(for: [chegou], timeout: 5)
        XCTAssertEqual(recebido?.stored, "claude\u{1}5h")
    }

    func test_oIdentificadorDoCodigoBateComODeclaradoNoInfoPlist() throws {
        // Sem isto, trocar o identificador no código e esquecer o plist passaria batido.
        let plist = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/Info.plist")
        let raw = try Data(contentsOf: plist)
        let parsed = try PropertyListSerialization.propertyList(from: raw, format: nil)
        let declarations = try XCTUnwrap(
            (parsed as? [String: Any])?["UTExportedTypeDeclarations"] as? [[String: Any]]
        )
        let identifiers = declarations.compactMap { $0["UTTypeIdentifier"] as? String }
        XCTAssertTrue(
            identifiers.contains(UTType.menuBarPin.identifier),
            "UTType.menuBarPin (\(UTType.menuBarPin.identifier)) não está em UTExportedTypeDeclarations: \(identifiers)"
        )
    }

    func test_oValorQueChegaDoDropAlimentaOReordenador() {
        let pins = ["claude\u{1}5h", "codex\u{1}weekly", "cursor\u{1}cycle"]
        XCTAssertEqual(
            PinReorder.reordered(pins, dragging: MenuBarPinTransfer(stored: pins[0]).stored, onto: pins[2]),
            ["codex\u{1}weekly", "cursor\u{1}cycle", "claude\u{1}5h"]
        )
    }
}
