// Sources/OkTally/UI/MenuBarLabelModel.swift
import Foundation

enum DangerLevel: Equatable { case ok, warn, critical, neutral }

struct MenuBarSegment: Equatable {
    let glyph: String?
    let providerId: String?
    let text: String
    let danger: DangerLevel
}

/// Cálculo puro do que a barra de menu mostra — fora da view/renderer para as regras
/// serem testáveis. A barra mostra o percentual *restante*, igual ao "X% restante" do
/// popover (a barra pré-redesenho mostrava o usado).
///
/// A barra carrega UM número só. Ela chegou a imprimir um segmento por pino
/// ("C100 X56 ▷56 G99 M84") e o dono reprovou nestes termos: "muito feios e ruins de
/// ler". Cinco números de 11pt lado a lado no menu do sistema não são um painel, são
/// ruído. O que sobra na barra é o símbolo da marca mais a cota mais crítica — a única
/// informação que justifica ocupar a barra o dia inteiro. Os demais números foram para o
/// painel do notch (`NotchHUDModel`), que sabe usar espaço de verdade.
enum MenuBarLabelModel {

    /// A ÚNICA cota que vai para a barra: a mais apertada entre as candidatas.
    ///
    /// Vence a menor sobra; empate desempata pelo reset mais próximo e, se ainda empatar,
    /// pela ordem determinística das candidatas — `snapshots` é um dicionário, e sem esse
    /// último critério o número da barra poderia trocar entre dois empatados a cada
    /// recomposição.
    static func criticalSegment(
        pins: [AppModel.MenuBarPin],
        snapshots: [String: ProviderSnapshot],
        hasAnyError: Bool
    ) -> MenuBarSegment {
        let candidates = self.candidates(pins: pins, snapshots: snapshots)
        // Janelas com porcentagem primeiro: um saldo em dólares não tem "aperto" para
        // comparar com uma cota em porcento, então ele só aparece quando é tudo o que há.
        let ranked = candidates.enumerated().compactMap { index, candidate -> (Int, Candidate, Double)? in
            QuotaPresentation.remainingFraction(candidate.window.shape).map { (index, candidate, $0) }
        }
        if let best = ranked.min(by: { lhs, rhs in
            if lhs.2 != rhs.2 { return lhs.2 < rhs.2 }
            let lReset = lhs.1.window.shape.resetAt ?? .distantFuture
            let rReset = rhs.1.window.shape.resetAt ?? .distantFuture
            if lReset != rReset { return lReset < rReset }
            return lhs.0 < rhs.0
        }) {
            return segment(providerId: best.1.providerId, shape: best.1.window.shape)
        }
        if let only = candidates.first {
            return segment(providerId: only.providerId, shape: only.window.shape)
        }
        return MenuBarSegment(glyph: nil, providerId: nil,
                              text: hasAnyError ? "!" : "OK", danger: .neutral)
    }

    /// Mesmas faixas de `QuotaPresentation.color(remaining:)`.
    static func danger(remaining: Double) -> DangerLevel {
        if remaining <= 0.10 { return .critical }
        if remaining <= 0.30 { return .warn }
        return .ok
    }

    struct Candidate: Equatable {
        let providerId: String
        let window: QuotaWindow
    }

    /// Janelas elegíveis, em ordem determinística: com pinos, a ordem dos pinos; sem
    /// pinos, provedores por id (o dicionário de snapshots não tem ordem própria) e,
    /// dentro de cada um, a ordem em que o provedor devolveu as janelas.
    ///
    /// Compartilhado com o painel do notch: os dois precisam concordar sobre o que conta
    /// como "as cotas que o dono está acompanhando".
    static func candidates(pins: [AppModel.MenuBarPin], snapshots: [String: ProviderSnapshot]) -> [Candidate] {
        if !pins.isEmpty {
            return pins.compactMap { pin in
                guard let snapshot = snapshots[pin.providerId],
                      let window = snapshot.quotas.first(where: { $0.label == pin.windowLabel })
                else { return nil }
                return Candidate(providerId: pin.providerId, window: window)
            }
        }
        return snapshots.keys.sorted().flatMap { providerId in
            (snapshots[providerId]?.quotas ?? []).map { Candidate(providerId: providerId, window: $0) }
        }
    }

    /// O segmento de UM slot: a janela escolhida quando ela existe, e a mais crítica
    /// quando o slot é automático — ou quando a escolha se refere a uma janela que sumiu
    /// (provedor deslogado). A queda é silenciosa de propósito; ver `QuotaSlotResolver`.
    static func segment(
        slot: QuotaSlot,
        pins: [AppModel.MenuBarPin],
        snapshots: [String: ProviderSnapshot],
        hasAnyError: Bool
    ) -> MenuBarSegment {
        if case .window(let providerId, let windowLabel) = slot,
           let snapshot = snapshots[providerId],
           let window = snapshot.quotas.first(where: { $0.label == windowLabel }) {
            return segment(providerId: providerId, shape: window.shape)
        }
        return criticalSegment(pins: pins, snapshots: snapshots, hasAnyError: hasAnyError)
    }

    static func segment(for candidate: Candidate) -> MenuBarSegment {
        segment(providerId: candidate.providerId, shape: candidate.window.shape)
    }

    static func segment(providerId: String, shape: QuotaShape) -> MenuBarSegment {
        let glyph = ProviderPalette.glyph(forId: providerId)
        if let remaining = QuotaPresentation.remainingFraction(shape) {
            return MenuBarSegment(glyph: glyph, providerId: providerId,
                                  text: String(Int((remaining * 100).rounded())),
                                  danger: danger(remaining: remaining))
        }
        switch shape {
        case .creditBalance(let remaining, _):
            let value = NSDecimalNumber(decimal: remaining).doubleValue
            return MenuBarSegment(glyph: glyph, providerId: providerId,
                                  text: String(format: "%.1f$", value), danger: .neutral)
        case .meteredOnly(let cost):
            let value = NSDecimalNumber(decimal: cost).doubleValue
            return MenuBarSegment(glyph: glyph, providerId: providerId,
                                  text: String(format: "%.1f$", value), danger: .neutral)
        default:
            return MenuBarSegment(glyph: glyph, providerId: providerId, text: "–", danger: .neutral)
        }
    }
}
