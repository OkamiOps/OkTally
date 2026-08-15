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
                .foregroundStyle(QuotaPresentation.menuBarColor(remaining: segment.remaining,
                                                                onDarkBar: onDarkBar))
        }
        .padding(.horizontal, 1)
        .fixedSize()
    }

    /// A marca, pelo mesmo `BrandMark` que o popover, as Preferências e o notch usam —
    /// e não por uma cópia local do carregamento do PNG.
    ///
    /// Eram dois caminhos até aqui, e eles divergiram: este desenhava o arquivo oficial
    /// num quadrado de 15pt (glifo de ~11pt, por causa da margem do canvas) enquanto o
    /// `BrandMark` desenhava uma reinterpretação em SwiftUI que nem era a marca. Um
    /// componente só, com `size` significando a altura do desenho, mantém a barra e o
    /// notch mostrando a MESMA coisa — que é o mínimo que se espera de uma identidade.
    private var symbol: some View {
        BrandMark(size: 13)
            .foregroundStyle(ink)
    }

    // A cor do número sai de `QuotaPresentation.menuBarColor`: a escala contínua, com o
    // escurecimento que a barra CLARA exige (o amarelo da escala tem 1,3:1 contra uma
    // barra branca — some). O símbolo continua na tinta neutra: ele é identidade, não
    // estado, e um símbolo colorido brigaria com o número ao lado.
    //
    // O número era neutro com folga e só ganhava cor abaixo de 30%. Era essa regra, boa
    // para três degraus, que fazia a barra não dizer nada durante 90% do tempo.
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
    /// O mesmo símbolo, com o nome que o resto do app usa. `menuBarSymbol` continua
    /// existindo porque é o nome que a barra de menu sempre teve; `symbol` é o apelido
    /// para quem não é a barra (o `BrandMark`, que agora desenha ESTE arquivo em vez de
    /// uma reinterpretação em SwiftUI).
    static var symbol: NSImage? { menuBarSymbol }

    /// Que fatia da ALTURA do canvas do PNG o glifo realmente ocupa (o resto é margem
    /// transparente).
    ///
    /// Existe para `BrandMark(size:)` poder significar "a marca sai com esta altura", e
    /// não "a marca sai dentro de um quadrado deste tamanho" — a diferença entre as duas
    /// leituras é uns 25%, e é ela que fazia o símbolo parecer encolhido ao lado de um
    /// texto do mesmo corpo. Medida do arquivo, não cravada: se a marca for regerada com
    /// outra margem, o número acompanha sozinho.
    ///
    /// 0,74 é o valor do asset atual; o `1` do fallback só vale se a medição falhar, e aí
    /// o pior que acontece é o símbolo voltar a sair pequeno — nunca esticado.
    static let symbolHeightRatio: CGFloat = {
        guard let symbol,
              let rep = symbol.representations.max(by: { $0.pixelsHigh < $1.pixelsHigh }) as? NSBitmapImageRep,
              rep.pixelsHigh > 0
        else { return 1 }
        var top = rep.pixelsHigh, bottom = -1
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
                top = min(top, y)
                bottom = max(bottom, y)
                break
            }
        }
        guard bottom >= top else { return 1 }
        return CGFloat(bottom - top + 1) / CGFloat(rep.pixelsHigh)
    }()

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
