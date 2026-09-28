// Sources/OkTally/UI/DesignSystem/ChartTooltip.swift
import SwiftUI

/// Uma linha de detalhamento do tooltip: ponto na cor de identidade, nome, valor e fatia.
struct ChartTooltipRow: Identifiable {
    let id: String
    let color: Color
    let name: String
    let value: String
    /// Fatia do total daquele ponto. `nil` esconde a coluna (tooltips de série única).
    var percent: String?
}

/// O cartão de detalhe que TODOS os gráficos da aba Análise usam. Um só componente
/// porque a alternativa já foi tentada em outros apps e sempre termina igual: cada gráfico
/// inventa um balão com padding, fonte e fundo um pouco diferentes, e a tela passa a ter
/// cinco tooltips que não parecem do mesmo produto.
///
/// Superfície opaca de propósito (`Theme.surface()`, não material translúcido): o cartão
/// pousa EM CIMA de barras e áreas saturadas, e qualquer transparência transforma o número
/// que ele existe para mostrar em algo ilegível.
struct ChartTooltip: View {
    /// Linha de cima — normalmente a data ("Qua, 15 abr").
    let title: String
    /// O número que o olho procura primeiro.
    var value: String?
    /// Contexto do valor: número exato, comparação com o dia anterior, quartil.
    var caption: String?
    /// Fração para o `DeltaBadge` ao lado do título. `nil` some (sem base de comparação).
    var delta: Double?
    var rows: [ChartTooltipRow] = []

    /// Teto de linhas. Com dez provedores conectados o cartão viraria uma coluna mais alta
    /// que o próprio gráfico; as excedentes são somadas numa linha "outros".
    static let maxRows = 6

    private var visibleRows: [ChartTooltipRow] { Array(rows.prefix(Self.maxRows)) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(spacing: Theme.Space.sm) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                if let delta {
                    DeltaBadge(fraction: delta)
                }
            }
            if let value {
                Text(value)
                    .font(Theme.Font.metricMedium)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            if let caption {
                Text(caption)
                    .font(.system(size: 9))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            if !visibleRows.isEmpty {
                Divider().opacity(0.4)
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(visibleRows) { row in
                        HStack(spacing: Theme.Space.sm) {
                            Circle().fill(row.color).frame(width: 7, height: 7)
                            Text(row.name)
                                .font(.system(size: 10))
                                .lineLimit(1)
                            Spacer(minLength: Theme.Space.md)
                            Text(row.value)
                                .font(.system(size: 10, weight: .semibold))
                                .monospacedDigit()
                            if let percent = row.percent {
                                Text(percent)
                                    .font(.system(size: 9))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 30, alignment: .trailing)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.sm)
        .background(Self.shape.fill(Theme.surface()))
        .overlay(Self.shape.strokeBorder(Theme.border()))
        // Sombra é o que separa o cartão do gráfico atrás dele: sem ela a borda sutil
        // desaparece contra uma barra da mesma luminosidade e o cartão "cola" no dado.
        .shadow(color: .black.opacity(0.35), radius: 9, x: 0, y: 3)
        .fixedSize()
    }

    private static var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
    }
}

/// Coloca um tooltip ao lado do cursor sem deixá-lo vazar do gráfico.
///
/// A medição do cartão vem depois do primeiro layout (`onGeometryChange`), então o
/// grampeamento só pode acontecer com o tamanho em mão — é por isso que isto é uma view
/// com estado e não um `offset` calculado no call site.
struct ChartTooltipLayer<Tip: View>: View {
    /// Posição do cursor no mesmo espaço de `bounds`. `nil` esconde o cartão.
    let anchor: CGPoint?
    /// Área em que o cartão precisa caber inteiro.
    let bounds: CGRect
    var gap: CGFloat = 12
    @ViewBuilder var tip: Tip

    @State private var size: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let anchor {
                let origin = ChartHover.tooltipOrigin(
                    anchor: anchor, tooltipSize: size, bounds: bounds, gap: gap)
                tip
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
                    .offset(x: origin.x, y: origin.y)
                    // O cartão é leitura, não alvo: se capturasse hover, entrar nele
                    // encerraria o hover do gráfico e o cartão piscaria sem parar.
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(Theme.hoverTransition, value: anchor)
    }
}

/// A régua vertical que ancora a leitura no dia sob o cursor, com o ponto sobre a curva.
/// Sem ela o cartão informa um valor sem dizer de onde ele veio.
struct ChartHoverRule: View {
    /// X da régua, no espaço do gráfico.
    let x: CGFloat
    /// Faixa vertical que a régua percorre.
    let top: CGFloat
    let bottom: CGFloat
    /// Y do ponto sobre a curva. `nil` desenha só a régua (gráficos de barra).
    var markerY: CGFloat?
    let color: Color

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(color.opacity(0.55))
                .frame(width: 1, height: max(0, bottom - top))
                .offset(x: x - 0.5, y: top)
            if let markerY {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                    // Halo na cor da superfície: sobre a área preenchida o ponto cheio
                    // some dentro do próprio gradiente.
                    .overlay(Circle().strokeBorder(Theme.surface(), lineWidth: 1.5))
                    .offset(x: x - 3.5, y: markerY - 3.5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

extension Theme {
    /// A curva de TODA transição de hover do app. Fica num token porque o dono é
    /// sensível a movimento: 0,18s em `easeInOut` some do caminho, enquanto durações
    /// diferentes por gráfico fazem a tela parecer ter cinco velocidades.
    static let hoverTransition: Animation = .easeInOut(duration: 0.18)

    /// Opacidade de um elemento REBAIXADO por outro estar em foco. Escurecer o resto em
    /// vez de acender o escolhido: acender mudaria a cor de identidade, que aqui carrega
    /// significado.
    static let dimmedOpacity: Double = 0.28
}
