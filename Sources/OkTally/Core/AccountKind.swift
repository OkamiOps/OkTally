// Sources/OkTally/Core/AccountKind.swift
import Foundation

/// O que o provedor É (cor, glifo, painel, config OAuth). Distinto do id da instância,
/// que é a chave em todo o resto do app (registry, scheduler, SQLite, Keychain, pinos).
enum AccountKind: String, CaseIterable, Codable {
    case claude, codex, supergrok, cursor
    case grokbot = "cursor-grokbot"
    case copilot, antigravity, openrouter, minimax, opencode, mimo

    /// Tipos que aceitam segunda conta. OpenCode e MiMo ficam de fora por decisão do dono
    /// (a estimativa do OpenCode e a sessão web do MiMo são da máquina, não da conta);
    /// Copilot não foi pedido; o GrokBot nasce junto de cada conta do Cursor.
    static var addableKinds: [AccountKind] { [.claude, .codex, .supergrok] }

    /// Tipos cujo legado lê um app de terceiros (IDE/CLI) e por isso não podem ser removidos.
    var legacyIsMachineBound: Bool {
        switch self {
        case .cursor, .grokbot, .antigravity, .copilot, .mimo: return true
        default: return false
        }
    }
}

/// Formato do id de instância: `kind` (a conta legada, idêntica ao app de antes) ou
/// `kind#xxxxxx` (6 hex) para contas extras. O `#` foi escolhido porque `\u{1}`
/// (pinos/slots), `\u{2}` (providerOrder/lista de pinos) e `-` (`cursor-grokbot`) já têm
/// dono — por isso nunca se quebra um id em `-`.
enum AccountID {
    static let separator: Character = "#"

    static func kind(of instanceId: String) -> AccountKind? {
        let prefix = instanceId.split(separator: separator, maxSplits: 1, omittingEmptySubsequences: false).first
        return prefix.flatMap { AccountKind(rawValue: String($0)) }
    }

    static func isLegacy(_ instanceId: String) -> Bool { !instanceId.contains(separator) }

    static func suffix(of instanceId: String) -> String? {
        instanceId.split(separator: separator, maxSplits: 1).dropFirst().first.map(String.init)
    }

    static func make(kind: AccountKind, suffix: String = randomSuffix()) -> String {
        "\(kind.rawValue)\(separator)\(suffix)"
    }

    /// Reaproveita o id legado quando ele está livre (o dono removeu a conta original e
    /// adicionou de novo): assim a conta volta a ser "a de sempre", sem sufixo.
    static func nextId(kind: AccountKind, existing: [String], suffix: String = randomSuffix()) -> String {
        existing.contains(kind.rawValue) ? make(kind: kind, suffix: suffix) : kind.rawValue
    }

    /// O GrokBot segue a conta do Cursor que o alimenta: `cursor#abc` → `cursor-grokbot#abc`.
    static func grokBotId(forCursor cursorId: String) -> String {
        suffix(of: cursorId).map { make(kind: .grokbot, suffix: $0) } ?? AccountKind.grokbot.rawValue
    }

    /// O inverso de `grokBotId(forCursor:)`.
    static func cursorId(forGrokBot grokBotId: String) -> String {
        suffix(of: grokBotId).map { make(kind: .cursor, suffix: $0) } ?? AccountKind.cursor.rawValue
    }

    static func randomSuffix() -> String {
        String(UUID().uuidString.lowercased().filter(\.isHexDigit).prefix(6))
    }
}
