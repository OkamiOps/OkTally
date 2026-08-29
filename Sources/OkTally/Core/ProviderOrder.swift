// Sources/OkTally/Core/ProviderOrder.swift
import Foundation

/// Ordem visível das contas: a que o dono arrumou, ou a lista histórica das
/// Preferências quando ele ainda não tocou em nada.
enum ProviderOrder {
    /// A sequência que a sidebar de Preferências usava hardcoded. Quem atualiza
    /// sem nunca reordenar continua vendo isto — não a ordem de `registry.register`.
    static let defaultIDs = [
        "claude", "codex", "supergrok", "cursor", "cursor-grokbot", "copilot",
        "antigravity", "openrouter", "minimax", "opencode", "mimo"
    ]

    /// Resolve a ordem mostrada.
    ///
    /// - `saved` vazio = nunca persistido → usa `defaultIDs`.
    /// - ids salvos que o registry não conhece saem da lista visível (o storage
    ///   não é reescrito aqui).
    /// - ids conhecidos que ainda não estão em `saved` entram no fim, na ordem
    ///   em que `known` os apresentou.
    static func resolved(saved: [String], known: [String]) -> [String] {
        let seed = saved.isEmpty ? defaultIDs : saved
        var seen = Set<String>()
        let knownSet = Set(known)
        var result: [String] = []
        result.reserveCapacity(known.count)
        for id in seed where knownSet.contains(id) && seen.insert(id).inserted {
            result.append(id)
        }
        for id in known where seen.insert(id).inserted {
            result.append(id)
        }
        return result
    }
}
