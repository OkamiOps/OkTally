// Sources/OkTally/UI/ProviderCardView.swift
import SwiftUI

struct ProviderCardView: View {
    let provider: UsageProvider
    let snapshot: ProviderSnapshot?
    let errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(provider.displayName)
                .font(.headline)
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if let snapshot {
                ForEach(snapshot.quotas, id: \.label) { window in
                    QuotaBarView(window: window)
                }
            } else {
                Text("Carregando…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
    }
}
