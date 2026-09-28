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
    /// Datas das amostras, quando quem chama as tem. Sem elas o rótulo de hover mostra só
    /// o percentual — um índice de amostra ("3") não significa nada para quem lê.
    var dates: [Date] = []
    /// Liga a régua e o rótulo de hover. Fica desligado por padrão: em faixas de 20pt
    /// espalhadas pelo popover, um rótulo por sparkline seria ruído.
    var hover: Bool = false

    @State private var hoveredIndex: Int?

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
        .chartOverlay { proxy in
            if hover { overlay(proxy: proxy) }
        }
        .frame(height: height)
    }

    /// Régua, ponto e um rótulo MÍNIMO ao lado. Uma faixa de 20–30pt não tem altura para o
    /// `ChartTooltip`: grampeado ali dentro, o cartão cobriria a curva inteira. Aqui o
    /// valor vira uma cápsula rasa que cabe na própria faixa.
    private func overlay(proxy: ChartProxy) -> some View {
        GeometryReader { geo in
            let plot = proxy.plotFrame.map { geo[$0] } ?? .zero
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover(coordinateSpace: .local) { phase in
                        switch phase {
                        case .active(let location):
                            guard !points.isEmpty,
                                  let raw = proxy.value(atX: location.x - plot.minX, as: Double.self)
                            else { return }
                            let index = max(0, min(points.count - 1, Int(raw.rounded())))
                            if index != hoveredIndex { hoveredIndex = index }
                        case .ended:
                            hoveredIndex = nil
                        }
                    }
                if let index = hoveredIndex, points.indices.contains(index) {
                    let value = max(0, min(100, points[index]))
                    let x = plot.minX + (proxy.position(forX: index) ?? 0)
                    let y = plot.minY + (proxy.position(forY: value) ?? 0)
                    ChartHoverRule(x: x, top: plot.minY, bottom: plot.maxY, markerY: y, color: color)
                    label(index: index, value: value, x: x, plot: plot)
                }
            }
            .animation(Theme.hoverTransition, value: hoveredIndex)
        }
    }

    private func label(index: Int, value: Double, x: CGFloat, plot: CGRect) -> some View {
        let text = dates.indices.contains(index)
            ? "\(ChartHover.dayLabel(dates[index])) · \(ChartHover.percentLabel(value / 100))"
            : ChartHover.percentLabel(value / 100)
        return Text(text)
            .font(.system(size: 9, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(Theme.surface()))
            .overlay(Capsule().strokeBorder(Theme.border()))
            .fixedSize()
            // Mesmo grampeamento dos cartões grandes, só com folga menor: perto da borda
            // direita a cápsula vira para o outro lado do cursor em vez de vazar.
            .modifier(SparklineLabelPlacement(x: x, plot: plot))
            .allowsHitTesting(false)
    }
}

/// O grampeamento da cápsula de hover da sparkline. É um `ViewModifier` porque a posição
/// só pode ser calculada depois de medir o texto, e medir exige estado.
private struct SparklineLabelPlacement: ViewModifier {
    let x: CGFloat
    let plot: CGRect

    @State private var size: CGSize = .zero

    func body(content: Content) -> some View {
        let origin = ChartHover.tooltipOrigin(
            anchor: CGPoint(x: x, y: plot.minY),
            tooltipSize: size,
            bounds: plot,
            gap: 6
        )
        return content
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .offset(x: origin.x, y: plot.minY)
    }
}
