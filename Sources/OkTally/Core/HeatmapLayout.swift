// Sources/OkTally/Core/HeatmapLayout.swift
import CoreGraphics

/// Célula e número de semanas que preenchem a largura disponível.
struct HeatmapMetrics: Equatable {
    let cell: CGFloat
    let weeks: Int
}

/// O heatmap antigo tinha célula fixa de 10 pt e 26 semanas: numa janela larga sobrava
/// metade do card vazia. Aqui a largura manda — primeiro tenta caber o máximo de semanas
/// com célula legível, depois ajusta a célula para consumir o resto.
enum HeatmapLayout {
    static func metrics(
        availableWidth: CGFloat,
        gap: CGFloat = 2,
        minCell: CGFloat = 8,
        maxCell: CGFloat = 16,
        maxWeeks: Int = 53
    ) -> HeatmapMetrics {
        // `availableWidth` chega crua de quem chama (os `Layout`s do heatmap repassam
        // `proposal.width` direto) e um `ProposedViewSize.width` pode legitimamente ser
        // `.infinity` — é assim que SwiftUI pede "tamanho ideal" em medições de
        // ScrollView/List/Form, `.fixedSize()` e negociação de coluna de
        // NavigationSplitView. `Int(CGFloat.infinity)` (usado abaixo) trapa (fatal error),
        // então qualquer largura não finita (`.infinity` ou `.nan`) cai no mesmo fallback
        // degenerado já usado para largura negativa/zero — 1 semana, célula mínima — em
        // vez de tentar adivinhar um "tamanho ideal" que enganaria a negociação de tamanho
        // do container pai.
        let width = availableWidth.isFinite ? max(0, availableWidth) : 0
        // Quantas colunas cabem com a célula no menor tamanho legível.
        let widest = Int(((width + gap) / (minCell + gap)).rounded(.down))
        let weeks = max(1, min(maxWeeks, widest))
        // Com o número de colunas fixo, a célula cresce para consumir a sobra.
        let raw = (width - gap * CGFloat(weeks - 1)) / CGFloat(weeks)
        let cell = min(maxCell, max(minCell, raw))
        return HeatmapMetrics(cell: cell, weeks: weeks)
    }
}
