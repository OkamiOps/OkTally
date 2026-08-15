// Sources/OkTally/UI/Charts/DailyTokensAreaChart.swift
import SwiftUI
import Charts

/// Área com gradiente do volume diário. Usada atrás do número-herói e no popover, onde
/// precisa ficar decorativa (`showsAxes: false`) e não competir com o valor.
struct DailyTokensAreaChart: View {
    let points: [DailyTokens]
    let color: Color
    var showsAxes: Bool = false

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
    }
}
