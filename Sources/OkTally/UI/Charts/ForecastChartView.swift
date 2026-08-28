import Charts
import SwiftUI

/// Evolução de uma única janela renovável em percentual **restante**.
///
/// A view recebe o resultado já calculado pelo engine; não recalcula ritmo, não escolhe a
/// janela e não produz copy. Isso mantém a representação numérica independente de
/// `AppModel` e deixa `UsageForecastPresentation` como a única dona de métricas e textos.
struct ForecastChartView: View {
    let forecast: UsageForecast
    let providerColor: Color
    let now: Date

    private static let historyWindow: TimeInterval = 24 * 60 * 60
    private static let minimumDomain: TimeInterval = 60 * 60

    private var history: [ForecastChartPoint] {
        let lowerBound = now.addingTimeInterval(-Self.historyWindow)
        return forecast.samples.enumerated().compactMap { index, sample in
            guard sample.date >= lowerBound,
                  sample.date <= now,
                  sample.usedPercent.isFinite else {
                return nil
            }
            return ForecastChartPoint(
                id: "history-\(index)",
                date: sample.date,
                remainingPercent: remainingPercent(fromUsed: sample.usedPercent)
            )
        }
        .sorted { lhs, rhs in
            if lhs.date == rhs.date { return lhs.id < rhs.id }
            return lhs.date < rhs.date
        }
    }

    /// A projeção parte de `now`, mesmo que o último snapshot seja alguns minutos mais
    /// antigo: uma linha que começasse no último poll criaria uma continuidade visual
    /// enganosa entre dado real e estimativa.
    private var projection: [ForecastChartPoint] {
        guard let exhaustionAt = forecast.exhaustionAt, exhaustionAt > now else { return [] }
        return [
            ForecastChartPoint(id: "projection-now", date: now, remainingPercent: currentRemaining),
            ForecastChartPoint(id: "projection-exhaustion", date: exhaustionAt, remainingPercent: 0)
        ]
    }

    /// O ritmo seguro é a reta que chega a zero exatamente na renovação. Ela não depende
    /// de o ritmo observado já ter maturidade suficiente para gerar uma exaustão.
    private var safePace: [ForecastChartPoint] {
        guard let resetAt = forecast.resetAt, resetAt > now else { return [] }
        return [
            ForecastChartPoint(id: "safe-now", date: now, remainingPercent: currentRemaining),
            ForecastChartPoint(id: "safe-reset", date: resetAt, remainingPercent: 0)
        ]
    }

    /// 0 fica na base e 100 no topo por coordenada normal do gráfico; a escrita natural
    /// do domínio continua `0...100`, pois uma faixa invertida não é válida para Charts.
    private var dateDomain: ClosedRange<Date> {
        let lower = history.first?.date ?? now
        let farthestEvent = [forecast.exhaustionAt, forecast.resetAt]
            .compactMap { $0 }
            .filter { $0 > now }
            .max() ?? now
        let upper = max(farthestEvent, lower.addingTimeInterval(Self.minimumDomain))
        return lower...upper
    }

    private var currentRemaining: Double {
        remainingPercent(fromUsed: forecast.currentUsedPercent)
    }

    /// A projeção é uma estimativa de risco, não continuidade do histórico. A tinta vem
    /// da mesma escala semântica das cotas e acompanha as paradas editáveis do app.
    private var projectionColor: Color {
        QuotaPresentation.color(remaining: currentRemaining / 100)
    }

    private var seriesLabels: [String] {
        ForecastChartSeries.allCases.map(\.label)
    }

    var body: some View {
        Chart {
            ForEach(history) { point in
                LineMark(
                    x: .value(L("Tempo"), point.date),
                    y: .value(L("Restante"), point.remainingPercent),
                    series: .value(L("Série"), ForecastChartSeries.history.label)
                )
                .foregroundStyle(by: .value(L("Série"), ForecastChartSeries.history.label))
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                PointMark(
                    x: .value(L("Tempo"), point.date),
                    y: .value(L("Restante"), point.remainingPercent)
                )
                .foregroundStyle(by: .value(L("Série"), ForecastChartSeries.history.label))
                .symbolSize(18)
            }

            ForEach(projection) { point in
                LineMark(
                    x: .value(L("Tempo"), point.date),
                    y: .value(L("Restante"), point.remainingPercent),
                    series: .value(L("Série"), ForecastChartSeries.projection.label)
                )
                .foregroundStyle(by: .value(L("Série"), ForecastChartSeries.projection.label))
                .lineStyle(Self.dashedStroke)
            }

            ForEach(safePace) { point in
                LineMark(
                    x: .value(L("Tempo"), point.date),
                    y: .value(L("Restante"), point.remainingPercent),
                    series: .value(L("Série"), ForecastChartSeries.safePace.label)
                )
                .foregroundStyle(by: .value(L("Série"), ForecastChartSeries.safePace.label))
                .lineStyle(Self.dashedStroke)
            }
        }
        .chartForegroundStyleScale(
            domain: seriesLabels,
            range: [Theme.accent, projectionColor, providerColor]
        )
        .chartXScale(domain: dateDomain)
        .chartYScale(domain: 0...100)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                    .foregroundStyle(Theme.border())
                AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
        .chartYAxis {
            AxisMarks(values: [0.0, 50.0, 100.0]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                    .foregroundStyle(Theme.border())
                AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel {
                    if let percent = value.as(Double.self) {
                        Text("\(Int(percent))%")
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .chartPlotStyle { plotArea in
            plotArea.background(Theme.track())
        }
        .accessibilityLabel(L("Previsão de consumo"))
        .frame(height: 188)
    }

    private func remainingPercent(fromUsed usedPercent: Double) -> Double {
        guard usedPercent.isFinite else { return 0 }
        return 100 - min(max(usedPercent, 0), 100)
    }

    private static let dashedStroke = StrokeStyle(
        lineWidth: 1.5,
        lineCap: .round,
        lineJoin: .round,
        dash: [5, 4]
    )
}

private struct ForecastChartPoint: Identifiable {
    let id: String
    let date: Date
    let remainingPercent: Double
}

private enum ForecastChartSeries: CaseIterable {
    case history
    case projection
    case safePace

    var label: String {
        switch self {
        case .history: L("Histórico")
        case .projection: L("Projeção")
        case .safePace: L("Ritmo seguro")
        }
    }
}
