// Sources/OkTally/UI/PreferencesView.swift
import SwiftUI

struct PreferencesView: View {
    let preferencesStore: PreferencesStore
    @State private var openRouterAPIKey: String = ""

    var body: some View {
        Form {
            Section("OpenRouter") {
                SecureField("API Key", text: $openRouterAPIKey)
                Button("Salvar") {
                    preferencesStore.openRouterAPIKey = openRouterAPIKey
                }
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            openRouterAPIKey = preferencesStore.openRouterAPIKey ?? ""
        }
    }
}
