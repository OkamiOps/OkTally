// Sources/OkTally/UI/DesignSystem/Components.swift
import SwiftUI

/// Card padrão: substitui as seis cópias do mesmo fundo+borda.
struct DashboardCard<Content: View>: View {
    var padding: CGFloat = Theme.Space.lg
    /// Mesma escotilha do `StatTile.fillsHeight`, e pelo mesmo motivo: um
    /// `.frame(maxHeight: .infinity)` aplicado por fora cresce o frame mas não o
    /// `.background`, que já foi desenhado no tamanho ideal — o card fica pequeno dentro
    /// de uma caixa grande. Grades e colunas de bento ligam isto para todos os cards de
    /// uma linha terminarem na mesma altura, ancorados no topo.
    var fillsHeight: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
            .cardSurface()
    }
}

extension View {
    /// Superfície de card: fundo um degrau acima da página + a borda interna sutil das
    /// referências. Fica como modificador (e não só dentro do `DashboardCard`) porque
    /// alguns blocos precisam do mesmo tratamento sem herdar o padding do card.
    func cardSurface(radius: CGFloat = Theme.Radius.medium) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(shape.fill(Theme.surface()))
            .overlay(shape.strokeBorder(Theme.border()))
    }

    /// Superfície do bloco de destaque: gradiente saturado de verdade. Só UM por tela —
    /// é o contraste com os cards neutros que faz o destaque existir.
    func heroSurface(_ color: Color, radius: CGFloat = Theme.Radius.medium) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(shape.fill(Theme.heroFill(color)))
            // Realce interno no topo: sem ele o gradiente encosta no fundo escuro sem
            // aresta e o bloco parece um borrão em vez de um objeto.
            .overlay(shape.strokeBorder(Color.white.opacity(0.18)))
    }
}

/// Chip de ícone colorido: quadrado arredondado pequeno com preenchimento SATURADO e
/// glifo em off-white. A versão antiga preenchia com `color.opacity(0.16)` e escrevia o
/// glifo na própria cor — no fundo quase preto isso vira um retângulo cinza com uma letra
/// apagada. Aqui a cor é a identidade do provedor, cheia, do tamanho de um selo.
struct IconChip: View {
    let glyph: String
    let color: Color
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
            .overlay(
                Text(glyph)
                    .font(.system(size: size * 0.52, weight: .heavy, design: .rounded))
                    // Off-white sobre chip escuro, charcoal sobre chip claro: alguns
                    // providers (Cursor grafite, MiMo âmbar) são claros demais para
                    // aguentar texto branco.
                    .foregroundStyle(color.isLight ? Theme.Brand.charcoal : Theme.onHero)
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16))
            )
    }
}

/// Métrica com hierarquia: `.hero` é o bloco de gradiente saturado, `.regular` orbita.
struct StatTile: View {
    enum Emphasis { case regular, hero }

    let title: String
    let value: String
    var caption: String?
    var tint: Color = Theme.accent
    var emphasis: Emphasis = .regular
    /// Faz o tile ocupar toda a altura oferecida, com o conteúdo ancorado no topo. É
    /// preciso ser opção interna: um `.frame(maxHeight: .infinity)` aplicado por fora
    /// cresce o frame mas não o `.background`, que já foi desenhado no tamanho ideal —
    /// o card fica pequeno dentro de uma caixa grande. Colunas de bento usam isto para
    /// terminar na mesma linha que o card vizinho.
    var fillsHeight: Bool = false

    private var isHero: Bool { emphasis == .hero }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title, onHero: isHero)
            Text(value)
                .font(isHero ? Theme.Font.metricHero : Theme.Font.metricLarge)
                .monospacedDigit()
                // No herói o número é off-white sobre a cor, não a cor sobre cinza: é a
                // superfície que carrega a identidade, e aí o número pode ser enorme sem
                // brigar com ela.
                .foregroundStyle(isHero ? Theme.onHero : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let caption {
                Text(caption)
                    .font(.system(size: 10))
                    .foregroundStyle(isHero ? Theme.onHero.opacity(0.72) : Color.secondary.opacity(0.8))
                    .lineLimit(1)
            }
        }
        .padding(Theme.Space.lg)
        .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
        .modifier(StatTileSurface(tint: tint, isHero: isHero))
    }
}

/// `if` dentro de `.background` faria o tipo do card mudar entre os dois ramos; um
/// modificador resolve sem `AnyView`.
private struct StatTileSurface: ViewModifier {
    let tint: Color
    let isHero: Bool

    func body(content: Content) -> some View {
        if isHero {
            content.heroSurface(tint)
        } else {
            content.cardSurface()
        }
    }
}

/// O rótulo maiúsculo com tracking, hoje repetido em quatro telas. Minúsculo e espaçado
/// de propósito: é o contraponto do número gigante.
struct SectionHeader: View {
    let text: String
    var onHero: Bool = false
    init(_ text: String, onHero: Bool = false) {
        self.text = text
        self.onHero = onHero
    }

    var body: some View {
        Text(text.uppercased())
            .font(Theme.Font.label)
            .tracking(Theme.labelTracking)
            .foregroundStyle(onHero ? AnyShapeStyle(Theme.onHero.opacity(0.85)) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
    }
}

/// Variação percentual. `nil` (sem base de comparação) some em vez de mostrar "+∞".
struct DeltaBadge: View {
    let fraction: Double?
    /// Sobre o gradiente do herói a cápsula precisa ser off-white translúcido: ciano
    /// sobre ciano some.
    var onHero: Bool = false

    var body: some View {
        if let fraction {
            let up = fraction >= 0
            let tint: Color = onHero
                ? Theme.onHero
                : (abs(fraction) < 0.005 ? .secondary : (up ? Theme.accent : Theme.Brand.neonMagenta))
            Label(
                String(format: "%@%.0f%%", up ? "+" : "−", abs(fraction) * 100),
                systemImage: up ? "arrow.up.right" : "arrow.down.right"
            )
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(onHero ? 0.22 : 0.16)))
        }
    }
}

/// Fatia de participação de um provider.
struct ShareBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track())
                Capsule()
                    .fill(color.gradient)
                    .frame(width: max(3, geo.size.width * Theme.clampFraction(fraction)))
            }
        }
        .frame(height: 6)
    }
}

/// Anel de capacidade. Desde a revisão "usar o que o SwiftUI já tem", isto é um `Gauge`
/// NATIVO com `.accessoryCircularCapacity` — não mais dois `Circle()` com `.trim()`
/// desenhados à mão. O nativo traz de graça a animação entre valores, o traço na
/// espessura do sistema e a rotulagem de acessibilidade (o desenho antigo era um
/// `Text` mudo dentro de um `ZStack`).
///
/// A troca foi decidida por imagem, não por princípio: renderizado lado a lado com o anel
/// antigo, o `Gauge` sai com traço mais grosso e trilho na própria cor rebaixada, que é
/// exatamente a leitura das referências — e, ao contrário dos estilos LINEARES do
/// `Gauge`, o circular respeita `.tint()` e sobrevive ao `ImageRenderer`. Ver o relatório
/// `.superpowers/popover-native-pass.md` para os dois PNGs de sonda.
struct ProgressRing: View {
    let fraction: Double
    let color: Color
    var size: CGFloat = 44
    var label: String?

    var body: some View {
        Gauge(value: Theme.clampFraction(fraction)) {
            Text(L("Progresso"))
        } currentValueLabel: {
            if let label {
                Text(label)
                    .font(.system(size: size * 0.30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(color)
        .labelsHidden()
        .frame(width: size, height: size)
    }
}

/// O símbolo da marca desenhado em SwiftUI: três traços de contagem (tally) cortados por
/// uma diagonal nas três cores de acento. Não usa `Resources/Brand/*.png` porque esses
/// arquivos não estão no bundle do target e incluí-los exigiria mexer no `Package.swift`
/// — e, de qualquer forma, um vetor de 16pt desenhado direto fica nítido em qualquer
/// escala e acompanha o esquema de cor sozinho.
///
/// Fica no header do popover: é a tela que o dono abre dez vezes por dia e a única que
/// não tinha nenhum sinal de identidade além do texto "OkTally".
struct BrandMark: View {
    var size: CGFloat = 16

    var body: some View {
        let barWidth = size * 0.17
        ZStack {
            HStack(spacing: size * 0.16) {
                ForEach(0..<3, id: \.self) { _ in
                    Capsule().fill(.primary).frame(width: barWidth)
                }
            }
            // A diagonal do símbolo, com o gradiente das três cores de acento — é ela que
            // transforma "três barras" no logo.
            Capsule()
                .fill(LinearGradient(
                    colors: [Theme.Brand.voltCyan, Theme.Brand.heatOrange, Theme.Brand.neonMagenta],
                    startPoint: .top, endPoint: .bottom))
                .frame(width: barWidth * 1.15, height: size * 1.34)
                .rotationEffect(.degrees(-52))
        }
        .frame(width: size * 0.83, height: size)
        .accessibilityHidden(true)
    }
}
