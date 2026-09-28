// Sources/OkTally/UI/DesignSystem/StaticRender.swift
import SwiftUI

/// Sinaliza que a árvore está sendo desenhada por `ImageRenderer` (os PNGs de
/// `docs/assets`), e não numa janela viva. Controles do AppKit não têm representação
/// nesse caminho — `Picker(.segmented)`, por exemplo, sai como um retângulo amarelo com
/// o símbolo de proibido. Quem depende de um controle desses desenha um substituto
/// estático quando a flag está ligada.
///
/// Só o harness de render liga isto. O app nunca liga, então o usuário continua com o
/// controle nativo: semântica de seleção para o VoiceOver, navegação por setas dentro do
/// grupo e o estilo do sistema.
private struct StaticRenderKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isStaticRender: Bool {
        get { self[StaticRenderKey.self] }
        set { self[StaticRenderKey.self] = newValue }
    }
}

/// Seleção de hover FORÇADA, pela mesma razão do `isStaticRender`: `onContinuousHover` e
/// `chartAngleSelection` dependem de um cursor de verdade, e num render offscreen não
/// existe cursor nenhum — os tooltips simplesmente não apareceriam no PNG, e o estado
/// mais fácil de estragar (cartão cortado pela borda do card) seria justamente o que
/// nenhuma imagem mostraria.
///
/// Só o harness de render preenche isto. No app o valor é `nil` e cada gráfico responde
/// exclusivamente ao cursor.
struct ChartHoverPreview: Equatable {
    /// Dia "yyyy-MM-dd" a destacar nos gráficos com eixo de tempo e no heatmap.
    var day: String?
    /// Provedor a destacar no donut de participação.
    var providerId: String?
}

private struct ChartHoverPreviewKey: EnvironmentKey {
    static let defaultValue: ChartHoverPreview? = nil
}

extension EnvironmentValues {
    var chartHoverPreview: ChartHoverPreview? {
        get { self[ChartHoverPreviewKey.self] }
        set { self[ChartHoverPreviewKey.self] = newValue }
    }
}
