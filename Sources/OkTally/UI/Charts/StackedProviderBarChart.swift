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

    var body: some View {
        Chart(points, id: \.self) { point in
            BarMark(
                x: .value(L("Dia"), TokenAnalytics.date(fromDay: point.day) ?? Date(), unit: .day),
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
