// Sources/OkTally/UI/Notch/NotchIslandGeometry.swift
import CoreGraphics

/// Onde a janela da ilha nasce na tela — e nada além disso.
///
/// ## Por que isto é um arquivo separado, sem `AppKit`
///
/// Posicionamento absoluto de janela é a única parte do painel que NENHUM PNG revela: o
/// harness de imagem desenha o conteúdo, não a tela. Mas a conta é aritmética pura — dado
/// o retângulo da tela, o tamanho da pílula e a fração salva, sai uma origem —, então ela
/// sai daqui inteira e é testada de verdade, em vez de ser conferida no olho a cada build.
///
/// ## As três regras que esta conta existe para garantir
///
/// 1. **O topo é a borda de cima da TELA, não da área útil.** `visibleFrame` desconta a
///    barra de menu; usar ele pendurava a pílula ABAIXO da barra, no meio do conteúdo das
///    janelas. A região central da barra de menu é vazia, e é exatamente ali que um notch
///    simulado tem de morar — por isso a conta parte de `frame.maxY`.
/// 2. **O topo é ÂNCORA, não resultado.** A origem de uma janela no macOS é o canto
///    INFERIOR esquerdo, então crescer para baixo significa a origem descer junto com a
///    altura. Quem calcula "origem = topo − altura" a cada estado mantém a borda de cima
///    parada; quem centraliza pela altura faz a pílula pular ao expandir.
/// 3. **A fração sobrevive à tela.** A posição horizontal é guardada como fração de 0 a 1
///    da largura, e não em pontos: trocar a resolução (ou o monitor) reposiciona a pílula
///    proporcionalmente em vez de jogá-la para fora da tela.
enum NotchIslandGeometry {
    /// O centro da tela, que é onde a pílula nasce antes de o dono mexer nela.
    static let centerFraction: CGFloat = 0.5

    /// Quão perto do centro o arrasto precisa terminar para a pílula grudar nele.
    ///
    /// Existe porque acertar o centro exato arrastando é impossível, e uma pílula 3pt
    /// fora do centro lê como erro do app, não como escolha do dono.
    static let centerSnapTolerance: CGFloat = 28

    /// Distância mínima antes de um clique virar arrasto. Sem ela, o tremor da mão entre
    /// apertar e soltar mataria o clique que abre o popover.
    static let dragThreshold: CGFloat = 4

    /// Fração válida: 0…1, com o centro como rede para lixo (`NaN`, valor de uma versão
    /// antiga, arquivo de preferências editado à mão).
    static func clampFraction(_ fraction: CGFloat) -> CGFloat {
        guard fraction.isFinite else { return centerFraction }
        return min(max(fraction, 0), 1)
    }

    /// O frame da JANELA da ilha (não o da pílula: a janela é maior, porque a sombra
    /// precisa de respiro em volta para não sair cortada em quadrado).
    ///
    /// - Parameters:
    ///   - screenFrame: `NSScreen.frame` — o retângulo INTEIRO, barra de menu incluída.
    ///   - pillSize: o tamanho medido do desenho da pílula no estado atual.
    ///   - horizontalMargin: respiro da sombra de cada lado.
    ///   - bottomMargin: respiro da sombra embaixo. Em cima não há respiro nenhum: é lá
    ///     que a pílula encosta na borda da tela, e sombra para cima não existiria de
    ///     qualquer forma.
    ///   - fraction: onde o CENTRO da pílula deve ficar ao longo da largura da tela.
    static func windowFrame(
        screenFrame: CGRect,
        pillSize: CGSize,
        horizontalMargin: CGFloat,
        bottomMargin: CGFloat,
        fraction: CGFloat
    ) -> CGRect {
        let size = CGSize(
            width: pillSize.width + horizontalMargin * 2,
            height: pillSize.height + bottomMargin
        )
        let center = clampedCenterX(screenFrame: screenFrame, pillWidth: pillSize.width, fraction: fraction)
        return CGRect(
            x: center - size.width / 2,
            // A borda de CIMA da janela encosta no topo da tela; a origem é o que sobra
            // depois de descontar a altura. É esta linha que faz o expandir crescer só
            // para baixo.
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// Onde o centro da pílula pode de fato ficar: a fração pedida, contida para a pílula
    /// não sair pela borda.
    ///
    /// Quando a pílula é mais larga que a tela (expandida numa tela estreita) não há
    /// posição que a contenha, e aí o centro da tela é o menos ruim — sobra igual dos dois
    /// lados em vez de tudo de um lado só.
    static func clampedCenterX(screenFrame: CGRect, pillWidth: CGFloat, fraction: CGFloat) -> CGFloat {
        let half = pillWidth / 2
        guard screenFrame.width > pillWidth else { return screenFrame.midX }
        let desired = screenFrame.minX + clampFraction(fraction) * screenFrame.width
        return min(max(desired, screenFrame.minX + half), screenFrame.maxX - half)
    }

    /// O caminho inverso: o dono soltou a pílula com o centro aqui — que fração é essa?
    static func fraction(forCenterX centerX: CGFloat, screenFrame: CGRect) -> CGFloat {
        guard screenFrame.width > 0 else { return centerFraction }
        return clampFraction((centerX - screenFrame.minX) / screenFrame.width)
    }

    /// A fração depois do ímã do centro: perto o bastante, vira centro exato.
    ///
    /// A tolerância é medida em PONTOS de tela (não em fração) de propósito — o que o
    /// dono percebe como "quase no meio" é uma distância na tela, e num monitor largo a
    /// mesma fração vale muito mais pixels.
    static func snappedFraction(
        _ fraction: CGFloat,
        screenFrame: CGRect,
        tolerance: CGFloat = centerSnapTolerance
    ) -> CGFloat {
        let clamped = clampFraction(fraction)
        let centerX = screenFrame.minX + clamped * screenFrame.width
        return abs(centerX - screenFrame.midX) <= tolerance ? centerFraction : clamped
    }
}
