// Sources/OkTally/App/OkTallyApp.swift
import SwiftUI

@main
struct OkTallyApp: App {
    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 8) {
                Text("OkTally")
                    .font(.headline)
                Divider()
                Button("Sair") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(12)
            .frame(width: 200)
        } label: {
            Text("OK")
        }
        .menuBarExtraStyle(.window)
    }
}
