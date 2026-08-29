// Sources/OkTally/Core/ProviderOrderTransfer.swift
import Foundation
import UniformTypeIdentifiers
import CoreTransferable

/// Tipo de arrasto exclusivo das contas na sidebar de Preferências.
///
/// Mesma razão dos pinos da barra: `String` cru marcaria qualquer texto de outro app
/// como alvo válido de soltura, e arrastar uma conta para fora exportaria o id interno
/// (`"claude"`) como texto. Um tipo próprio faz o hit-testing dizer a verdade e mantém
/// o identificador dentro do app.
///
/// O identificador precisa estar declarado em `UTExportedTypeDeclarations` no
/// `Resources/Info.plist` — sem isso o sistema não reconhece o tipo.
extension UTType {
    static let providerOrder = UTType(exportedAs: "com.oktally.app.providerorder")
}

/// O `id` de um provider (o mesmo identificador que `PinReorder` e
/// `AppModel.moveProvider` consomem).
struct ProviderOrderTransfer: Codable, Transferable, Equatable {
    let id: String

    init(id: String) {
        self.id = id
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .providerOrder)
    }
}
