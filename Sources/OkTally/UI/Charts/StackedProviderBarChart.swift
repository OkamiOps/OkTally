// Sources/OkTally/UI/Charts/StackedProviderBarChart.swift
import SwiftUI
import Charts

/// Barras diárias empilhadas por provider: resolve "tendência ao longo do tempo" e
/// "distribuição entre providers" na mesma figura, usando as cores de identidade que já
/// existem em `ProviderPalette`.
struct StackedProviderBarChart: View {
    let points: [TrendPoint]
    let providerName: (String) -> String

    private var providerIds: [String] {
        Array(Set(points.map(\.providerId))).sorted()
    }

    /// Pré-parseia `day` uma vez por avaliação de `body`, com um único `DateFormatter`
    /// reaproveitado — mesmo motivo de `DailyTokensAreaChart.datedPoints`:
    /// `TokenAnalytics.date(fromDay:)` chamado direto no `body` alocava um formatter por
    /// ponto (3 providers × 365 dias ≈ 60ms por render). O formatter fica local à
    /// avaliação, nunca `static`/compartilhado entre threads.
    private var datedPoints: [DatedTrendPoint] {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        return points.map { point in
            DatedTrendPoint(
                day: point.day,
                providerId: point.providerId,
                tokens: point.tokens,
                date: fmt.date(from: point.day) ?? Date()
            )
        }
    }

    var body: some View {
        Chart(datedPoints, id: \.self) { point in
            BarMark(
                x: .value(L("Dia"), point.date, unit: .day),
                y: .value(L("Tokens"), point.tokens)
            )
            // Categoria é o nome exibido, não o id: senão a legenda mostra "codex" cru.
            .foregroundStyle(by: .value(L("Provedor"), providerName(point.providerId)))
        }
        .chartForegroundStyleScale(
            domain: providerIds.map(providerName),
            range: providerIds.map { ProviderPalette.color(for: $0) }
        )
        .chartLegend(position: .bottom, spacing: Theme.Space.sm)
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let tokens = value.as(Int.self) {
                        Text(TokenAnalytics.compactTokens(tokens))
                    }
                }
            }
        }
    }
}

// Synthesize automático de `Hashable` exige a conformidade no mesmo arquivo do tipo
// original (`TrendSeries.swift`); daqui, precisa da implementação manual.
extension TrendPoint: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(day)
        hasher.combine(providerId)
        hasher.combine(tokens)
    }
}

/// `TrendPoint` com a data já parseada — o que o `Chart` de fato itera, para não repetir
/// o parsing de `day` por mark. Declarado e conformado a `Hashable` neste mesmo arquivo,
/// então a sintetização automática funciona sem implementação manual.
private struct DatedTrendPoint: Hashable {
    let day: String
    let providerId: String
    let tokens: Int
    let date: Date
}
