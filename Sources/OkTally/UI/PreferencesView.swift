// Sources/OkTally/UI/PreferencesView.swift
import SwiftUI
import AppKit

struct PreferencesView: View {
    let preferencesStore: PreferencesStore
    let tokenStore: TokenStoring
    let browserFlow: BrowserOAuthFlow
    let deviceCodeFlow: DeviceCodeFlow
    let onImportClaudeLegacy: () -> Bool

    @State private var openRouterAPIKey: String = ""
    @State private var minimaxAPIKey: String = ""
    @State private var minimaxRegionIsChina = false
    @State private var openCodeAPIKey: String = ""
    @State private var mimoAPIKey: String = ""
    @State private var mimoAllowance: String = ""
    @State private var mimoUsed: String = ""
    @State private var claudeLoggedIn = false
    @State private var codexLoggedIn = false
    @State private var superGrokLoggedIn = false
    @State private var superGrokDeviceCode: DeviceCodeInfo?
    @State private var statusMessage: String = ""

    var body: some View {
        Form {
            Section("Claude Code") {
                HStack {
                    Text(claudeLoggedIn ? "Conectado" : "Não conectado")
                        .foregroundStyle(claudeLoggedIn ? .green : .secondary)
                    Spacer()
                    if claudeLoggedIn {
                        Button("Sair") { logout(providerId: "claude", flag: $claudeLoggedIn) }
                    } else {
                        Button("Entrar…") { login(config: ClaudeOAuth.config, flag: $claudeLoggedIn) }
                        Button("Importar login do Claude Code") {
                            if onImportClaudeLegacy() {
                                claudeLoggedIn = true
                                statusMessage = "Login importado."
                            } else {
                                statusMessage = "Nenhum login do Claude Code encontrado."
                            }
                        }
                    }
                }
            }

            Section("Codex") {
                HStack {
                    Text(codexLoggedIn ? "Conectado" : "Não conectado")
                        .foregroundStyle(codexLoggedIn ? .green : .secondary)
                    Spacer()
                    if codexLoggedIn {
                        Button("Sair") { logout(providerId: "codex", flag: $codexLoggedIn) }
                    } else {
                        Button("Entrar…") { login(config: CodexOAuth.config, flag: $codexLoggedIn) }
                    }
                }
            }

            Section("SuperGrok") {
                HStack {
                    Text(superGrokLoggedIn ? "Conectado" : "Não conectado")
                        .foregroundStyle(superGrokLoggedIn ? .green : .secondary)
                    Spacer()
                    if superGrokLoggedIn {
                        Button("Sair") { logout(providerId: SuperGrokOAuth.providerId, flag: $superGrokLoggedIn) }
                    } else {
                        Button("Entrar…") { loginSuperGrok() }
                    }
                }
                if let info = superGrokDeviceCode {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Abra \(info.verificationURL.absoluteString) e digite o código:")
                            .font(.caption)
                        Text(info.userCode)
                            .font(.title3.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }

            Section("OpenRouter") {
                SecureField("API Key", text: $openRouterAPIKey)
                Button("Salvar") { preferencesStore.openRouterAPIKey = openRouterAPIKey }
            }

            Section("MiniMax") {
                SecureField("API Key", text: $minimaxAPIKey)
                Toggle("Região China (minimaxi.com)", isOn: $minimaxRegionIsChina)
                Button("Salvar") {
                    preferencesStore.minimaxAPIKey = minimaxAPIKey
                    preferencesStore.minimaxRegionRaw = minimaxRegionIsChina ? "china" : "global"
                }
            }

            Section("OpenCode") {
                SecureField("API Key", text: $openCodeAPIKey)
                Button("Salvar") { preferencesStore.openCodeAPIKey = openCodeAPIKey }
            }

            Section("MiMo (estimativa manual)") {
                SecureField("API Key (tp-…)", text: $mimoAPIKey)
                TextField("Franquia mensal (Credits)", text: $mimoAllowance)
                TextField("Credits usados", text: $mimoUsed)
                Button("Salvar") {
                    preferencesStore.mimoAPIKey = mimoAPIKey
                    preferencesStore.mimoMonthlyAllowanceCredits = Double(mimoAllowance)
                    preferencesStore.mimoUsedCredits = Double(mimoUsed) ?? 0
                }
            }

            if !statusMessage.isEmpty {
                Text(statusMessage).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            openRouterAPIKey = preferencesStore.openRouterAPIKey ?? ""
            minimaxAPIKey = preferencesStore.minimaxAPIKey ?? ""
            minimaxRegionIsChina = preferencesStore.minimaxRegionRaw == "china"
            openCodeAPIKey = preferencesStore.openCodeAPIKey ?? ""
            mimoAPIKey = preferencesStore.mimoAPIKey ?? ""
            mimoAllowance = preferencesStore.mimoMonthlyAllowanceCredits.map { String($0) } ?? ""
            mimoUsed = String(preferencesStore.mimoUsedCredits)
            claudeLoggedIn = tokenStore.load(providerId: "claude") != nil
            codexLoggedIn = tokenStore.load(providerId: "codex") != nil
            superGrokLoggedIn = tokenStore.load(providerId: SuperGrokOAuth.providerId) != nil
        }
    }

    private func login(config: OAuthConfig, flag: Binding<Bool>) {
        statusMessage = "Abrindo o navegador…"
        Task {
            do {
                _ = try await browserFlow.login(config: config)
                await MainActor.run {
                    flag.wrappedValue = true
                    statusMessage = "Conectado."
                }
            } catch {
                await MainActor.run { statusMessage = error.localizedDescription }
            }
        }
    }

    private func loginSuperGrok() {
        statusMessage = "Solicitando código de dispositivo…"
        Task {
            do {
                let request = try await deviceCodeFlow.requestDeviceCode(config: SuperGrokOAuth.config)
                await MainActor.run {
                    superGrokDeviceCode = request.info
                    statusMessage = "Digite o código no navegador para continuar."
                    NSWorkspace.shared.open(request.info.verificationURL)
                }
                _ = try await deviceCodeFlow.poll(request, config: SuperGrokOAuth.config)
                await MainActor.run {
                    superGrokLoggedIn = true
                    superGrokDeviceCode = nil
                    statusMessage = "Conectado."
                }
            } catch {
                await MainActor.run {
                    superGrokDeviceCode = nil
                    statusMessage = error.localizedDescription
                }
            }
        }
    }

    private func logout(providerId: String, flag: Binding<Bool>) {
        try? tokenStore.delete(providerId: providerId)
        flag.wrappedValue = false
        statusMessage = "Desconectado."
    }
}
