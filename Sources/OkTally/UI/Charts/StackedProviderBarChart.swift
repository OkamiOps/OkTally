// Sources/OkTally/UI/Charts/StackedProviderBarChart.swift
import SwiftUI
import Charts

/// Barras diárias empilhadas por provider: resolve "tendência ao longo do tempo" e
/// "distribuição entre providers" na mesma figura, usando as cores de identidade que já
/// existem em `ProviderPalette`.
struct StackedProviderBarChart: View {
    let points: [TrendPoint]
    let providerName: (String) -> String

    @Environment(\.chartHoverPreview) private var hoverPreview

    @State private var hoveredDay: String?

    private var providerIds: [String] {
        Array(Set(points.map(\.providerId))).sorted()
    }

    /// Dias presentes na série, em ordem — o domínio de encaixe do cursor.
    private var days: [String] {
        Array(Set(points.map(\.day))).sorted()
    }

    /// O dia em foco: o do cursor ou, num render estático, o forçado pelo harness.
    private var selectedDay: String? {
        hoveredDay ?? hoverPreview?.day.flatMap { days.contains($0) ? $0 : nil }
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
            // Rebaixa o RESTO em vez de acender o escolhido: a cor de cada barra é a
            // identidade do provedor e carrega significado — clareá-la mentiria sobre
            // quem é quem. Com `selectedDay == nil` todas voltam a 1.
            .opacity(selectedDay == nil || selectedDay == point.day ? 1 : Theme.dimmedOpacity)
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
        .animation(Theme.hoverTransition, value: selectedDay)
        .chartOverlay { proxy in overlay(proxy: proxy) }
    }

    // MARK: - Hover

    private func overlay(proxy: ChartProxy) -> some View {
        GeometryReader { geo in
            let plot = proxy.plotFrame.map { geo[$0] } ?? .zero
            let domain = days
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover(coordinateSpace: .local) { phase in
                        switch phase {
                        case .active(let location):
                            guard let date = proxy.value(atX: location.x - plot.minX, as: Date.self),
                                  let day = ChartHover.nearestDay(in: domain, to: date)
                            else { return }
                            if day != hoveredDay { hoveredDay = day }
                        case .ended:
                            hoveredDay = nil
                        }
                    }
                if let day = selectedDay, let date = TokenAnalytics.date(fromDay: day) {
                    let total = ChartHover.total(points: points, day: day)
                    let x = plot.minX + (proxy.position(forX: date) ?? 0)
                    // Âncora no TOPO da pilha daquele dia, não no cursor: o cartão fica
                    // junto do dado que descreve, e não no meio do vazio acima da barra.
                    let y = plot.minY + (proxy.position(forY: total) ?? 0)
                    ChartHoverRule(x: x, top: plot.minY, bottom: plot.maxY, color: Theme.accent)
                    ChartTooltipLayer(anchor: CGPoint(x: x, y: y), bounds: plot) {
                        card(day: day, date: date, total: total)
                    }
                }
            }
        }
    }

    private func card(day: String, date: Date, total: Int) -> some View {
        let rows = ChartHover.breakdown(points: points, day: day)
        return ChartTooltip(
            title: ChartHover.dayLabel(date),
            value: TokenAnalytics.compactTokens(total),
            caption: LF("%@ tokens", ChartHover.groupedTokens(total)),
            rows: rows.map { row in
                ChartTooltipRow(
                    id: row.providerId,
                    color: ProviderPalette.color(for: row.providerId),
                    name: providerName(row.providerId),
                    value: TokenAnalytics.compactTokens(row.tokens),
                    percent: ChartHover.percentLabel(row.fraction)
                )
            }
        )
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
