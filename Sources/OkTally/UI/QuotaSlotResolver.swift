// Sources/OkTally/UI/QuotaSlotResolver.swift
import Foundation

/// De `QuotaSlot` para a janela concreta que o pixel vai mostrar. Puro, para as regras
/// (ordem, desempate, queda para automático) serem testáveis sem tela.
///
/// Três lugares usam isto e precisam concordar: a asa esquerda do notch, a asa direita e
/// o número da barra de menu. Se cada um resolvesse "a pior janela" com um critério
/// próprio, o notch e a barra mostrariam provedores diferentes no mesmo instante — e o
/// dono não teria como saber qual dos dois está mentindo.
enum QuotaSlotResolver {

    /// As janelas candidatas, da mais apertada para a mais folgada.
    ///
    /// Com pinos, as candidatas são os pinos — fixar continua sendo o jeito de dizer
    /// "acompanhe estas". Sem pinos, uma janela por provedor (a mais apertada de cada),
    /// que é a mesma base que o painel do notch já usava: um provedor com 5h + semanal
    /// não pode ocupar as duas asas e esconder todos os outros.
    static func ranked(
        pins: [AppModel.MenuBarPin],
        snapshots: [String: ProviderSnapshot],
        providerOrder: [String]
    ) -> [MenuBarLabelModel.Candidate] {
        let base = pins.isEmpty
            ? NotchHUDModel.automaticCandidates(snapshots: snapshots, providerOrder: providerOrder)
            : MenuBarLabelModel.candidates(pins: pins, snapshots: snapshots)
        return sortedByTightness(base)
    }

    /// Ordem de aperto com desempate determinístico.
    ///
    /// Saldos em dólares vão para o fim (`.infinity`): não existe "aperto" comparável
    /// entre um saldo e uma porcentagem, e tratá-los como 0% os colocaria no topo como se
    /// fossem a emergência do dia. Empate de sobra desempata pelo reset mais próximo e,
    /// se ainda empatar, pela posição de entrada — sem esse último critério a asa poderia
    /// trocar de provedor a cada recomposição, porque `snapshots` é um dicionário.
    private static func sortedByTightness(
        _ candidates: [MenuBarLabelModel.Candidate]
    ) -> [MenuBarLabelModel.Candidate] {
        candidates.enumerated()
            .map { index, candidate -> (Int, MenuBarLabelModel.Candidate, Double) in
                (index, candidate, QuotaPresentation.remainingFraction(candidate.window.shape) ?? .infinity)
            }
            .sorted { lhs, rhs in
                if lhs.2 != rhs.2 { return lhs.2 < rhs.2 }
                let lReset = lhs.1.window.shape.resetAt ?? .distantFuture
                let rReset = rhs.1.window.shape.resetAt ?? .distantFuture
                if lReset != rReset { return lReset < rReset }
                return lhs.0 < rhs.0
            }
            .map(\.1)
    }

    /// A janela de um slot, ou `nil` quando não há nada para mostrar.
    ///
    /// Escolha explícita que deixou de existir (provedor deslogado, cota que o serviço
    /// parou de devolver) NÃO vira buraco: o slot cai para automático em silêncio. O
    /// contrário — apagar a asa e esperar que o dono vá às Preferências entender por quê —
    /// transformaria um logout em um bug aparente.
    static func resolve(
        _ slot: QuotaSlot,
        ranked: [MenuBarLabelModel.Candidate],
        snapshots: [String: ProviderSnapshot],
        excluding: MenuBarLabelModel.Candidate? = nil
    ) -> MenuBarLabelModel.Candidate? {
        if case .window(let providerId, let windowLabel) = slot,
           let snapshot = snapshots[providerId],
           let window = snapshot.quotas.first(where: { $0.label == windowLabel }) {
            return MenuBarLabelModel.Candidate(providerId: providerId, window: window)
        }
        return ranked.first { $0 != excluding }
    }

    /// As duas asas do notch fechado, resolvidas juntas.
    ///
    /// A direita é resolvida DEPOIS e sabendo o que a esquerda pegou: em automático, duas
    /// asas mostrando o mesmo número seria o pior resultado possível — gastaria os dois
    /// lugares para dizer uma coisa só. Uma escolha explícita, porém, manda: se o dono
    /// pediu a mesma cota dos dois lados, é isso que ele vê.
    static func wings(
        leading: QuotaSlot,
        trailing: QuotaSlot,
        pins: [AppModel.MenuBarPin],
        snapshots: [String: ProviderSnapshot],
        providerOrder: [String]
    ) -> (leading: MenuBarLabelModel.Candidate?, trailing: MenuBarLabelModel.Candidate?) {
        let ranked = self.ranked(pins: pins, snapshots: snapshots, providerOrder: providerOrder)
        let left = resolve(leading, ranked: ranked, snapshots: snapshots)
        let right = resolve(trailing, ranked: ranked, snapshots: snapshots, excluding: left)
        return (left, right)
    }

    /// Todas as janelas que um `Picker` pode oferecer, na ordem de leitura das
    /// Preferências: os provedores na ordem visível das contas e, dentro de cada um, a
    /// ordem em que o provedor devolveu as janelas.
    ///
    /// Ordem das contas e não de aperto: uma lista que se reordena sozinha entre duas
    /// aberturas do menu é impossível de usar.
    static func availableWindows(
        snapshots: [String: ProviderSnapshot],
        providerOrder: [String]
    ) -> [QuotaSlot] {
        let order = providerOrder + snapshots.keys.sorted().filter { !providerOrder.contains($0) }
        return order.flatMap { providerId in
            (snapshots[providerId]?.quotas ?? []).map {
                QuotaSlot.window(providerId: providerId, windowLabel: $0.label)
            }
        }
    }

    /// O card-herói do popover: a escolha explícita do dono, ou — em automático — a pior
    /// janela entre as candidatas relevantes. No Codex, a candidata automática é o
    /// Weekly geral; limites do Spark continuam disponíveis como escolha explícita.
    ///
    /// Não recebe pinos de propósito: ao contrário das asas e da barra inferior do notch,
    /// o herói do popover não é restrito ao conjunto fixado — ele responde ao que está
    /// pior entre os provedores com dado, pinados ou não.
    ///
    /// `snapshots` já vem filtrado pelo chamador (sem provedores deslogados/sem dado) —
    /// é o mesmo filtro que decide o que aparece na lista abaixo do herói, então uma
    /// escolha explícita que aponte para fora dele já cai em automático por não ser
    /// encontrada, sem lógica extra aqui.
    static func popoverHero(
        slot: QuotaSlot,
        snapshots: [String: ProviderSnapshot],
        providerOrder: [String]
    ) -> MenuBarLabelModel.Candidate? {
        if case .window(let providerId, let windowLabel) = slot,
           let snapshot = snapshots[providerId],
           let window = snapshot.quotas.first(where: { $0.label == windowLabel }) {
            return MenuBarLabelModel.Candidate(providerId: providerId, window: window)
        }
        // Ordem de registry para o desempate: fração e reset iguais não podem fazer o
        // herói trocar de provedor a cada recomposição por causa da ordem de um
        // dicionário.
        let order = providerOrder + snapshots.keys.sorted().filter { !providerOrder.contains($0) }
        var best: MenuBarLabelModel.Candidate?
        var bestFraction = Double.infinity
        var bestReset = Date.distantFuture
        for providerId in order {
            guard let snapshot = snapshots[providerId] else { continue }
            // Model-specific Codex limits stay selectable explicitly, but the automatic
            // headline represents Codex with its general Weekly quota.
            let windows = providerId == "codex"
                ? PopoverLayout.primaryWindow(providerId: providerId, quotas: snapshot.quotas).map { [$0] } ?? []
                : snapshot.quotas
            for window in windows {
                guard let remaining = QuotaPresentation.remainingFraction(window.shape) else { continue }
                let reset = window.shape.resetAt ?? .distantFuture
                if remaining < bestFraction || (remaining == bestFraction && reset < bestReset) {
                    best = MenuBarLabelModel.Candidate(providerId: providerId, window: window)
                    bestFraction = remaining
                    bestReset = reset
                }
            }
        }
        return best
    }
}

/// A barra fina da borda inferior do notch fechado.
///
/// Só percentual mora aqui: um saldo em dólares não tem "quanto resta" para preencher
/// uma barra — sem teto conhecido, qualquer preenchimento seria inventado. Por isso o
/// tipo carrega `remaining` não-opcional e a ausência de barra é representada pelo
/// `nil` do resolvedor, não por um valor vazio.
struct NotchBottomBar: Equatable {
    let providerId: String
    let windowLabel: String
    /// Fração RESTANTE (0…1) — cheia é folga, igual a toda barra do app.
    let remaining: Double
}

extension QuotaSlotResolver {

    /// A cota da barra inferior do notch.
    ///
    /// Em automático é a MAIS APERTADA, sem exclusão nenhuma: ao contrário da asa
    /// direita, esta barra não está tentando dizer uma segunda coisa — ela é o alarme, e
    /// o alarme é sempre sobre a pior cota. Que ela coincida com a asa esquerda em
    /// automático é o comportamento pedido, não um efeito colateral.
    ///
    /// Devolve `nil` quando não há nenhuma janela com percentual (por exemplo, só
    /// provedores de saldo logados): a barra some em vez de mentir um preenchimento.
    static func bottomBar(
        slot: QuotaSlot,
        pins: [AppModel.MenuBarPin],
        snapshots: [String: ProviderSnapshot],
        providerOrder: [String]
    ) -> NotchBottomBar? {
        let ranked = self.ranked(pins: pins, snapshots: snapshots, providerOrder: providerOrder)
        guard let candidate = resolve(slot, ranked: ranked, snapshots: snapshots),
              let remaining = QuotaPresentation.remainingFraction(candidate.window.shape)
        else { return nil }
        return NotchBottomBar(
            providerId: candidate.providerId,
            windowLabel: candidate.window.label,
            remaining: remaining
        )
    }
}
