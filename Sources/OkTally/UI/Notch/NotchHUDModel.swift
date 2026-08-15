// Sources/OkTally/UI/Notch/NotchHUDModel.swift
import Foundation

/// Uma cota escolhida para o painel do notch.
struct NotchQuotaEntry: Equatable, Identifiable {
    /// Provedor + janela. O rótulo sozinho não serve de identidade: "weekly" existe em
    /// pelo menos três provedores, e um `ForEach` com ids repetidos desenha uma linha só.
    var id: String { providerId + "\u{1}" + windowLabel }
    let providerId: String
    let windowLabel: String
    /// Fração restante (0…1); `nil` para saldos, que não têm porcentagem.
    let remaining: Double?
    let danger: DangerLevel
}

/// Escolha e ordem do que o painel do notch mostra — puro, para ser testável sem tela.
///
/// Fechado e expandido mostram exatamente a MESMA lista: fechado desenha um tracinho por
/// item, expandido desenha uma linha por item. Se as duas listas divergissem, o painel
/// mentiria durante a animação de expansão — o tracinho que o olho estava seguindo viraria
/// outra coisa.
enum NotchHUDModel {
    /// Teto de itens. Fechado, os tracinhos precisam caber nos ~90pt de cada lado do
    /// notch sem empurrar o painel para cima dos menus do app da frente; expandido, seis
    /// linhas ou mais transformariam um HUD de relance numa segunda janela.
    static let maxEntries = 5

    /// As cotas que o dono está acompanhando.
    ///
    /// Com pinos: os pinos, na ordem em que foram fixados — a mesma ordem que as
    /// Preferências deixam arrastar. Sem pinos: a janela mais apertada de CADA provedor,
    /// das mais apertadas para as mais folgadas. Um provedor não pode ocupar duas linhas
    /// no modo automático; senão o Claude (5h + semanal) sozinho comeria dois dos cinco
    /// lugares e esconderia um provedor inteiro.
    static func entries(
        pins: [AppModel.MenuBarPin],
        snapshots: [String: ProviderSnapshot],
        providerOrder: [String],
        limit: Int = maxEntries
    ) -> [NotchQuotaEntry] {
        let chosen = pins.isEmpty
            ? automatic(snapshots: snapshots, providerOrder: providerOrder)
            : MenuBarLabelModel.candidates(pins: pins, snapshots: snapshots)
        return chosen.prefix(max(0, limit)).map(entry(for:))
    }

    /// Uma janela por provedor, da mais apertada para a mais folgada. `providerOrder` (a
    /// ordem do registry) é o desempate: sem ele, dois provedores com a mesma sobra
    /// trocariam de lugar a cada recomposição, porque `snapshots` é um dicionário.
    private static func automatic(
        snapshots: [String: ProviderSnapshot],
        providerOrder: [String]
    ) -> [MenuBarLabelModel.Candidate] {
        // Provedores que o registry não conhece ainda assim aparecem, no fim e por id, em
        // vez de sumirem em silêncio.
        let order = providerOrder + snapshots.keys.sorted().filter { !providerOrder.contains($0) }
        let tightest = order.compactMap { providerId -> (Int, MenuBarLabelModel.Candidate, Double)? in
            guard let snapshot = snapshots[providerId],
                  let window = PopoverLayout.orderedWindows(snapshot.quotas).first
            else { return nil }
            let rank = order.firstIndex(of: providerId) ?? order.count
            // Saldos vão para o fim: não há "aperto" para comparar com uma porcentagem.
            let remaining = QuotaPresentation.remainingFraction(window.shape) ?? .infinity
            return (rank, MenuBarLabelModel.Candidate(providerId: providerId, window: window), remaining)
        }
        return tightest
            .sorted { lhs, rhs in lhs.2 == rhs.2 ? lhs.0 < rhs.0 : lhs.2 < rhs.2 }
            .map(\.1)
    }

    private static func entry(for candidate: MenuBarLabelModel.Candidate) -> NotchQuotaEntry {
        let remaining = QuotaPresentation.remainingFraction(candidate.window.shape)
        return NotchQuotaEntry(
            providerId: candidate.providerId,
            windowLabel: candidate.window.label,
            remaining: remaining,
            danger: remaining.map(MenuBarLabelModel.danger(remaining:)) ?? .neutral
        )
    }
}
