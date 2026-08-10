// Sources/OkTally/UI/PreferencesView.swift
import SwiftUI
import AppKit

struct PreferencesView: View {
    let preferencesStore: PreferencesStore
    let tokenStore: TokenStoring
    let browserFlow: BrowserOAuthFlow
    let manualFlow: ManualCodeOAuthFlow
    let deviceCodeFlow: DeviceCodeFlow
    let mimoSessionStore: MiMoSessionStoring
    let onImportClaudeLegacy: () -> Bool

    @State private var openRouterAPIKey: String = ""
    @State private var minimaxAPIKey: String = ""
    @State private var minimaxRegionIsChina = false
    @State private var openCodeAPIKey: String = ""
    @State private var mimoAPIKey: String = ""
    @State private var mimoAllowance: String = ""
    @State private var mimoUsed: String = ""
    @State private var claudeLoggedIn = false
    @State private var claudeSession: ManualCodeSession?
    @State private var claudePastedCode: String = ""
    @State private var codexLoggedIn = false
    @State private var superGrokLoggedIn = false
    @State private var superGrokDeviceCode: DeviceCodeInfo?
    @State private var mimoLoggedIn = false
    @State private var statusMessage: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Contas e chaves")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                claudeCard
                codexCard
                superGrokCard
                cursorCard
                keyCard("OpenRouter", initial: "O", text: $openRouterAPIKey) {
                    saveSecret("OpenRouter") { try preferencesStore.setOpenRouterAPIKey(openRouterAPIKey) }
                }
                minimaxCard
                keyCard("OpenCode", initial: "◇", text: $openCodeAPIKey) {
                    saveSecret("OpenCode") { try preferencesStore.setOpenCodeAPIKey(openCodeAPIKey) }
                }
                mimoCard

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
            .padding(20)
        }
        .frame(width: 460, height: 620)
        .onAppear(perform: load)
    }

    // MARK: - Cards

    private var claudeCard: some View {
        card("Claude", initial: "C", active: claudeLoggedIn) {
            HStack {
                statusText(claudeLoggedIn ? "Conectado" : "Não conectado", active: claudeLoggedIn)
                Spacer()
                if claudeLoggedIn {
                    Button("Sair") { logout(providerId: "claude", flag: $claudeLoggedIn); claudeSession = nil }
                        .buttonStyle(.bordered).controlSize(.small)
                } else {
                    Button("Entrar…") { beginClaudeLogin() }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                    Button("Importar do Claude Code") {
                        statusMessage = onImportClaudeLegacy() ? "Login importado." : "Nenhum login do Claude Code encontrado."
                        claudeLoggedIn = tokenStore.load(providerId: "claude") != nil
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
            }
            if claudeSession != nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Autorize no navegador, copie o código e cole abaixo:")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("CÓDIGO#STATE", text: $claudePastedCode).textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Concluir") { completeClaudeLogin() }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                            .disabled(claudePastedCode.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button("Cancelar") { claudeSession = nil; claudePastedCode = ""; statusMessage = "" }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private var codexCard: some View {
        card("Codex", initial: "X", active: codexLoggedIn) {
            HStack {
                statusText(codexLoggedIn ? "Conectado" : "Não conectado", active: codexLoggedIn)
                Spacer()
                if codexLoggedIn {
                    Button("Sair") { logout(providerId: "codex", flag: $codexLoggedIn) }
                        .buttonStyle(.bordered).controlSize(.small)
                } else {
                    Button("Entrar…") { login(config: CodexOAuth.config, flag: $codexLoggedIn) }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                }
            }
        }
    }

    private var superGrokCard: some View {
        card("SuperGrok", initial: "G", active: superGrokLoggedIn) {
            HStack {
                statusText(superGrokLoggedIn ? "Conectado" : "Não conectado", active: superGrokLoggedIn)
                Spacer()
                if superGrokLoggedIn {
                    Button("Sair") { logout(providerId: SuperGrokOAuth.providerId, flag: $superGrokLoggedIn) }
                        .buttonStyle(.bordered).controlSize(.small)
                } else {
                    Button("Entrar…") { loginSuperGrok() }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                }
            }
            if let info = superGrokDeviceCode {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Abra \(info.verificationURL.absoluteString) e digite:")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(info.userCode).font(.title3.monospaced()).textSelection(.enabled)
                }
                .padding(.top, 4)
            }
        }
    }

    private var cursorCard: some View {
        card("Cursor", initial: "▹", active: true) {
            statusText("Lê a sessão do app Cursor automaticamente", active: true)
        }
    }

    private var minimaxCard: some View {
        card("MiniMax", initial: "M", active: !minimaxAPIKey.isEmpty) {
            SecureField("API Key", text: $minimaxAPIKey).textFieldStyle(.roundedBorder)
            Toggle("Região China (minimaxi.com)", isOn: $minimaxRegionIsChina)
                .toggleStyle(.switch).controlSize(.mini)
            HStack {
                Spacer()
                Button("Salvar") {
                    saveSecret("MiniMax") { try preferencesStore.setMinimaxAPIKey(minimaxAPIKey) }
                    preferencesStore.minimaxRegionRaw = minimaxRegionIsChina ? "china" : "global"
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
    }

    private var mimoCard: some View {
        card("MiMo", initial: "K", active: mimoLoggedIn) {
            HStack {
                statusText(mimoLoggedIn ? "Sessão ativa — uso automático" : "Sem sessão (usa estimativa)", active: mimoLoggedIn)
                Spacer()
                if mimoLoggedIn {
                    Button("Sair") { mimoSessionStore.isLoggedIn = false; mimoLoggedIn = false; statusMessage = "Sessão do MiMo removida." }
                        .buttonStyle(.bordered).controlSize(.small)
                } else {
                    Button("Entrar no MiMo…") {
                        MiMoWebSession.shared.presentLogin {
                            mimoSessionStore.isLoggedIn = true
                            mimoLoggedIn = true
                            statusMessage = "Sessão do MiMo ativa — uso automático."
                        }
                    }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                }
            }
            if !mimoLoggedIn {
                HStack(spacing: 8) {
                    TextField("Franquia (Credits)", text: $mimoAllowance).textFieldStyle(.roundedBorder)
                    TextField("Usados", text: $mimoUsed).textFieldStyle(.roundedBorder)
                    Button("Salvar") {
                        preferencesStore.mimoMonthlyAllowanceCredits = Double(mimoAllowance)
                        preferencesStore.mimoUsedCredits = Double(mimoUsed) ?? 0
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Reusable pieces

    private func keyCard(_ title: String, initial: String, text: Binding<String>, save: @escaping () -> Void) -> some View {
        card(title, initial: initial, active: !text.wrappedValue.isEmpty) {
            SecureField("API Key", text: text).textFieldStyle(.roundedBorder)
            HStack { Spacer(); Button("Salvar", action: save).buttonStyle(.borderedProminent).controlSize(.small) }
        }
    }

    private func card<C: View>(_ title: String, initial: String, active: Bool, @ViewBuilder content: () -> C) -> some View {
        let accent: Color = active ? .green : .secondary
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(accent.opacity(0.16)).frame(width: 30, height: 30)
                    Text(initial).font(.system(size: 14, weight: .bold)).foregroundStyle(accent)
                }
                Text(title).font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            content()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.07)))
    }

    private func statusText(_ text: String, active: Bool) -> some View {
        Text(text).font(.caption).foregroundStyle(active ? .green : .secondary)
    }

    private func load() {
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
        mimoLoggedIn = mimoSessionStore.isLoggedIn
    }

    // MARK: - Login flows (unchanged)

    private func login(config: OAuthConfig, flag: Binding<Bool>) {
        statusMessage = "Abrindo o navegador…"
        Task {
            do {
                _ = try await browserFlow.login(config: config)
                await MainActor.run { flag.wrappedValue = true; statusMessage = "Conectado." }
            } catch {
                await MainActor.run { statusMessage = error.localizedDescription }
            }
        }
    }

    private func beginClaudeLogin() {
        claudePastedCode = ""
        claudeSession = manualFlow.begin(config: ClaudeOAuth.config)
        statusMessage = "Abrindo o navegador — copie o código e cole aqui."
    }

    private func completeClaudeLogin() {
        guard let session = claudeSession else { return }
        let pasted = claudePastedCode
        statusMessage = "Validando código…"
        Task {
            do {
                _ = try await manualFlow.complete(pasted: pasted, session: session)
                await MainActor.run {
                    claudeLoggedIn = true; claudeSession = nil; claudePastedCode = ""; statusMessage = "Conectado."
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
                await MainActor.run { superGrokLoggedIn = true; superGrokDeviceCode = nil; statusMessage = "Conectado." }
            } catch {
                await MainActor.run { superGrokDeviceCode = nil; statusMessage = error.localizedDescription }
            }
        }
    }

    private func saveSecret(_ label: String, _ save: () throws -> Void) {
        do {
            try save()
            statusMessage = "\(label): chave salva."
        } catch {
            statusMessage = "\(label): falha ao salvar chave — \(error.localizedDescription)"
        }
    }

    private func logout(providerId: String, flag: Binding<Bool>) {
        try? tokenStore.delete(providerId: providerId)
        flag.wrappedValue = false
        statusMessage = "Desconectado."
    }
}
