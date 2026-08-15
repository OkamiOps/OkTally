// Sources/OkTally/UI/DesignSystem/ProviderSidebarRow.swift
import SwiftUI

/// Linha de sidebar com chip colorido e ponto de status. Estava duplicada entre
/// `MainWindowView.sidebarRow` e `PreferencesView.sidebarRow`.
///
/// O chip passou a ser o `IconChip` saturado do resto do app. A versão anterior era a
/// única sobrevivente do desenho antigo — `color.opacity(0.16)` com o glifo na própria
/// cor —, que contra a base quase preta vira um retângulo cinza com uma letra apagada.
/// Como a sidebar é a primeira coisa que se vê nas duas janelas, era justamente ali que
/// a identidade dos dez provedores estava sendo jogada fora.
struct ProviderSidebarRow: View {
    let providerId: String
    let name: String
    let statusColor: Color
    var statusHelp: String = ""

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            IconChip(glyph: ProviderPalette.glyph(forId: providerId),
                     color: ProviderPalette.color(for: providerId),
                     size: 18)
            Text(name).font(Theme.Font.body)
            Spacer()
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
                .help(statusHelp)
        }
    }
}
