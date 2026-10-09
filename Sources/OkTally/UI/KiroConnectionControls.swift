import SwiftUI

/// Importar copia uma sessão para esta conta do OkTally. Os dois aplicativos
/// podem estar conectados em contas diferentes, por isso a origem é explícita.
struct KiroConnectionControls: View {
    let isConnected: Bool
    let isBusy: Bool
    let onImportCLI: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Button(L("Importar do Kiro CLI"), action: onImportCLI)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("kiro-import-cli")
                .disabled(isBusy)
            if isBusy {
                HStack(spacing: Theme.Space.sm) {
                    ProgressView().controlSize(.small)
                    Text(L("Verificando a conta Kiro…"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if isConnected {
                Button(L("Desconectar do OkTally"), action: onDisconnect)
                    .buttonStyle(.bordered)
                    .disabled(isBusy)
            }
            Text(L("Entre no Kiro CLI e importe a sessão. Para adicionar outra conta, entre nela no Kiro CLI e importe novamente em Adicionar conta."))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Link(L("Como entrar no Kiro"), destination: URL(string: "https://kiro.dev/docs/getting-started/authentication/")!)
                .font(.caption)
        }
    }

}
