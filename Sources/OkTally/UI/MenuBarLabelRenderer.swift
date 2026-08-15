// Sources/OkTally/UI/MenuBarLabelRenderer.swift
import SwiftUI
import AppKit

/// `MenuBarExtra` desenha rótulos de texto como template (monocromático) e descarta
/// qualquer `foregroundStyle` — a única forma de cor sobreviver na barra é uma `NSImage`
/// NÃO-template. Aqui o par símbolo + número vira essa imagem.
enum MenuBarLabelRenderer {
    @MainActor
    static func image(for segment: MenuBarSegment) -> NSImage {
        let renderer = ImageRenderer(content: MenuBarLabelView(segment: segment))
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

    var body: some View {
        HStack(spacing: 4) {
            symbol
            Text(segment.text)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
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
                .frame(width: 13, height: 13)
                .foregroundStyle(Self.chromeGray)
        } else {
            BrandMark(size: 13)
                .foregroundStyle(Self.chromeGray)
        }
    }

    /// Cinza médio, e não `.primary`: a imagem é renderizada fora do contexto de
    /// aparência da barra de menu, então uma cor semântica congelaria a aparência do app e
    /// poderia sumir contra a barra oposta. 0.58 tem contraste nas duas.
    private static let chromeGray = Color(white: 0.58)

    /// Escala de perigo da marca. Com folga o número é NEUTRO de propósito: quase toda
    /// cota está folgada, e um número verde permanente ensina o olho a ignorar a cor —
    /// aí, quando ela finalmente muda, ninguém percebe. Cor aqui é exceção, igual ao
    /// `QuotaPresentation.valueColor` do resto do app.
    private func color(for danger: DangerLevel) -> Color {
        switch danger {
        case .ok, .neutral: return Self.chromeGray
        case .warn: return Theme.Brand.heatOrange
        case .critical: return Theme.Brand.neonMagenta
        }
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
