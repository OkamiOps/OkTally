// Sources/OkTally/Core/AccountRemoval.swift
import Foundation

enum AccountError: LocalizedError, Equatable {
    /// Conta que lê um app de terceiros (Cursor, Antigravity, Copilot, MiMo) ou o
    /// GrokBot, que segue o Cursor dele.
    case cannotRemove(String)
    case unknownAccount(String)

    var errorDescription: String? {
        switch self {
        case .cannotRemove:
            return L("Esta conta vem de um app instalado neste Mac e não pode ser removida.")
        case .unknownAccount:
            return L("Conta não encontrada.")
        }
    }
}

/// Limpeza pura do que aponta para uma conta removida. Separada do `AppModel` para ser
/// testável sem SwiftUI nem scheduler.
enum AccountRemoval {
    struct Result: Equatable {
        let pins: [AppModel.MenuBarPin]
        let slots: [QuotaSlot]
        let order: [String]
    }

    /// Pinos da conta somem, slots que a escolhiam voltam a automático e ela sai da
    /// ordem salva. Nada de outras contas é tocado.
    static func cleanup(removedIds: Set<String>, pins: [AppModel.MenuBarPin], slots: [QuotaSlot], order: [String]) -> Result {
        Result(
            pins: pins.filter { !removedIds.contains($0.providerId) },
            slots: slots.map { slot in
                if case .window(let providerId, _) = slot, removedIds.contains(providerId) { return .automatic }
                return slot
            },
            order: order.filter { !removedIds.contains($0) }
        )
    }

    /// Contas legadas que leem um IDE/app instalado não podem sair (voltariam no próximo
    /// launch de qualquer jeito); o GrokBot sai junto do Cursor dele, nunca sozinho.
    static func canRemove(_ id: String) -> Bool {
        guard let kind = AccountID.kind(of: id) else { return false }
        if kind == .grokbot { return false }
        return !(AccountID.isLegacy(id) && kind.legacyIsMachineBound)
    }

    /// Ids que saem junto: a conta do Cursor leva o GrokBot gêmeo.
    static func cascadeIds(for id: String) -> [String] {
        AccountID.kind(of: id) == .cursor ? [id, AccountID.grokBotId(forCursor: id)] : [id]
    }
}
