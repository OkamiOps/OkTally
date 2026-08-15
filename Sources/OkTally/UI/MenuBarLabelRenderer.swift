// Sources/OkTally/UI/MenuBarLabelRenderer.swift
import SwiftUI
import AppKit

/// `MenuBarExtra` desenha rótulos de texto como template (monocromático) e descarta
/// qualquer `foregroundStyle` — a única forma de cor sobreviver na barra é uma `NSImage`
/// NÃO-template. Aqui o par símbolo + número vira essa imagem.
enum MenuBarLabelRenderer {
    /// A barra do sistema é escura? A imagem é montada FORA do contexto de aparência da
    /// barra, então isto tem que ser dito, nunca herdado.
    @MainActor
    static func image(for segment: MenuBarSegment, onDarkBar: Bool) -> NSImage {
        let renderer = ImageRenderer(content: MenuBarLabelView(segment: segment, onDarkBar: onDarkBar))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return NSImage() }
        image.isTemplate = false
        // A barra vira um bitmap: sem isto o VoiceOver anuncia "imagem" e o número que
        // justifica o app inteiro fica inaudível.
        image.accessibilityDescription = accessibilityDescription(for: segment)
        return image
    }

    private static func accessibilityDescription(for segment: MenuBarSegment) -> String {
        guard let providerId = segment.providerId else { return segment.text }
        return "\(providerId) \(segment.text)"
    }
}

/// Símbolo da marca + UM número. Antes daqui a barra imprimia um segmento por pino e o
/// dono descreveu o resultado como "muito feios e ruins de ler": cinco pares
/// glifo+número de 10pt encostados viram uma faixa de ruído colorido no menu do sistema.
///
/// O que ficou: o símbolo oficial (`MenuBarTemplate.png`, o mesmo asset da marca) para a
/// barra dizer *de quem* é o número, e a cota mais apertada. O resto mora no painel do
/// notch e no popover.
struct MenuBarLabelView: View {
    let segment: MenuBarSegment
    /// Escuro é o padrão porque é onde o dono vive, mas quem desenha na barra de verdade
    /// (`OkTallyApp`) sempre passa o valor observado — ver `MenuBarInk`.
    var onDarkBar: Bool = true

    private var ink: Color { MenuBarInk.color(onDarkBar: onDarkBar) }

    var body: some View {
        HStack(spacing: 4) {
            symbol
            Text(segment.text)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color(for: segment.danger))
        }
        .padding(.horizontal, 1)
        .fixedSize()
    }

    /// O PNG template da marca quando o bundle o entrega; o vetor `BrandMark` quando não.
    /// O fallback existe porque o bundle de recursos precisa ser empacotado junto (ver
    /// `AppResources`) — se um empacotamento futuro esquecer disso, a barra continua
    /// mostrando a marca em vez de um buraco.
    @ViewBuilder private var symbol: some View {
        if let nsImage = BrandAssets.menuBarSymbol {
            Image(nsImage: nsImage)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .frame(width: 15, height: 15)
                .foregroundStyle(ink)
        } else {
            BrandMark(size: 15)
                .foregroundStyle(ink)
        }
    }

    /// Escala de perigo da marca. Com folga o número é NEUTRO de propósito: quase toda
    /// cota está folgada, e um número verde permanente ensina o olho a ignorar a cor —
    /// aí, quando ela finalmente muda, ninguém percebe. Cor aqui é exceção, igual ao
    /// `QuotaPresentation.valueColor` do resto do app.
    private func color(for danger: DangerLevel) -> Color {
        switch danger {
        case .ok, .neutral: return ink
        case .warn: return Theme.Brand.heatOrange
        case .critical: return Theme.Brand.neonMagenta
        }
    }
}

/// A tinta do rótulo da barra de menu — símbolo e números sem alarme.
///
/// ## Por que isto virou um cálculo explícito
///
/// O rótulo da barra é uma `NSImage` NÃO-template (é a única forma de os números
/// coloridos sobreviverem: `MenuBarExtra` monocromatiza qualquer coisa marcada como
/// template). O preço disso é que o macOS deixa de adaptar a cor sozinho — o que sai do
/// `ImageRenderer` é literalmente o que aparece na barra.
///
/// A primeira versão pagou esse preço com um cinza médio fixo (0.58) escolhido para
/// "ter contraste nas duas barras". Na barra escura real ele dá ~5:1 enquanto TODO ícone
/// vizinho do sistema é branco puro (~17:1): o símbolo do OkTally não ficava ilegível,
/// ficava *apagado* — que foi exatamente a palavra do dono. Contraste suficiente para
/// passar num teste e insuficiente para pertencer à fileira.
///
/// A correção é dizer a cor certa para cada barra, em vez de procurar uma cor que sirva
/// para as duas. Puro e testável: `Tests/MenuBarInkTests` mede o contraste WCAG dos dois
/// valores contra as barras reais.
enum MenuBarInk {
    /// Quase branco, não branco puro: na barra escura o branco puro num traço de 1,5pt
    /// floresce e o símbolo engorda.
    static let onDarkBar: Double = 0.96
    /// Quase preto, pelo motivo espelhado.
    static let onLightBar: Double = 0.14

    static func white(onDarkBar dark: Bool) -> Double { dark ? onDarkBar : onLightBar }

    static func color(onDarkBar dark: Bool) -> Color { Color(white: white(onDarkBar: dark)) }

    /// Contraste WCAG entre dois cinzas sRGB (0…1). Existe para o teste poder afirmar
    /// "isto se lê", em vez de a legibilidade ser opinião de quem escolheu o número.
    static func contrastRatio(_ a: Double, _ b: Double) -> Double {
        let lighter = max(relativeLuminance(a), relativeLuminance(b))
        let darker = min(relativeLuminance(a), relativeLuminance(b))
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func relativeLuminance(_ channel: Double) -> Double {
        channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }
}

/// Assets de marca que moram como arquivo no bundle do target (e não desenhados em
/// SwiftUI, como o `BrandMark`).
enum BrandAssets {
    /// O símbolo template oficial da barra de menu, 18×18pt, com as três resoluções
    /// dentro de UMA `NSImage`.
    ///
    /// As três representações importam: sem elas o `ImageRenderer` teria que reamostrar o
    /// PNG de 18px num Retina de 2× ou 3× e o traço sairia borrado. Cada bitmap entra com
    /// `size` de 18×18 *pontos* — é o tamanho em pontos, não em pixels, que faz o AppKit
    /// escolher a representação certa para a escala corrente.
    static let menuBarSymbol: NSImage? = {
        let pointSize = NSSize(width: 18, height: 18)
        let reps: [NSImageRep] = ["MenuBarTemplate", "MenuBarTemplate@2x", "MenuBarTemplate@3x"]
            .compactMap { name in
                guard let url = AppResources.bundle.url(forResource: name, withExtension: "png"),
                      let data = try? Data(contentsOf: url),
                      let rep = NSBitmapImageRep(data: data)
                else { return nil }
                rep.size = pointSize
                return rep
            }
        guard !reps.isEmpty else { return nil }
        let image = NSImage(size: pointSize)
        reps.forEach(image.addRepresentation)
        image.isTemplate = true
        return image
    }()
}
