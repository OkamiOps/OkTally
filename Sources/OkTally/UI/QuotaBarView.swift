// Sources/OkTally/UI/QuotaBarView.swift
import SwiftUI

struct QuotaBarView: View {
    let window: QuotaWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(window.label)
                    .font(.caption)
                Spacer()
                Text(QuotaDisplayFormatter.valueText(for: window.shape))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let percent = window.shape.usedPercent {
                ProgressView(value: min(percent, 100), total: 100)
                    .opacity(window.shape.isEstimated ? 0.55 : 1.0)
            }
        }
        .help(window.shape.isEstimated ? "Estimativa local, não confirmada pelo provedor" : "")
    }
}
