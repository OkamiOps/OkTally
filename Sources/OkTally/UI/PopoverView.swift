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
                    errorMessage: appModel.errorsByProvider[provider.id],
                    errorKind: appModel.errorKindByProvider[provider.id]
                )
                Divider()
            }
            Button("Atualizar agora") {
                Task { await appModel.refreshNow() }
            }
            // SettingsLink is the public, version-stable way to open the Settings scene
            // (the private showSettingsWindow:/showPreferencesWindow: selector name has
            // drifted across macOS releases and silently no-ops when it's wrong). Tapping
            // it also activates the app, so the window comes to the front for an
            // LSUIElement menu bar app. Fall back to the selector on macOS 13.
            if #available(macOS 14.0, *) {
                SettingsLink {
                    Text("Preferências…")
                }
                .simultaneousGesture(TapGesture().onEnded {
                    NSApp.activate(ignoringOtherApps: true)
                })
            } else {
                Button("Preferências…") {
                    NSApp.activate(ignoringOtherApps: true)
                    DispatchQueue.main.async {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    }
                }
            }
            Button("Sair") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 260)
    }
}
