// Sources/OkTally/Core/ChartHover.swift
import CoreGraphics
import Foundation

/// Uma linha do detalhamento por provedor dentro de um tooltip: quem, quanto e que
/// fatia do dia.
struct HoverBreakdownRow: Equatable {
    let providerId: String
    let tokens: Int
    /// Participação no total daquele dia, em 0…1.
    let fraction: Double
}

/// A aritmética do hover dos gráficos. Fica fora das views pelo mesmo motivo de
/// `TrendSeries`: encaixe no ponto mais próximo, ordenação do detalhamento, grampeamento
/// da posição do tooltip e formatação são decisões que ou estão certas ou estão erradas —
/// e nenhuma delas precisa de um `Chart` na tela para ser verificada.
///
/// O grampeamento em particular nasceu de um defeito previsível: um tooltip posicionado
/// "ao lado do cursor" some pela direita do card quando o cursor está no último dia, que é
/// justamente o dia que o dono mais olha.
enum ChartHover {

    // MARK: - Encaixe no ponto mais próximo

    /// Índice da amostra mais próxima de `target`. Empate exato volta para a amostra mais
    /// ANTIGA: sem essa regra o tooltip alterna entre dois dias quando o cursor para no
    /// meio, e um valor que oscila sozinho é pior que um valor um pixel deslocado.
    static func nearestIndex(in dates: [Date], to target: Date) -> Int? {
        guard !dates.isEmpty else { return nil }
        var best = 0
        var bestDistance = Double.infinity
        for (index, date) in dates.enumerated() {
            let distance = abs(date.timeIntervalSince(target))
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return best
    }

    /// Mesma busca, com as chaves "yyyy-MM-dd" que as séries do app carregam. Chave que
    /// não parseia é simplesmente ignorada — não vale derrubar o hover por um dia torto.
    static func nearestDay(in days: [String], to target: Date) -> String? {
        let parsed = days.compactMap { day -> (day: String, date: Date)? in
            TokenAnalytics.date(fromDay: day).map { (day, $0) }
        }
        guard let index = nearestIndex(in: parsed.map(\.date), to: target) else { return nil }
        return parsed[index].day
    }

    // MARK: - Detalhamento por provedor

    /// As linhas do dia, da maior para a menor. O desempate é pelo id do provedor: com
    /// dois providers no mesmo valor a ordem viria da ordem de chegada dos pontos, e o
    /// tooltip trocaria as linhas de lugar entre um hover e o seguinte.
    static func breakdown(points: [TrendPoint], day: String) -> [HoverBreakdownRow] {
        let ofDay = points.filter { $0.day == day }
        let total = ofDay.reduce(0) { $0 + $1.tokens }
        return ofDay
            .map { point in
                HoverBreakdownRow(
                    providerId: point.providerId,
                    tokens: point.tokens,
                    // `total` zerado sairia NaN, e `max(0, min(1, .nan))` é 1.0 em Swift:
                    // uma linha de 0 token apareceria como 100%.
                    fraction: total > 0 ? Double(point.tokens) / Double(total) : 0
                )
            }
            .sorted { lhs, rhs in
                lhs.tokens == rhs.tokens ? lhs.providerId < rhs.providerId : lhs.tokens > rhs.tokens
            }
    }

    /// Total do dia — o número grande do tooltip do empilhado.
    static func total(points: [TrendPoint], day: String) -> Int {
        points.filter { $0.day == day }.reduce(0) { $0 + $1.tokens }
    }

    // MARK: - Fatia do donut

    /// `chartAngleSelection` devolve um valor no domínio SOMADO do donut (a posição
    /// acumulada sob o cursor), não o índice da fatia. Isto traduz um no outro.
    ///
    /// Fatias de valor zero não ocupam ângulo nenhum e por isso nunca podem ser o
    /// selecionado — daí a comparação ser feita sobre a soma acumulada e não sobre cada
    /// valor isolado.
    static func sliceIndex(forAngleValue value: Int, in values: [Int]) -> Int? {
        guard !values.isEmpty, value >= 0 else { return nil }
        var running = 0
        for (index, slice) in values.enumerated() {
            guard slice > 0 else { continue }
            running += slice
            if value <= running { return index }
        }
        return nil
    }

    // MARK: - Posição do tooltip

    /// Canto superior esquerdo do tooltip, já grampeado dentro de `bounds`.
    ///
    /// Regra: ao lado direito do cursor, centralizado na vertical; se não couber à
    /// direita, vira para a esquerda; e em último caso encosta na borda. Nunca vaza —
    /// vazar significa ser cortado pelo card, que é o defeito que este cálculo existe
    /// para impedir.
    static func tooltipOrigin(
        anchor: CGPoint,
        tooltipSize: CGSize,
        bounds: CGRect,
        gap: CGFloat = 12
    ) -> CGPoint {
        var x = anchor.x + gap
        if x + tooltipSize.width > bounds.maxX {
            x = anchor.x - gap - tooltipSize.width
        }
        // `min` antes de `max`: numa área mais estreita que o próprio tooltip (a
        // sparkline de 70pt) o `min` mandaria para um valor negativo, e é o `max` que
        // tem a última palavra e encosta na borda esquerda.
        x = max(bounds.minX, min(x, bounds.maxX - tooltipSize.width))

        var y = anchor.y - tooltipSize.height / 2
        y = max(bounds.minY, min(y, bounds.maxY - tooltipSize.height))
        return CGPoint(x: x, y: y)
    }

    // MARK: - Intensidade do heatmap

    /// Os três cortes de quartil dos dias ATIVOS — a mesma conta que pinta as células em
    /// `TokenAnalytics.heatLevels()`. Compartilhado de propósito: cor da célula e texto do
    /// tooltip discordarem ("célula mais forte" com "quartil menos ativo") seria um bug
    /// invisível em revisão de código e óbvio na tela.
    static func quartiles(_ activeTokens: [Int]) -> (q1: Int, q2: Int, q3: Int)? {
        let sorted = activeTokens.sorted()
        guard !sorted.isEmpty else { return nil }
        func quantile(_ q: Double) -> Int {
            sorted[Int((Double(sorted.count - 1) * q).rounded())]
        }
        return (quantile(0.25), quantile(0.5), quantile(0.75))
    }

    /// Nível 0–4 de um dia: 0 = sem uso, 1–4 = quartis dos dias com uso.
    static func quartileLevel(tokens: Int, quartiles: (q1: Int, q2: Int, q3: Int)) -> Int {
        guard tokens > 0 else { return 0 }
        if tokens <= quartiles.q1 { return 1 }
        if tokens <= quartiles.q2 { return 2 }
        if tokens <= quartiles.q3 { return 3 }
        return 4
    }

    /// Onde aquele dia cai na distribuição, em palavras. "2.3M tokens" sozinho não diz se
    /// foi um dia forte; é a comparação que carrega o significado.
    static func intensityLabel(level: Int) -> String? {
        switch level {
        case 4: return L("top 25% dos dias")
        case 3: return L("acima da mediana")
        case 2: return L("abaixo da mediana")
        case 1: return L("25% menos ativos")
        default: return nil
        }
    }

    // MARK: - Formatação

    /// O número inteiro com separador de milhar da localidade. `TokenAnalytics
    /// .compactTokens` arredonda ("1.2M"), e o tooltip é exatamente o lugar onde o dono
    /// quer conferir o valor cheio.
    static func groupedTokens(_ value: Int, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// "1.234.567 · 1.2M" — o exato para conferir e o compacto para ler. Abaixo de mil o
    /// compacto É o exato, e repetir seria ruído.
    static func exactTokens(_ value: Int, locale: Locale = .current) -> String {
        let grouped = groupedTokens(value, locale: locale)
        let compact = TokenAnalytics.compactTokens(value)
        guard abs(value) >= 1_000 else { return grouped }
        return "\(grouped) · \(compact)"
    }

    /// "Sáb, 15 ago" — dia da semana abreviado, dia e mês, no formato da localidade. A
    /// primeira letra vai para maiúscula porque o pt_BR abrevia o dia da semana em
    /// minúscula e num tooltip isso lê como descuido.
    static func dayLabel(_ date: Date, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM")
        let text = formatter.string(from: date)
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    /// Porcentagem inteira, com a fração já grampeada em 0…1 — `NaN` vira 0% em vez de
    /// 100%, pelo mesmo motivo de `Theme.clampFraction` (a guarda está repetida aqui para
    /// o `Core` não depender da camada de UI).
    static func percentLabel(_ fraction: Double) -> String {
        let clamped = fraction.isFinite ? max(0, min(1, fraction)) : 0
        return String(format: "%.0f%%", clamped * 100)
    }
}
