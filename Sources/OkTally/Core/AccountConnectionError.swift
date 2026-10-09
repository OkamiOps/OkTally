import Foundation

enum AccountConnectionError: LocalizedError {
    case differentAccount
    case duplicateKey

    var errorDescription: String? {
        switch self {
        case .differentAccount:
            return L("Você entrou em outra conta. Use Adicionar conta para manter as contas e seus históricos separados.")
        case .duplicateKey:
            return L("Esta chave já pertence a outra conta no OkTally. A conexão atual foi preservada.")
        }
    }
}
