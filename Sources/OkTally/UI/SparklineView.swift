// Sources/OkTally/UI/SparklineView.swift
import SwiftUI
import Charts

/// Tendência de uso de um provedor (escala fixa 0–100%). Sem eixos nem rótulos: o número
/// grande acima já carrega o valor; isto só responde "subindo ou estável?".
///
/// Desde a revisão "usar o que o SwiftUI já tem", isto é **Swift Charts** — a mesma
/// biblioteca que o resto do app já usava em `DailyTokensAreaChart`,
/// `StackedProviderBarChart` e `ProviderShareDonut`. A versão anterior era um
/// `GeometryReader` com dois `Path` montados na mão (normalização, polilinha e polígono
/// de preenchimento): um gráfico de linha reimplementado ao lado de um framework de
/// gráficos que já estava importado no alvo. A interpolação suave e a animação entre
/// séries vêm de graça, e a curva ficou mais macia que a polilinha de segmentos retos.
struct SparklineView: View {
    /// Valores de percentual USADO (0…100) em ordem cronológica.
    let points: [Double]
    let color: Color
    /// Altura da faixa. Um gráfico sem eixos não tem altura intrínseca — alguém precisa
    /// propor uma — mas 20pt esmagavam a área preenchida a ponto de a curva virar um
    /// risco reto. Dentro do bloco-herói ela ganha mais espaço e volta a ter forma.
    var height: CGFloat = 20

    var body: some View {
        Chart(Array(points.enumerated()), id: \.offset) { index, value in
            AreaMark(
                x: .value(L("Amostra"), index),
                y: .value(L("Uso"), max(0, min(100, value)))
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(
                LinearGradient(colors: [color.opacity(0.28), color.opacity(0.02)],
                               startPoint: .top, endPoint: .bottom)
            )
            LineMark(
                x: .value(L("Amostra"), index),
                y: .value(L("Uso"), max(0, min(100, value)))
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(color.opacity(0.85))
            .lineStyle(StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
        }
        // Escala vertical FIXA 0–100: com o domínio automático do Swift Charts uma série
        // baixa e plana seria esticada até o topo e leria como "no limite". Cravar o
        // domínio é o que mantém "uso baixo e estável" com cara de uso baixo.
        .chartYScale(domain: 0...100)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartPlotStyle { $0.padding(.zero) }
        .frame(height: height)
    }
}
