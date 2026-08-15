// Sources/OkTally/UI/DesignSystem/Theme.swift
import SwiftUI
import AppKit

/// Tokens visuais do app. Antes disto, `RoundedRectangle(cornerRadius: 12)
/// .fill(Color.primary.opacity(0.045))` estava copiado em seis lugares — mudar a
/// estética exigia editar todos.
///
/// A partir da revisão de identidade, as superfícies deixaram de ser derivadas de
/// `Color.primary` (cinza do sistema) e passaram a sair da paleta oficial da marca
/// (`Resources/Brand`). O motivo é simples: o app era julgado em tema claro e desenhado
/// com cor de sistema, então nunca teve identidade nenhuma. As referências do dono são
/// dashboards escuros — base quase preta, card um degrau mais claro, borda interna
/// sutil, e UM bloco com gradiente saturado no meio de blocos neutros.
enum Theme {

    // MARK: - Paleta da marca

    /// As cinco cores oficiais, exatamente como no README do pacote de marca.
    enum Brand {
        /// `#1B1D20` — cinza-carvão. Base das superfícies escuras.
        static let charcoal = Color(hex: 0x1B1D20)
        /// `#F7F5F0` — branco-quebrado. Texto sobre escuro e base do tema claro.
        static let offWhite = Color(hex: 0xF7F5F0)
        /// `#00B8F5` — ciano elétrico. Acento primário do app.
        static let voltCyan = Color(hex: 0x00B8F5)
        /// `#FF007F` — magenta neon. Realce e topo da escala de perigo.
        static let neonMagenta = Color(hex: 0xFF007F)
        /// `#FF9D00` — laranja quente. Degrau intermediário da escala de perigo.
        static let heatOrange = Color(hex: 0xFF9D00)
    }

    /// Acento do app. Existe como token para nenhuma tela precisar escrever
    /// `.accentColor` (que é a cor do *sistema*, escolhida pelo usuário nas Preferências
    /// do macOS — ou seja: qualquer coisa menos a nossa marca).
    static let accent = Brand.voltCyan

    // MARK: - Espaço e forma

    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    /// Raios generosos, como nas referências (16–20pt). Os 12pt antigos deixavam os
    /// cards com cara de caixa de diálogo, não de widget.
    enum Radius {
        static let small: CGFloat = 10
        static let medium: CGFloat = 16
        static let large: CGFloat = 20
    }

    enum Font {
        /// Número dominante da tela. 38pt: as referências usam 32–40 contra rótulos
        /// minúsculos, e é esse contraste de tamanho que cria hierarquia — não a cor.
        static let metricHero = SwiftUI.Font.system(size: 38, weight: .bold, design: .rounded)
        static let metricLarge = SwiftUI.Font.system(size: 24, weight: .bold, design: .rounded)
        static let metricMedium = SwiftUI.Font.system(size: 15, weight: .semibold, design: .rounded)
        static let body = SwiftUI.Font.system(size: 12)
        static let label = SwiftUI.Font.system(size: 9, weight: .semibold)
    }

    /// Tracking do rótulo em caixa alta. Fica no token porque o par
    /// "minúsculo + espaçado" é metade da identidade das referências.
    static let labelTracking: CGFloat = 0.9

    // MARK: - Superfícies

    /// Fundo da página: quase preto no escuro (um degrau ABAIXO do charcoal, para o card
    /// em charcoal aparecer como um degrau acima), off-white no claro.
    static let pageBackground = ThemeColor(light: Color(hex: 0xF1EFEA), dark: Color(hex: 0x0C0D0F))

    /// Card padrão: um degrau mais claro que a página.
    static func surface() -> ThemeColor { ThemeColor(light: .white, dark: Color(hex: 0x1B1D20)) }

    /// Elemento elevado sobre um card (segmentado selecionado, trilho de barra).
    static func surfaceRaised() -> ThemeColor { ThemeColor(light: Color(hex: 0xE7E4DD), dark: Color(hex: 0x272A2F)) }

    /// Borda interna sutil — branco a ~7% no escuro; no claro precisa ser escura para
    /// existir. É a linha fina que separa o card do fundo sem virar moldura.
    static func border() -> ThemeColor {
        ThemeColor(light: Color.black.opacity(0.08), dark: Color.white.opacity(0.07))
    }

    /// Trilho vazio de barras e anéis. Não usa `Color.primary.opacity(0.08)` porque no
    /// escuro isso é branco puro translúcido, que "brilha" mais do que o preenchimento
    /// dessaturado de alguns providers.
    static func track() -> ThemeColor {
        ThemeColor(light: Color.black.opacity(0.09), dark: Color.white.opacity(0.09))
    }

    /// Grampeia uma fração em 0…1 tratando `NaN`/infinito como zero. Existe porque em
    /// Swift `max(0, min(1, .nan))` devolve `1.0` — qualquer divisão por zero que escape
    /// de um call site desenharia a barra ou o anel CHEIOS, que é a leitura oposta da
    /// verdadeira. A guarda mora no componente, não só no aviso do ledger.
    static func clampFraction(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return max(0, min(1, value))
    }

    // MARK: - Destaque

    /// Gradiente saturado DE VERDADE, para o único bloco de destaque de cada tela. É o
    /// "pop" das referências: um card com cor cheia no meio de cards neutros. A versão
    /// antiga (`color.opacity(0.18) → 0.05`) era um tingimento tão fraco que sumia contra
    /// o fundo — o dono viu um dashboard cinza com números coloridos, não um destaque.
    static func heroFill(_ color: Color) -> LinearGradient {
        LinearGradient(
            colors: [color.heroTop, color.heroBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Tingimento leve, para blocos que acompanham o herói sem competir com ele.
    static func surfaceAccent(_ color: Color) -> LinearGradient {
        LinearGradient(
            colors: [color.opacity(0.20), color.opacity(0.06)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Texto sobre o gradiente do herói. Off-white da marca, não `.white` puro: o branco
    /// puro sobre magenta/ciano saturado vibra.
    static let onHero = Brand.offWhite
}

// MARK: - Cores dinâmicas

extension Color {
    /// Cor fixa a partir de um hex `0xRRGGBB`.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    /// Topo do gradiente do herói: a própria cor, um pouco mais viva.
    var heroTop: Color { shifted(hue: 0, saturation: 1.02, brightness: 1.10) }

    /// Base do gradiente do herói: MESMA cor com o matiz girado para o lado
    /// magenta/violeta e escurecida. Duas paradas de matizes diferentes, não uma cor
    /// misturada com cinza — a primeira tentativa fundia 34% de charcoal na base e o
    /// laranja saía ocre, cor de tijolo, exatamente o "tingimento apagado" que o bloco
    /// deveria eliminar. Girar o matiz mantém a saturação alta e ainda dá profundidade.
    var heroBottom: Color { shifted(hueDelta: 0.045, saturation: 1.0, brightness: 0.74) }

    /// Gira matiz/satura/escurece em HSB. O sentido do giro depende do matiz de origem:
    /// abaixo de 0.5 (vermelhos, laranjas, amarelos) gira para BAIXO, em direção ao
    /// vermelho; de 0.5 para cima (cianos, azuis) gira para CIMA, em direção ao violeta.
    /// Nos dois casos a base do gradiente cai no lado quente-escuro/violeta, que é o que
    /// dá o degradê de dashboard em vez de um retângulo chapado.
    private func shifted(hue: Double = 0, hueDelta: Double = 0, saturation: Double, brightness: Double) -> Color {
        guard let base = NSColor(self).usingColorSpace(.sRGB) else { return self }
        var h: CGFloat = 0, sat: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        base.getHue(&h, saturation: &sat, brightness: &b, alpha: &a)
        let direction: CGFloat = h < 0.5 ? -1 : 1
        var newHue = h + direction * CGFloat(hueDelta) + CGFloat(hue)
        newHue = newHue.truncatingRemainder(dividingBy: 1)
        if newHue < 0 { newHue += 1 }
        return Color(nsColor: NSColor(
            hue: newHue,
            saturation: min(1, sat * CGFloat(saturation)),
            brightness: min(1, b * CGFloat(brightness)),
            alpha: a
        ))
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Token de cor que troca sozinho entre claro e escuro.
///
/// Implementado como `ShapeStyle` que lê `EnvironmentValues.colorScheme`, e NÃO como
/// `NSColor(name:dynamicProvider:)`. A primeira tentativa usou o `NSColor` dinâmico e as
/// superfícies saíram CLARAS num render forçado para escuro: o provider do AppKit é
/// resolvido pela aparência corrente de desenho, que o `ImageRenderer` não herda do
/// `environment` do SwiftUI. Lendo o ambiente direto, o mesmo token vale para a janela
/// viva e para o PNG — que é exatamente a divergência que fez todo o design ser julgado
/// no tema errado.
struct ThemeColor: ShapeStyle {
    let light: Color
    let dark: Color

    func resolve(in environment: EnvironmentValues) -> Color {
        environment.colorScheme == .dark ? dark : light
    }
}

/// Liquid Glass, restrito a cromo (headers, barras de ação, a faixa flutuante do
/// popover). Fica fora dos dashboards e dos cards de detalhe, onde ficaria atrás de
/// número e gráfico densos e prejudicaria a leitura. A faixa "Hoje" é a exceção
/// deliberada: tem número e sparkline, mas é uma tira fina e flutuante, lida como cromo.
///
/// Usa `glassEffect(_:in:)` de verdade — a API do macOS 26, confirmada com a assinatura
/// `glassEffect(_ glass: Glass = .regular, in shape: some Shape)` no
/// `SwiftUICore.swiftinterface` do SDK instalado. Nasceu com `.regularMaterial` só
/// porque o nome da API ainda não estava confirmado quando o plano começou.
///
/// O vidro precisa do compositor vivo: sob `ImageRenderer` ele não só deixa de desenhar
/// o fundo como apaga a subárvore inteira — os PNGs de `docs/assets` perdiam a faixa
/// "Hoje" com número e sparkline. Por isso o render estático cai no material, pelo mesmo
/// `isStaticRender` que já troca os controles do AppKit. O app nunca liga essa flag.
private struct GlassChrome<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.isStaticRender) private var isStaticRender

    func body(content: Content) -> some View {
        if isStaticRender {
            content.background(.regularMaterial, in: shape)
        } else {
            content.glassEffect(.regular, in: shape)
        }
    }
}

extension View {
    /// Vidro na cápsula/retângulo arredondado padrão (faixa flutuante).
    func glassChrome() -> some View {
        modifier(GlassChrome(shape: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)))
    }

    /// Vidro numa faixa que encosta nas bordas — header e barra de ações do popover, onde
    /// um canto arredondado deixaria um vinco visível contra a moldura da janela.
    func glassChrome<S: Shape>(in shape: S) -> some View {
        modifier(GlassChrome(shape: shape))
    }
}

extension Color {
    /// Luminância relativa alta o bastante para exigir texto escuro em cima. Usado pelo
    /// `IconChip`: a cor de identidade é escolhida para ser distinguível das outras, não
    /// para ter contraste com o off-white.
    var isLight: Bool {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .white
        return (0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent) > 0.6
    }
}
