// Sources/OkTally/UI/DesignSystem/Theme.swift
import SwiftUI

/// Tokens visuais do app. Antes disto, `RoundedRectangle(cornerRadius: 12)
/// .fill(Color.primary.opacity(0.045))` estava copiado em seis lugares — mudar a
/// estética exigia editar todos.
enum Theme {
    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
    }

    enum Font {
        static let metricHero = SwiftUI.Font.system(size: 34, weight: .bold, design: .rounded)
        static let metricLarge = SwiftUI.Font.system(size: 22, weight: .bold, design: .rounded)
        static let metricMedium = SwiftUI.Font.system(size: 15, weight: .semibold, design: .rounded)
        static let body = SwiftUI.Font.system(size: 12)
        static let label = SwiftUI.Font.system(size: 9, weight: .semibold)
    }

    /// Superfícies derivadas de `Color.primary` para acompanhar claro e escuro sozinhas.
    static func surface() -> Color { Color.primary.opacity(0.045) }
    static func surfaceRaised() -> Color { Color.primary.opacity(0.075) }
    static func border() -> Color { Color.primary.opacity(0.07) }

    /// Fundo tingido do bloco-herói.
    static func surfaceAccent(_ color: Color) -> LinearGradient {
        LinearGradient(
            colors: [color.opacity(0.18), color.opacity(0.05)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// Liquid Glass, restrito a cromo (headers, barras de ação, a faixa flutuante do
/// popover). Vidro atrás de número ou gráfico prejudica a leitura, então nada de
/// conteúdo denso usa isto.
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
private struct GlassChrome: ViewModifier {
    @Environment(\.isStaticRender) private var isStaticRender

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
        if isStaticRender {
            content.background(.regularMaterial, in: shape)
        } else {
            content.glassEffect(.regular, in: shape)
        }
    }
}

extension View {
    func glassChrome() -> some View { modifier(GlassChrome()) }
}
