// Sources/OkTally/Core/MenuBarPinTransfer.swift
import Foundation
import UniformTypeIdentifiers
import CoreTransferable

/// Tipo de arrasto exclusivo dos pinos da barra de menu.
///
/// Antes as linhas usavam `String` cru como `Transferable`. Isso tinha dois efeitos ruins,
/// nenhum deles fatal mas os dois errados: qualquer texto arrastado de outro app marcava a
/// linha como alvo válido de soltura (o realce mentia, mesmo com a soltura sendo recusada
/// depois), e arrastar um pino para fora exportava o id interno (`"claude\u{1}5h"`) como
/// texto para qualquer editor. Um tipo próprio faz o hit-testing dizer a verdade e mantém
/// o identificador dentro do app.
///
/// O identificador precisa estar declarado em `UTExportedTypeDeclarations` no
/// `Resources/Info.plist` — sem isso o sistema não reconhece o tipo.
extension UTType {
    static let menuBarPin = UTType(exportedAs: "com.oktally.app.menubarpin")
}

/// O `stored` de um `MenuBarPin` (o mesmo identificador que `PinReorder` consome).
struct MenuBarPinTransfer: Codable, Transferable, Equatable {
    let stored: String

    init(stored: String) {
        self.stored = stored
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .menuBarPin)
    }
}
