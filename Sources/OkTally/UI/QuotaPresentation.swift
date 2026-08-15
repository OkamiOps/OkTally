// Sources/OkTally/UI/QuotaPresentation.swift
import SwiftUI

/// Presentation helpers for rendering a quota window the way the reference design does:
/// a bar of the *remaining* fraction, a "X% restante" label, and a reset countdown.
enum QuotaPresentation {
    /// Remaining fraction (0…1) for windows that have a percentage; nil for pure balances.
    static func remainingFraction(_ shape: QuotaShape) -> Double? {
        guard let used = shape.usedPercent else { return nil }
        return max(0, min(1, (100 - used) / 100))
    }

    /// Primary right-aligned value, e.g. "98% restante" or "37.5 USD".
    static func remainingText(_ shape: QuotaShape) -> String {
        if let used = shape.usedPercent {
            let left = Int((100 - used).rounded())
            let prefix = shape.isEstimated ? "~" : ""
            return prefix + LF("%d%% restante", left)
        }
        switch shape {
        case .creditBalance(let remaining, let currency):
            return "\(format(remaining)) \(currency)"
        case .meteredOnly(let cost):
            return LF("$%@ usado", format(cost))
        default:
            return ""
        }
    }

    /// Just the value, without the "restante"/"left" word: "26%", "~62%", "19.82 USD".
    /// Exists so a layout can print the number once and label it separately (the popover
    /// hero prints a 36pt "26%" over the word "restante" — `remainingText` would repeat
    /// the number that the rest of the block already carries).
    static func remainingValueText(_ shape: QuotaShape) -> String {
        if let used = shape.usedPercent {
            let left = Int((100 - used).rounded())
            return (shape.isEstimated ? "~" : "") + "\(left)%"
        }
        return remainingText(shape)
    }

    /// Reset countdown like "Reseta em 3h 24m"; nil when there's no meaningful future reset.
    static func resetText(_ shape: QuotaShape, now: Date = Date()) -> String? {
        guard let s = resetCompactText(shape, now: now) else { return nil }
        return LF("Reseta em %@", s)
    }

    /// Bare countdown ("15h 23m", "1d 17h", "11d") for dense rows where the column
    /// position already says what the number means. The full sentence truncated to
    /// "Resets in 2h 4…" in a 360pt popover; this never does.
    static func resetCompactText(_ shape: QuotaShape, now: Date = Date()) -> String? {
        guard let reset = shape.resetAt, reset.timeIntervalSince(now) > 60 else { return nil }
        let fmt = DateComponentsFormatter()
        fmt.unitsStyle = .abbreviated
        fmt.allowedUnits = [.day, .hour, .minute]
        fmt.maximumUnitCount = 2
        return fmt.string(from: now, to: reset)
    }

    /// Escala de perigo NA PALETA DA MARCA: Volt Cyan com folga, Heat Orange no meio,
    /// Neon Magenta no fim. Substitui verde/laranja/vermelho do sistema — que, além de
    /// não ser da marca, pintava o app inteiro de verde (quase toda cota está folgada) e
    /// deixava a tela monocromática justamente onde ela deveria ser categórica.
    ///
    /// Magenta no lugar do vermelho é deliberado: contra a base quase preta o vermelho
    /// puro escurece e some, e o magenta da marca é a cor mais alta em saturação — é o
    /// alarme que se enxerga de longe.
    static func color(remaining: Double?) -> Color {
        guard let remaining else { return Theme.accent }
        if remaining <= 0.10 { return Theme.Brand.neonMagenta }
        if remaining <= 0.30 { return Theme.Brand.heatOrange }
        return Theme.accent
    }

    /// Cor do NÚMERO numa lista: neutro quando há folga, cor da escala quando aperta.
    ///
    /// `color(remaining:)` sozinho pintava toda a lista de ciano — quase toda cota está
    /// folgada, então a tela virava monocromática e a cor deixava de significar coisa
    /// alguma. Aqui a regra é a das referências: neutro é o normal, cor é a exceção que
    /// pede atenção. A variedade cromática da tela vem dos chips e das barras de
    /// identidade, que são categóricos por natureza.
    static func valueColor(remaining: Double?) -> Color {
        guard let remaining else { return .primary }
        return remaining > 0.30 ? .primary : color(remaining: remaining)
    }

    /// Worst (lowest-remaining) status color across a provider's windows, for its tab dot.
    static func providerColor(_ snapshot: ProviderSnapshot?) -> Color {
        guard let snapshot else { return .secondary }
        let remainings = snapshot.quotas.compactMap { remainingFraction($0.shape) }
        guard let worst = remainings.min() else { return .secondary }
        return color(remaining: worst)
    }

    private static func format(_ d: Decimal) -> String {
        let n = NSDecimalNumber(decimal: d)
        return String(format: "%.2f", n.doubleValue)
    }
}
