// Sources/OkTally/Core/AccountPaneRouting.swift
import Foundation

/// Qual painel de Preferências mostrar para um id. Tirado de dentro da view para o
/// `switch` ter teste: a `PreferencesView` não tem nenhum, e é ali que um id de conta
/// extra (`claude#abc123`) cairia no `default` vazio sem ninguém perceber.
enum AccountPaneRoute: Equatable {
    case claude(instanceId: String)
    case codex(instanceId: String)
    case supergrok(instanceId: String)
    case cursor(instanceId: String)
    case grokbot(instanceId: String)
    case copilot
    case antigravity(instanceId: String)
    case minimax(instanceId: String)
    /// OpenRouter e OpenCode: painel genérico de chave de API.
    case apiKey(instanceId: String, kind: AccountKind)
    case mimo
    case unknown
}

enum AccountPaneRouting {
    static func route(for id: String) -> AccountPaneRoute {
        guard let kind = AccountID.kind(of: id) else { return .unknown }
        switch kind {
        case .claude: return .claude(instanceId: id)
        case .codex: return .codex(instanceId: id)
        case .supergrok: return .supergrok(instanceId: id)
        case .cursor: return .cursor(instanceId: id)
        case .grokbot: return .grokbot(instanceId: id)
        case .copilot: return .copilot
        case .antigravity: return .antigravity(instanceId: id)
        case .minimax: return .minimax(instanceId: id)
        case .openrouter, .opencode: return .apiKey(instanceId: id, kind: kind)
        case .mimo: return .mimo
        }
    }

    static func canRemove(_ id: String) -> Bool { AccountRemoval.canRemove(id) }

    /// A conta dona de um provedor: o GrokBot pertence à conta do Cursor dele.
    static func accountId(forProviderId id: String) -> String {
        AccountID.kind(of: id) == .grokbot ? AccountID.cursorId(forGrokBot: id) : id
    }

    /// O GrokBot não tem apelido nem remoção próprios — tudo isso mora na conta do Cursor.
    static func showsAccountSection(_ id: String) -> Bool {
        guard let kind = AccountID.kind(of: id) else { return false }
        return kind != .grokbot
    }
}
