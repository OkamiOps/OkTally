// Sources/OkTally/UI/Charts/DailyTokensAreaChart.swift
import SwiftUI
import Charts

/// Área com gradiente do volume diário. Usada atrás do número-herói e no popover, onde
/// precisa ficar decorativa (`showsAxes: false`) e não competir com o valor.
struct DailyTokensAreaChart: View {
    let points: [DailyTokens]
    let color: Color
    var showsAxes: Bool = false

    var body: some View {
        Chart(points, id: \.day) { point in
            AreaMark(
                x: .value(L("Dia"), TokenAnalytics.date(fromDay: point.day) ?? Date()),
                y: .value(L("Tokens"), point.tokens)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(
                LinearGradient(colors: [color.opacity(0.45), color.opacity(0.02)],
                               startPoint: .top, endPoint: .bottom)
            )
            LineMark(
                x: .value(L("Dia"), TokenAnalytics.date(fromDay: point.day) ?? Date()),
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
