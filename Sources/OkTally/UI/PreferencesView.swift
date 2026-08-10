// Sources/OkTally/UI/PreferencesView.swift
import SwiftUI
import AppKit

enum PreferencesPane: Hashable {
    case general
    case provider(String)
}

struct PreferencesView: View {
    let preferencesStore: PreferencesStore
    let tokenStore: TokenStoring
    let browserFlow: BrowserOAuthFlow
    let manualFlow: ManualCodeOAuthFlow
    let deviceCodeFlow: DeviceCodeFlow
    let mimoSessionStore: MiMoSessionStoring
    @ObservedObject var appModel: AppModel
    let onImportClaudeLegacy: () -> Bool

    @State private var pane: PreferencesPane = .general

    @State private var openRouterAPIKey: String = ""
    @State private var minimaxAPIKey: String = ""
    @State private var minimaxRegionIsChina = false
    @State private var openCodeAPIKey: String = ""
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

    /// Sidebar order — mirrors the old card order, not registration order.
    private let providerIds = ["claude", "codex", "supergrok", "cursor", "openrouter", "minimax", "opencode", "mimo"]

    var body: some View {
        NavigationSplitView {
            List(selection: $pane) {
                Label("Geral", systemImage: "slider.horizontal.3")
                    .tag(PreferencesPane.general)
                Section("Contas") {
                    ForEach(providerIds, id: \.self) { id in
                        sidebarRow(id).tag(PreferencesPane.provider(id))
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 180, max: 200)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    detailContent
                    if !statusMessage.isEmpty {
                        Text(statusMessage).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 640, height: 460)
        .onAppear(perform: load)
    }

    // MARK: - Sidebar

    private func sidebarRow(_ id: String) -> some View {
        let identity = ProviderPalette.color(for: id)
        return HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 5).fill(identity.opacity(0.16)).frame(width: 20, height: 20)
                Text(ProviderPalette.glyph(forId: id))
                    .font(.system(size: 10, weight: .heavy)).foregroundStyle(identity)
            }
            Text(providerName(id)).font(.system(size: 12))
            Spacer()
            Circle()
                .fill(isConfigured(id) ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 7, height: 7)
        }
    }

    private func providerName(_ id: String) -> String {
        appModel.orderedProviders.first(where: { $0.id == id })?.displayName ?? id
    }

    private func isConfigured(_ id: String) -> Bool {
        switch id {
        case "claude": return claudeLoggedIn
        case "codex": return codexLoggedIn
        case "supergrok": return superGrokLoggedIn
        case "cursor": return true // reads the Cursor app session automatically
        case "openrouter": return !openRouterAPIKey.isEmpty
        case "minimax": return !minimaxAPIKey.isEmpty
        case "opencode": return !openCodeAPIKey.isEmpty
        case "mimo": return mimoLoggedIn || !mimoAllowance.isEmpty
        default: return false
        }
    }

    // MARK: - Detail routing

    @ViewBuilder private var detailContent: some View {
        switch pane {
        case .general:
            GeneralPane(appModel: appModel, providerName: providerName)
        case .provider("claude"): claudePane
        case .provider("codex"): codexPane
        case .provider("supergrok"): superGrokPane
        case .provider("cursor"): cursorPane
        case .provider("openrouter"):
            keyPane("openrouter", text: $openRouterAPIKey, status: openRouterAPIKey.isEmpty ? "Sem chave" : "Chave salva") {
                saveSecret("OpenRouter") { try preferencesStore.setOpenRouterAPIKey(openRouterAPIKey) }
            }
        case .provider("minimax"): minimaxPane
        case .provider("opencode"):
            keyPane("opencode", text: $openCodeAPIKey, status: openCodeAPIKey.isEmpty ? "Sem chave" : "Chave salva") {
                saveSecret("OpenCode") { try preferencesStore.setOpenCodeAPIKey(openCodeAPIKey) }
            }
        case .provider("mimo"): mimoPane
        case .provider: EmptyView()
        }
    }

    private func paneHeader(_ id: String, status: String, active: Bool) -> some View {
        HStack(spacing: 12) {
            let identity = ProviderPalette.color(for: id)
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(identity.opacity(0.16)).frame(width: 40, height: 40)
                Text(ProviderPalette.glyph(forId: id))
                    .font(.system(size: 19, weight: .heavy)).foregroundStyle(identity)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(providerName(id)).font(.system(size: 16, weight: .bold))
                Text(status).font(.caption).foregroundStyle(active ? .green : .secondary)
            }
            Spacer()
        }
        .padding(.bottom, 4)
    }

    // MARK: - Provider panes

    private var claudePane: some View {
        VStack(alignment: .leading, spacing: 12) {
            paneHeader("claude", status: claudeLoggedIn ? "Conectado" : "Não conectado", active: claudeLoggedIn)
            HStack {
                if claudeLoggedIn {
                    Button("Sair") { logout(providerId: "claude", flag: $claudeLoggedIn); claudeSession = nil }
                        .buttonStyle(.bordered)
                } else {
                    Button("Entrar…") { beginClaudeLogin() }
                        .buttonStyle(.borderedProminent)
                    Button("Importar do Claude Code") {
                        statusMessage = onImportClaudeLegacy() ? "Login importado." : "Nenhum login do Claude Code encontrado."
                        claudeLoggedIn = tokenStore.load(providerId: "claude") != nil
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
            }
            if claudeSession != nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Autorize no navegador, copie o código e cole abaixo:")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("CÓDIGO#STATE", text: $claudePastedCode).textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Concluir") { completeClaudeLogin() }
                            .buttonStyle(.borderedProminent)
                            .disabled(claudePastedCode.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button("Cancelar") { claudeSession = nil; claudePastedCode = ""; statusMessage = "" }
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var codexPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            paneHeader("codex", status: codexLoggedIn ? "Conectado" : "Não conectado", active: codexLoggedIn)
            HStack {
                if codexLoggedIn {
                    Button("Sair") { logout(providerId: "codex", flag: $codexLoggedIn) }.buttonStyle(.bordered)
                } else {
                    Button("Entrar…") { login(config: CodexOAuth.config, flag: $codexLoggedIn) }
                        .buttonStyle(.borderedProminent)
                }
                Spacer()
            }
        }
    }

    private var superGrokPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            paneHeader("supergrok", status: superGrokLoggedIn ? "Conectado" : "Não conectado", active: superGrokLoggedIn)
            HStack {
                if superGrokLoggedIn {
                    Button("Sair") { logout(providerId: SuperGrokOAuth.providerId, flag: $superGrokLoggedIn) }
                        .buttonStyle(.bordered)
                } else {
                    Button("Entrar…") { loginSuperGrok() }.buttonStyle(.borderedProminent)
                }
                Spacer()
            }
            if let info = superGrokDeviceCode {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Abra \(info.verificationURL.absoluteString) e digite:")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(info.userCode).font(.title3.monospaced()).textSelection(.enabled)
                }
            }
        }
    }

    private var cursorPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            paneHeader("cursor", status: "Lê a sessão do app Cursor automaticamente", active: true)
            Text("Nada a configurar — se o app Cursor estiver logado nesta máquina, o uso aparece sozinho.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func keyPane(_ id: String, text: Binding<String>, status: String, save: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            paneHeader(id, status: status, active: !text.wrappedValue.isEmpty)
            SecureField("API Key", text: text).textFieldStyle(.roundedBorder).frame(maxWidth: 380)
            HStack { Button("Salvar", action: save).buttonStyle(.borderedProminent); Spacer() }
        }
    }

    private var minimaxPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            paneHeader("minimax", status: minimaxAPIKey.isEmpty ? "Sem chave" : "Chave salva", active: !minimaxAPIKey.isEmpty)
            SecureField("API Key", text: $minimaxAPIKey).textFieldStyle(.roundedBorder).frame(maxWidth: 380)
            Toggle("Região China (minimaxi.com)", isOn: $minimaxRegionIsChina)
                .toggleStyle(.switch).controlSize(.small)
            HStack {
                Button("Salvar") {
                    saveSecret("MiniMax") { try preferencesStore.setMinimaxAPIKey(minimaxAPIKey) }
                    preferencesStore.minimaxRegionRaw = minimaxRegionIsChina ? "china" : "global"
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            }
        }
    }

    private var mimoPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            paneHeader("mimo",
                       status: mimoLoggedIn ? "Sessão ativa — uso automático" : "Sem sessão (usa estimativa manual)",
                       active: mimoLoggedIn)
            HStack {
                if mimoLoggedIn {
                    Button("Sair") {
                        mimoSessionStore.isLoggedIn = false; mimoLoggedIn = false
                        statusMessage = "Sessão do MiMo removida."
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Entrar no MiMo…") {
                        MiMoWebSession.shared.presentLogin {
                            mimoSessionStore.isLoggedIn = true
                            mimoLoggedIn = true
                            statusMessage = "Sessão do MiMo ativa — uso automático."
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                Spacer()
            }
            if mimoLoggedIn {
                Text("A sessão sobrevive a reinícios e se renova sozinha quando o console expira — só pede login de novo se a conta Xiaomi deslogar de verdade.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Estimativa manual (sem sessão):").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        TextField("Franquia (Credits)", text: $mimoAllowance).textFieldStyle(.roundedBorder)
                        TextField("Usados", text: $mimoUsed).textFieldStyle(.roundedBorder)
                        Button("Salvar") {
                            preferencesStore.mimoMonthlyAllowanceCredits = Double(mimoAllowance)
                            preferencesStore.mimoUsedCredits = Double(mimoUsed) ?? 0
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: 420)
                }
            }
        }
    }

    // MARK: - State loading

    private func load() {
        openRouterAPIKey = preferencesStore.openRouterAPIKey ?? ""
        minimaxAPIKey = preferencesStore.minimaxAPIKey ?? ""
        minimaxRegionIsChina = preferencesStore.minimaxRegionRaw == "china"
        openCodeAPIKey = preferencesStore.openCodeAPIKey ?? ""
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

// MARK: - General pane

/// Menu bar pin management. Refresh intervals were deliberately left out: the store's
/// per-provider interval is not wired into the Scheduler, so a UI for it would lie.
private struct GeneralPane: View {
    @ObservedObject var appModel: AppModel
    let providerName: (String) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Barra de menu").font(.system(size: 16, weight: .bold))
            if appModel.menuBarPins.isEmpty {
                Text("Nada fixado — a barra mostra automaticamente a janela mais próxima do limite.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(appModel.menuBarPins.enumerated()), id: \.element.stored) { index, pin in
                        HStack(spacing: 8) {
                            Text(ProviderPalette.glyph(forId: pin.providerId))
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(ProviderPalette.color(for: pin.providerId))
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 5)
                                    .fill(ProviderPalette.color(for: pin.providerId).opacity(0.16)))
                            Text("\(providerName(pin.providerId)) · \(pin.windowLabel)")
                                .font(.system(size: 12))
                            Spacer()
                            Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }
                                .buttonStyle(.plain).disabled(index == 0)
                            Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }
                                .buttonStyle(.plain).disabled(index == appModel.menuBarPins.count - 1)
                            Button { appModel.menuBarPins.remove(at: index) } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.045)))
                    }
                }
                .frame(maxWidth: 420)
            }
            Text("Fixe janelas pelo alfinete no menu do OkTally — cada uma vira um número colorido na barra.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard appModel.menuBarPins.indices.contains(target) else { return }
        appModel.menuBarPins.swapAt(index, target)
    }
}
