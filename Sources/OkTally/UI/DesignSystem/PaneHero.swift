// Sources/OkTally/UI/DesignSystem/PaneHero.swift
import SwiftUI

/// Faixa de cabeçalho de um painel de Preferências: o bloco de destaque da tela, colado
/// no topo do painel e sangrando até as bordas.
///
/// Existe porque a tela de Preferências não tinha nenhum elemento dominante — o cabeçalho
/// de cada provedor era a primeira `Section` de um `Form` agrupado, ou seja: um card
/// cinza idêntico aos outros dois, com um quadradinho de cor a 16% e o nome em 16pt. A
/// tela inteira era uma pilha de três retângulos iguais, e por isso não tinha identidade
/// nenhuma — era o `Form` padrão do sistema com outro acento.
///
/// A faixa sangra de propósito (sem raio, sem margem): é o que a distingue dos cards do
/// `Form` logo abaixo e o que faz o painel ter um "topo" em vez de começar no meio de uma
/// lista. O `Form` agrupado continua embaixo, intacto — o idioma nativo de Ajustes do
/// macOS não é substituído, ganha um cabeçalho.
struct PaneHero<Leading: View, Trailing: View>: View {
    let tint: Color
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.md) {
            leading
            Spacer(minLength: Theme.Space.md)
            trailing
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.vertical, Theme.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.heroFill(tint))
        // Sombra de contato em vez de borda: a faixa encosta no `Form` e uma linha clara
        // ali viraria um vinco. A escura separa sem desenhar moldura.
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.black.opacity(0.28)).frame(height: 1)
        }
    }
}

/// Cápsula de estado sobre o gradiente. Sobre cor saturada não dá para usar verde/laranja
/// do sistema (o verde some contra lima, o laranja contra terracota): o pino é off-white
/// translúcido e quem carrega o estado é o PONTO dentro dele, que é pequeno o bastante
/// para a cor não brigar com o fundo.
struct HeroStatusPill: View {
    let text: String
    let dot: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(dot)
                .frame(width: 6, height: 6)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.25)))
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.onHero)
                .lineLimit(1)
        }
        .padding(.horizontal, Theme.Space.sm)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.black.opacity(0.22)))
        .overlay(Capsule().strokeBorder(Theme.onHero.opacity(0.25)))
    }
}
