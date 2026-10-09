import SwiftUI

/// Mesmo formulário para reconectar uma conta existente e adicionar outra conta.
struct ClaudeLoginCodeEntry: View {
    @Binding var code: String
    let onComplete: () -> Void
    let onCancel: () -> Void

    private var hasCode: Bool {
        !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(L("Autorize no navegador, copie o código e cole abaixo:"))
                .font(.caption).foregroundStyle(.secondary)
            TextField("CÓDIGO#STATE", text: $code)
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .accessibilityLabel(L("Autorize no navegador, copie o código e cole abaixo:"))
                .accessibilityIdentifier("claude-login-code")
                .onSubmit { if hasCode { onComplete() } }
            HStack {
                Button(L("Concluir"), action: onComplete)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!hasCode)
                    .accessibilityIdentifier("claude-login-done")
                Button(L("Cancelar"), action: onCancel)
                    .buttonStyle(.bordered)
            }
        }
    }
}
