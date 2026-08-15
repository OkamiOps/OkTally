// Sources/OkTally/UI/DesignSystem/ProviderSidebarRow.swift
import SwiftUI

/// Linha de sidebar com chip colorido e ponto de status. Estava duplicada entre
/// `MainWindowView.sidebarRow` e `PreferencesView.sidebarRow`.
struct ProviderSidebarRow: View {
    let providerId: String
    let name: String
    let statusColor: Color
    var statusHelp: String = ""

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(ProviderPalette.color(for: providerId).opacity(0.16))
                    .frame(width: 20, height: 20)
                Text(ProviderPalette.glyph(forId: providerId))
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(ProviderPalette.color(for: providerId))
            }
            Text(name).font(Theme.Font.body)
            Spacer()
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
                .help(statusHelp)
        }
    }
}
