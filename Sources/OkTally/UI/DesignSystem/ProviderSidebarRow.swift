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
    /// E-mail da conta, quando conhecido — é o que separa duas contas do mesmo provedor
    /// sem apelido. Trunca no meio: o começo e o domínio são as partes que identificam.
    var subtitle: String? = nil

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            IconChip(glyph: ProviderPalette.glyph(forId: providerId),
                     color: ProviderPalette.color(for: providerId),
                     size: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(name).font(Theme.Font.body).lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
                .help(statusHelp)
        }
    }
}
