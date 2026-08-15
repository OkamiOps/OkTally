// Sources/OkTally/UI/Charts/ProviderShareDonut.swift
import SwiftUI
import Charts

/// Participação de cada provider no período — a leitura instantânea de quem consome o quê.
struct ProviderShareDonut: View {
    let share: [(providerId: String, tokens: Int)]

    private var total: Int { share.reduce(0) { $0 + $1.tokens } }

    var body: some View {
        Chart(share, id: \.providerId) { slice in
            SectorMark(
                angle: .value(L("Tokens"), slice.tokens),
                innerRadius: .ratio(0.62),
                angularInset: 1.5
            )
            .cornerRadius(3)
            .foregroundStyle(ProviderPalette.color(for: slice.providerId))
        }
        .chartLegend(.hidden)
        .overlay {
            VStack(spacing: 0) {
                Text(TokenAnalytics.compactTokens(total))
                    .font(Theme.Font.metricMedium)
                    .monospacedDigit()
                Text(L("total"))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
