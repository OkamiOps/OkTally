// Sources/OkTally/UI/Charts/ProviderShareDonut.swift
import SwiftUI
import Charts

/// Participação de cada provider no período — a leitura instantânea de quem consome o quê.
struct ProviderShareDonut: View {
    let share: [(providerId: String, tokens: Int)]
    /// Nome exibido do provider. O miolo passa a escrever o nome de quem está sob o cursor,
    /// e "codex" cru no meio do anel não é o nome de nada.
    var providerName: (String) -> String = { $0 }

    @Environment(\.chartHoverPreview) private var hoverPreview

    /// `chartAngleSelection` entrega a posição ACUMULADA sob o cursor, não a fatia —
    /// `ChartHover.sliceIndex` faz a tradução.
    @State private var selectedAngle: Int?

    private var total: Int { share.reduce(0) { $0 + $1.tokens } }

    private var selectedIndex: Int? {
        if let selectedAngle {
            return ChartHover.sliceIndex(forAngleValue: selectedAngle, in: share.map(\.tokens))
        }
        guard let previewId = hoverPreview?.providerId else { return nil }
        return share.firstIndex { $0.providerId == previewId }
    }

    var body: some View {
        Chart(Array(share.enumerated()), id: \.element.providerId) { index, slice in
            let isSelected = index == selectedIndex
            SectorMark(
                angle: .value(L("Tokens"), slice.tokens),
                innerRadius: .ratio(0.62),
                // A fatia em foco CRESCE para fora. O anel tem raio externo de 92% por
                // padrão só para sobrar essa folga: sem ela o crescimento seria cortado
                // pela moldura do gráfico em vez de aparecer.
                outerRadius: .ratio(isSelected ? 1.0 : 0.92),
                angularInset: 1.5
            )
            .cornerRadius(3)
            .foregroundStyle(ProviderPalette.color(for: slice.providerId))
            // Mesma regra do empilhado: rebaixa o resto, nunca altera a cor do escolhido.
            .opacity(selectedIndex == nil || isSelected ? 1 : Theme.dimmedOpacity)
        }
        .chartAngleSelection(value: $selectedAngle)
        .chartLegend(.hidden)
        .animation(Theme.hoverTransition, value: selectedIndex)
        .overlay {
            if let index = selectedIndex, share.indices.contains(index) {
                center(
                    value: TokenAnalytics.compactTokens(share[index].tokens),
                    caption: providerName(share[index].providerId),
                    detail: total > 0
                        ? ChartHover.percentLabel(Double(share[index].tokens) / Double(total))
                        : nil,
                    tint: ProviderPalette.color(for: share[index].providerId)
                )
            } else {
                center(value: TokenAnalytics.compactTokens(total), caption: L("total"))
            }
        }
    }

    /// O miolo do anel. Mesma composição nos dois estados — valor grande, rótulo pequeno —
    /// para a troca ser uma mudança de CONTEÚDO e não um salto de layout.
    private func center(value: String, caption: String, detail: String? = nil, tint: Color? = nil) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(Theme.Font.metricMedium)
                .monospacedDigit()
                .foregroundStyle(tint ?? .primary)
            Text(caption)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let detail {
                Text(detail)
                    .font(.system(size: 9, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
        // O miolo tem o diâmetro do furo (62% do raio): sem esse teto um nome comprido
        // escreve por cima do anel.
        .frame(maxWidth: 84)
        .animation(Theme.hoverTransition, value: caption)
    }
}
