import XCTest
import UniformTypeIdentifiers
import CoreTransferable
@testable import OkTally

/// O gesto de arrastar é fiação do SwiftUI e não pode ser exercitado por teste. O que dá
/// para provar é o payload: que o `Transferable` expõe o tipo próprio (e não texto cru),
/// que o valor sobrevive ao `NSItemProvider` — o caminho que o arrasto realmente usa — e
/// que o identificador no código não divergiu do declarado no `Info.plist`.
final class ProviderOrderTransferTests: XCTestCase {
    private let expectedIdentifier = "com.oktally.app.providerorder"

    func test_oTransferableExpoeOTipoProprioENaoTextoCru() {
        XCTAssertEqual(ProviderOrderTransfer.exportedContentTypes().map(\.identifier), [expectedIdentifier])
        XCTAssertEqual(ProviderOrderTransfer.importedContentTypes().map(\.identifier), [expectedIdentifier])
    }

    func test_oItemProviderRegistraSomenteOTipoProprio() {
        let provider = NSItemProvider()
        provider.register(ProviderOrderTransfer(id: "claude"))
        XCTAssertEqual(provider.registeredTypeIdentifiers, [expectedIdentifier])
    }

    func test_oIdentificadorDaContaSobreviveAoItemProvider() {
        let provider = NSItemProvider()
        provider.register(ProviderOrderTransfer(id: "cursor-grokbot"))

        let chegou = expectation(description: "loadTransferable")
        var recebido: ProviderOrderTransfer?
        _ = provider.loadTransferable(type: ProviderOrderTransfer.self) { result in
            recebido = try? result.get()
            chegou.fulfill()
        }
        wait(for: [chegou], timeout: 5)
        XCTAssertEqual(recebido?.id, "cursor-grokbot")
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
            identifiers.contains(UTType.providerOrder.identifier),
            "UTType.providerOrder (\(UTType.providerOrder.identifier)) não está em UTExportedTypeDeclarations: \(identifiers)"
        )
        XCTAssertTrue(
            identifiers.contains("com.oktally.app.menubarpin"),
            "a declaração de menubarpin não pode sumir ao acrescentar providerorder"
        )
    }

    func test_oValorQueChegaDoDropAlimentaOReordenador() {
        let ids = ["claude", "codex", "mimo"]
        XCTAssertEqual(
            PinReorder.reordered(ids, dragging: ProviderOrderTransfer(id: ids[0]).id, onto: ids[2]),
            ["codex", "mimo", "claude"]
        )
    }
}
