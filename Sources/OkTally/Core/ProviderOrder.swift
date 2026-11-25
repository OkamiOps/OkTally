// Sources/OkTally/Core/ProviderOrder.swift
import Foundation

/// Ordem visível das contas: a que o dono arrumou, ou a lista histórica das
/// Preferências quando ele ainda não tocou em nada.
enum ProviderOrder {
    /// A sequência que a sidebar de Preferências usava hardcoded. Quem atualiza
    /// sem nunca reordenar continua vendo isto — não a ordem de `registry.register`.
    static let defaultIDs = [
        "claude", "codex", "supergrok", "cursor", "cursor-grokbot", "copilot",
        "antigravity", "devin", "openrouter", "minimax", "opencode", "mimo"
    ]

    /// Defaults adicionados depois que usuários já tinham uma ordem persistida. A lista
    /// existe para migrar esses tipos sem reordenar provedores antigos que um teste ou
    /// instalação parcial não tinha registrado.
    static let newlyIntroducedDefaultIDs: Set<String> = ["devin"]

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
            // Migração de tipo novo em instalação antiga: entra na posição histórica
            // dele. Qualquer outro id ausente da ordem salva (incluindo contas extras)
            // segue no fim, como sempre.
            if Self.newlyIntroducedDefaultIDs.contains(id), let defaultIndex = Self.defaultIDs.firstIndex(of: id) {
                var insertion = result.endIndex
                for later in Self.defaultIDs.dropFirst(defaultIndex + 1) {
                    if let index = result.firstIndex(of: later) {
                        insertion = index
                        break
                    }
                }
                result.insert(id, at: insertion)
            } else {
                result.append(id)
            }
        }
        return result
    }
}
