// Sources/OkTally/UI/PopoverView.swift
import SwiftUI

struct PopoverView: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(appModel.orderedProviders, id: \.id) { provider in
                ProviderCardView(
                    provider: provider,
                    snapshot: appModel.snapshotsByProvider[provider.id],
                    errorMessage: appModel.errorsByProvider[provider.id]
                )
                Divider()
            }
            Button("Atualizar agora") {
                Task { await appModel.refreshNow() }
            }
            Button("Preferências…") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            Button("Sair") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 260)
    }
}
