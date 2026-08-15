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

    /// A cor da escala de uso para esta sobra. **Ponto único de cor por percentual do
    /// app inteiro** — popover, herói, asas do notch, barra contínua, barra de menu,
    /// tabela da Visão geral e detalhe passam por aqui.
    ///
    /// Antes eram três degraus (ciano com folga, Heat Orange abaixo de 30%, Neon Magenta
    /// abaixo de 10%). Como quase toda cota está folgada quase sempre, o app ficava
    /// "sempre azul" e a cor não dizia nada de relance. Agora a cor é CONTÍNUA: cada
    /// percentual tem o seu tom, e o olho lê o estado sem ler o número. Os tons e os
    /// pontos de virada vêm da escala, que o dono edita em Preferências
    /// (`UsageColorScale`).
    ///
    /// Sem percentual (saldo puro em dólares) não há posição na escala — fica o acento.
    static func color(remaining: Double?) -> Color {
        guard let remaining else { return Theme.accent }
        return Color(usage: UsageColorScaleHolder.current.color(atRemaining: remaining))
    }

    /// Cor do NÚMERO num contexto que já se sabe ESCURO — hoje só o painel do notch, que
    /// é preto sólido independentemente do tema do sistema. Quem desenha em superfície
    /// que muda com o tema usa `valueStyle`.
    ///
    /// Existia para manter o número neutro com folga e colorir só na exceção — regra que
    /// fazia sentido enquanto a escala tinha três degraus, e que é justamente o que
    /// deixava a tela sem informação de cor. Com a escala contínua o número colorido É a
    /// leitura rápida.
    static func valueColor(remaining: Double?) -> Color {
        color(remaining: remaining)
    }

    /// A cor do número **resolvida pelo tema**: a mesma da escala no escuro, escurecida
    /// no claro.
    ///
    /// Existe porque a escala tem tons claros (amarelo, verde) e no tema claro eles
    /// caem sobre um card BRANCO — o amarelo dá 1,3:1 ali, ou seja, some. No escuro nada
    /// muda. É um `ShapeStyle` e não uma `Color` porque só o `resolve(in:)` enxerga o
    /// `colorScheme`; um `Color` calculado fora da view não tem como saber o tema (foi
    /// exatamente essa a armadilha que fez o app inteiro ser julgado no tema errado uma
    /// vez — ver `ThemeColor`).
    static func valueStyle(remaining: Double?) -> AnyShapeStyle {
        AnyShapeStyle(UsageValueStyle(remaining: remaining))
    }

    /// A mesma cor, legível sobre a barra de menu do sistema.
    ///
    /// A barra clara é o único fundo CLARO onde a escala aparece — e é onde o amarelo da
    /// escala sumiria. Sobre a barra escura a cor sai intacta.
    static func menuBarColor(remaining: Double?, onDarkBar: Bool) -> Color {
        guard let remaining else { return MenuBarInk.color(onDarkBar: onDarkBar) }
        let base = UsageColorScaleHolder.current.color(atRemaining: remaining)
        guard !onDarkBar else { return Color(usage: base) }
        // A barra clara do macOS é praticamente branca; é contra ela que o amarelo da
        // escala precisa de 4,5:1 para continuar sendo um número e não um borrão.
        return Color(usage: base.darkened(againstBackground: Self.lightMenuBar))
    }

    /// Aproximação da barra de menu clara do sistema.
    private static let lightMenuBar = UsageRGB(red: 0.95, green: 0.95, blue: 0.95)

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

/// Ver `QuotaPresentation.valueStyle(remaining:)`.
private struct UsageValueStyle: ShapeStyle {
    let remaining: Double?

    func resolve(in environment: EnvironmentValues) -> Color {
        let base = QuotaPresentation.color(remaining: remaining)
        guard environment.colorScheme == .light else { return base }
        // 4:1 e não 4,5:1 — o número é bold de 15pt para cima, a faixa de "texto grande"
        // da WCAG; exigir 4,5 escureceria o amarelo até virar marrom.
        return Color(usage: base.usageRGB.darkened(
            againstBackground: UsageRGB(red: 1, green: 1, blue: 1), minRatio: 4.0))
    }
}
