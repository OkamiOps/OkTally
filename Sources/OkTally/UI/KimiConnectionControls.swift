import SwiftUI

struct KimiConnectionControls: View {
    let isConnected: Bool
    let isBusy: Bool
    let authorization: KimiDeviceAuthorization?
    let onLogin: () -> Void
    let onCancel: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(spacing: Theme.Space.sm) {
                Button(L("Entrar no Kimi Code…"), action: onLogin)
                    .buttonStyle(.borderedProminent).disabled(isBusy)
                    .accessibilityIdentifier("kimi-sign-in")
                if isBusy {
                    ProgressView().controlSize(.small)
                    Button(L("Cancelar login"), action: onCancel).buttonStyle(.bordered)
                } else if isConnected {
                    Button(L("Desconectar"), action: onDisconnect).buttonStyle(.bordered)
                }
            }
            if let authorization {
                Text(L("Confirme este código no navegador:")).font(.caption).foregroundStyle(.secondary)
                Text(authorization.userCode).font(.title3.monospaced()).textSelection(.enabled)
                Link(L("Abrir autorização do Kimi"), destination: authorization.verificationURL)
            }
            Text(L("A sessão de cada conta é guardada separadamente no Keychain."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
