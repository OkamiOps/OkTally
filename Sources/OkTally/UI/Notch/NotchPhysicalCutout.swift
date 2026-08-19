// Sources/OkTally/UI/Notch/NotchPhysicalCutout.swift
import CoreGraphics

/// Quanto o recorte físico REALMENTE desce — que não é o que o macOS declara.
///
/// ## A mentira do `safeAreaInsets.top`
///
/// O furo da câmera tem altura fixa em pixels do painel. No modo padrão (metade das
/// linhas nativas, @2x) ele mede 38pt e o macOS conta a verdade: barra de menu, safe area
/// e furo coincidem. Em resolução ESCALADA ("mais espaço") o mesmo furo passa a valer
/// mais pontos — na tela do dono (1330 linhas lógicas num painel de 1964) ele ocupa
/// 38 × 1330 ÷ 982 ≈ 51,5pt — mas o macOS reporta `safeAreaInsets.top = 43` e deixa o
/// hardware invadir ~8,5pt do conteúdo abaixo da barra de menu.
///
/// Foi assim que a primeira prateleira (8pt, calculada sobre os 43 declarados) falhou no
/// olho do dono depois de passar no screenshot: o framebuffer TEM os pixels da barra —
/// `screencapture` mostra a barra contínua —, o painel de LED é que não tem onde
/// mostrá-los. A conta daqui existe para pôr a barra abaixo do furo VERDADEIRO.
///
/// Pura e sem AppKit de propósito (mesma razão de `NotchIslandGeometry`): quem descobre
/// as linhas nativas do painel é o controller, via CoreGraphics; aqui só mora a
/// aritmética, testável de verdade.
enum NotchPhysicalCutout {
    /// Altura do recorte, em pontos, no MODO PADRÃO (lógica = nativa ÷ 2). Vale 38 nos
    /// MacBook Pro 14"/16" com notch; painéis futuros com outro valor erram pouco e a
    /// `clearance` absorve.
    static let defaultModeHeight: CGFloat = 38

    /// Folga entre o fundo do furo estimado e o TOPO da barra. Cobre o erro do modelo
    /// (±2pt se o furo nativo não for exatamente 76 linhas) e o antialiasing da borda.
    static let clearance: CGFloat = 4

    /// A altura física do recorte no modo ATUAL da tela.
    ///
    /// - Parameters:
    ///   - logicalScreenHeight: `NSScreen.frame.height` — linhas lógicas do modo atual.
    ///   - nativePanelRows: linhas de PIXEL do painel (1964 no 14"); `nil` quando a
    ///     enumeração de modos não encontrar o modo nativo — e aí a resposta honesta é
    ///     a declarada (`safeTop`), não um chute.
    ///   - safeTop: o que o macOS declara (`safeAreaInsets.top`).
    static func height(
        logicalScreenHeight: CGFloat,
        nativePanelRows: CGFloat?,
        safeTop: CGFloat
    ) -> CGFloat {
        guard let nativePanelRows, nativePanelRows > 0, logicalScreenHeight > 0 else { return safeTop }
        let physical = defaultModeHeight * logicalScreenHeight / (nativePanelRows / 2)
        // O furo nunca é MENOR que a área que o sistema já reserva — se a conta der
        // menos, é o modelo errando (painel desconhecido), e o declarado é o piso.
        return max(physical, safeTop)
    }

    /// A prateleira que o painel compacto precisa descer abaixo do `safeTop` para a
    /// barra inteira (traço + respiro da borda) ficar abaixo do furo físico.
    ///
    /// `overlap` é o quanto o hardware invade além do declarado; o resto é a anatomia da
    /// barra (`bottomGap` + `thickness`) mais a folga do modelo. No modo padrão
    /// (overlap 0) sai ~10pt; na tela escalada do dono, ~18pt.
    static func shelf(physicalHeight: CGFloat, safeTop: CGFloat) -> CGFloat {
        let overlap = max(0, physicalHeight - safeTop)
        return (overlap + NotchBottomRule.bottomGap + NotchBottomRule.thickness + clearance).rounded(.up)
    }
}
