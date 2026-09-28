// Sources/OkTally/UI/Charts/DailyTokensAreaChart.swift
import SwiftUI
import Charts

/// Quanto o gráfico de área reage ao cursor.
enum DailyTokensHover {
    /// Decorativo: nenhuma reação. É o papel dele no popover, onde o número grande ao lado
    /// já é a informação e um cartão flutuante só atrapalharia.
    case none
    /// Régua e ponto, e o valor é reportado para QUEM CHAMA mostrar. Para as sparklines de
    /// 70×18 das linhas por provedor: um cartão ali dentro seria maior que o gráfico, e
    /// grampeá-lo na borda o deixaria cobrindo a curva inteira.
    case rule
    /// Régua, ponto e cartão completo — data, valor exato e variação contra o dia anterior.
    case card
}

/// Área com gradiente do volume diário. Usada atrás do número-herói e no popover, onde
/// precisa ficar decorativa (`showsAxes: false`) e não competir com o valor.
struct DailyTokensAreaChart: View {
    let points: [DailyTokens]
    let color: Color
    var showsAxes: Bool = false
    /// Reação ao cursor. `.none` por padrão para o popover continuar exatamente como era.
    var hover: DailyTokensHover = .none
    /// Chamado quando o dia sob o cursor muda (`nil` ao sair). Existe para o modo `.rule`:
    /// quem desenha a linha do provedor é que tem largura para mostrar data e valor.
    var onHoverDay: ((DailyTokens?) -> Void)?

    @Environment(\.chartHoverPreview) private var hoverPreview

    @State private var hoveredDay: String?

    /// Pré-parseia `day` uma vez por avaliação de `body`, com um único `DateFormatter`
    /// reaproveitado. `TokenAnalytics.date(fromDay:)` aloca um formatter por chamada, e o
    /// `body` original chamava duas vezes por ponto (Area + Line) — numa janela de 365
    /// dias isso media ~46ms por render, disparado a cada mudança de estado, hover ou
    /// frame de animação. O formatter continua local (nunca `static`/compartilhado entre
    /// threads), só a alocação sai do laço por ponto.
    private var datedPoints: [(day: String, tokens: Int, date: Date)] {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        return points.map { point in
            (day: point.day, tokens: point.tokens, date: fmt.date(from: point.day) ?? Date())
        }
    }

    /// O dia em foco: o do cursor ou, num render estático, o forçado pelo harness.
    private var selectedDay: String? {
        hoveredDay ?? hoverPreview?.day.flatMap { preview in
            points.contains { $0.day == preview } ? preview : nil
        }
    }

    var body: some View {
        Chart(datedPoints, id: \.day) { point in
            AreaMark(
                x: .value(L("Dia"), point.date),
                y: .value(L("Tokens"), point.tokens)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(
                LinearGradient(colors: [color.opacity(0.45), color.opacity(0.02)],
                               startPoint: .top, endPoint: .bottom)
            )
            LineMark(
                x: .value(L("Dia"), point.date),
                y: .value(L("Tokens"), point.tokens)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(color)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
        }
        .chartXAxis(showsAxes ? .automatic : .hidden)
        .chartYAxis(showsAxes ? .automatic : .hidden)
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            if hover != .none {
                overlay(proxy: proxy)
            }
        }
    }

    // MARK: - Hover

    @ViewBuilder
    private func overlay(proxy: ChartProxy) -> some View {
        GeometryReader { geo in
            let plot = proxy.plotFrame.map { geo[$0] } ?? .zero
            let series = datedPoints
            let spot = selectedDay.flatMap { day in
                series.firstIndex { $0.day == day }.map { (index: $0, point: series[$0]) }
            }
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover(coordinateSpace: .local) { phase in
                        switch phase {
                        case .active(let location):
                            // `value(atX:)` lê no espaço da ÁREA DE PLOTAGEM, que não
                            // começa em zero quando há eixos — daí subtrair `plot.minX`.
                            guard let date = proxy.value(atX: location.x - plot.minX, as: Date.self),
                                  let day = ChartHover.nearestDay(in: series.map(\.day), to: date)
                            else { return }
                            update(day: day, series: series)
                        case .ended:
                            update(day: nil, series: series)
                        }
                    }
                if let spot {
                    let x = plot.minX + (proxy.position(forX: spot.point.date) ?? 0)
                    let y = plot.minY + (proxy.position(forY: spot.point.tokens) ?? 0)
                    ChartHoverRule(x: x, top: plot.minY, bottom: plot.maxY, markerY: y, color: color)
                    if hover == .card {
                        ChartTooltipLayer(anchor: CGPoint(x: x, y: y), bounds: plot) {
                            card(index: spot.index, series: series)
                        }
                    }
                }
            }
            .animation(Theme.hoverTransition, value: selectedDay)
        }
    }

    private func card(index: Int, series: [(day: String, tokens: Int, date: Date)]) -> some View {
        let tokens = series[index].tokens
        let previous = index > 0 ? series[index - 1].tokens : 0
        return ChartTooltip(
            title: ChartHover.dayLabel(series[index].date),
            value: TokenAnalytics.compactTokens(tokens),
            caption: LF("%@ tokens", ChartHover.groupedTokens(tokens)),
            delta: TrendSeries.delta(current: tokens, previous: previous)
        )
    }

    private func update(day: String?, series: [(day: String, tokens: Int, date: Date)]) {
        guard day != hoveredDay else { return }
        hoveredDay = day
        guard let onHoverDay else { return }
        onHoverDay(day.flatMap { key in
            series.first { $0.day == key }.map { DailyTokens(day: $0.day, tokens: $0.tokens) }
        })
    }
}
