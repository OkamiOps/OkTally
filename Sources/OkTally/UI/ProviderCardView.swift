// Sources/OkTally/UI/ProviderCardView.swift
import SwiftUI

struct ProviderCardView: View {
    let provider: UsageProvider
    let snapshot: ProviderSnapshot?
    let errorMessage: String?
    /// How to color/frame `errorMessage`. `nil` (e.g. from an older call site, or a
    /// message with no classified error behind it) falls back to the old all-red
    /// behavior rather than crashing or silently dropping the message.
    var errorKind: ProviderErrorPresentation? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(provider.displayName)
                .font(.headline)
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(errorColor)
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

    private var errorColor: Color {
        switch errorKind {
        case .notConfigured: return .secondary
        case .needsReauth: return .orange
        case .error, .none: return .red
        }
    }
}
