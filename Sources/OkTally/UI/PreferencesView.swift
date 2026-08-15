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
    private let providerIds = ["claude", "codex", "supergrok", "cursor", "copilot", "antigravity", "openrouter", "minimax", "opencode", "mimo"]

    var body: some View {
        NavigationSplitView {
            List(selection: $pane) {
                Label(L("Geral"), systemImage: "slider.horizontal.3")
                    .tag(PreferencesPane.general)
                Section {
                    ForEach(providerIds, id: \.self) { id in
                        sidebarRow(id).tag(PreferencesPane.provider(id))
                    }
                } header: {
                    HStack {
                        Text(L("Contas"))
                        Spacer()
                        let attention = providerIds.filter { appModel.errorKindByProvider[$0] == .needsReauth }.count
                        if attention > 0 {
                            Text("\(attention)")
                                .font(.system(size: 9, weight: .bold))
                                .monospacedDigit()
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(Color.orange.opacity(0.25)))
                                .foregroundStyle(.orange)
                                .help(L("Contas com credencial expirada"))
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 180, max: 200)
        } detail: {
            // O pane Geral é um `Form` agrupado, que já rola sozinho — embrulhá-lo no
            // `ScrollView` dos panes de provedor daria rolagem aninhada.
            if case .general = pane {
                GeneralPane(appModel: appModel, preferencesStore: preferencesStore, providerName: providerName)
            } else {
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
        }
        .frame(minWidth: 680, idealWidth: 720, minHeight: 520, idealHeight: 560)
        .onAppear {
            load()
            consumeRequestedPane()
        }
        .onChange(of: appModel.requestedPreferencesPane) { _, _ in
            consumeRequestedPane()
        }
    }

    /// Salta para o pane pedido pelo botão "Reconectar"/"Configurar" do popover.
    private func consumeRequestedPane() {
        guard let requested = appModel.requestedPreferencesPane else { return }
        if providerIds.contains(requested) {
            pane = .provider(requested)
        }
        appModel.requestedPreferencesPane = nil
    }

    // MARK: - Sidebar

    private func sidebarRow(_ id: String) -> some View {
        ProviderSidebarRow(
            providerId: id,
            name: providerName(id),
            statusColor: statusDotColor(id),
            statusHelp: statusDotHelp(id)
        )
    }

    /// Tri-state (spec do redesign, agora completo): verde conectado, âmbar precisa
    /// reconectar (token presente mas o último fetch falhou por credencial), cinza não
    /// configurado.
    private func statusDotColor(_ id: String) -> Color {
        if appModel.errorKindByProvider[id] == .needsReauth { return .orange }
        return isConfigured(id) ? .green : Color.secondary.opacity(0.35)
    }

    private func statusDotHelp(_ id: String) -> String {
        if appModel.errorKindByProvider[id] == .needsReauth { return L("Credencial expirada — reconecte") }
        return isConfigured(id) ? L("Conectado") : L("Não configurado")
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
        case "copilot": return CopilotTokenReader().firstToken() != nil
        case "antigravity": return AntigravityTokenReader().readTokens() != nil
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
            EmptyView() // tratado antes do ScrollView, por rolar sozinho
        case .provider("claude"): claudePane
        case .provider("codex"): codexPane
        case .provider("supergrok"): superGrokPane
        case .provider("cursor"): cursorPane
        case .provider("copilot"): copilotPane
        case .provider("antigravity"): antigravityPane
        case .provider("openrouter"):
            keyPane("openrouter", text: $openRouterAPIKey, status: openRouterAPIKey.isEmpty ? L("Sem chave") : L("Chave salva")) {
                saveSecret("OpenRouter") { try preferencesStore.setOpenRouterAPIKey(openRouterAPIKey) }
            }
        case .provider("minimax"): minimaxPane
        case .provider("opencode"):
            keyPane("opencode", text: $openCodeAPIKey, status: openCodeAPIKey.isEmpty ? L("Sem chave") : L("Chave salva")) {
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
            paneHeader("claude", status: claudeLoggedIn ? L("Conectado") : L("Não conectado"), active: claudeLoggedIn)
            HStack {
                if claudeLoggedIn {
                    Button(L("Sair")) { logout(providerId: "claude", flag: $claudeLoggedIn); claudeSession = nil }
                        .buttonStyle(.bordered)
                } else {
                    Button(L("Entrar…")) { beginClaudeLogin() }
                        .buttonStyle(.borderedProminent)
                    Button(L("Importar do Claude Code")) {
                        statusMessage = onImportClaudeLegacy() ? L("Login importado.") : L("Nenhum login do Claude Code encontrado.")
                        claudeLoggedIn = tokenStore.load(providerId: "claude") != nil
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
            }
            if claudeSession != nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Autorize no navegador, copie o código e cole abaixo:"))
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("CÓDIGO#STATE", text: $claudePastedCode).textFieldStyle(.roundedBorder)
                    HStack {
                        Button(L("Concluir")) { completeClaudeLogin() }
                            .buttonStyle(.borderedProminent)
                            .disabled(claudePastedCode.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button(L("Cancelar")) { claudeSession = nil; claudePastedCode = ""; statusMessage = "" }
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var codexPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            paneHeader("codex", status: codexLoggedIn ? L("Conectado") : L("Não conectado"), active: codexLoggedIn)
            HStack {
                if codexLoggedIn {
                    Button(L("Sair")) { logout(providerId: "codex", flag: $codexLoggedIn) }.buttonStyle(.bordered)
                } else {
                    Button(L("Entrar…")) { login(config: CodexOAuth.config, flag: $codexLoggedIn) }
                        .buttonStyle(.borderedProminent)
                }
                Spacer()
            }
        }
    }

    private var superGrokPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            paneHeader("supergrok", status: superGrokLoggedIn ? L("Conectado") : L("Não conectado"), active: superGrokLoggedIn)
            HStack {
                if superGrokLoggedIn {
                    Button(L("Sair")) { logout(providerId: SuperGrokOAuth.providerId, flag: $superGrokLoggedIn) }
                        .buttonStyle(.bordered)
                } else {
                    Button(L("Entrar…")) { loginSuperGrok() }.buttonStyle(.borderedProminent)
                }
                Spacer()
            }
            if let info = superGrokDeviceCode {
                VStack(alignment: .leading, spacing: 4) {
                    Text(LF("Abra %@ e digite:", info.verificationURL.absoluteString))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(info.userCode).font(.title3.monospaced()).textSelection(.enabled)
                }
            }
        }
    }

    private var cursorPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            paneHeader("cursor", status: L("Lê a sessão do app Cursor automaticamente"), active: true)
            Text(L("Nada a configurar — se o app Cursor estiver logado nesta máquina, o uso aparece sozinho."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var copilotPane: some View {
        let detected = CopilotTokenReader().firstToken() != nil
        return VStack(alignment: .leading, spacing: 12) {
            paneHeader(
                "copilot",
                status: detected ? L("Login do Copilot/gh CLI detectado") : L("Nenhum login do Copilot/gh CLI encontrado"),
                active: detected
            )
            Text(L("Nada a configurar — detectado automaticamente a partir do login do Copilot ou do gh CLI neste Mac."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var antigravityPane: some View {
        let detected = AntigravityTokenReader().readTokens() != nil
        return VStack(alignment: .leading, spacing: 12) {
            paneHeader(
                "antigravity",
                status: detected ? L("Login do IDE Antigravity detectado") : L("Nenhum login do Antigravity encontrado"),
                active: detected
            )
            Text(L("Nada a configurar — detectado automaticamente a partir do login do IDE Antigravity neste Mac."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func keyPane(_ id: String, text: Binding<String>, status: String, save: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            paneHeader(id, status: status, active: !text.wrappedValue.isEmpty)
            SecureField("API Key", text: text).textFieldStyle(.roundedBorder).frame(maxWidth: 380)
            HStack { Button(L("Salvar"), action: save).buttonStyle(.borderedProminent); Spacer() }
        }
    }

    private var minimaxPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            paneHeader("minimax", status: minimaxAPIKey.isEmpty ? L("Sem chave") : L("Chave salva"), active: !minimaxAPIKey.isEmpty)
            SecureField("API Key", text: $minimaxAPIKey).textFieldStyle(.roundedBorder).frame(maxWidth: 380)
            Toggle(L("Região China (minimaxi.com)"), isOn: $minimaxRegionIsChina)
                .toggleStyle(.switch).controlSize(.small)
            HStack {
                Button(L("Salvar")) {
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
                       status: mimoLoggedIn ? L("Sessão ativa — uso automático") : L("Sem sessão (usa estimativa manual)"),
                       active: mimoLoggedIn)
            HStack {
                if mimoLoggedIn {
                    Button(L("Sair")) {
                        mimoSessionStore.isLoggedIn = false; mimoLoggedIn = false
                        statusMessage = L("Sessão do MiMo removida.")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button(L("Entrar no MiMo…")) {
                        MiMoWebSession.shared.presentLogin {
                            mimoSessionStore.isLoggedIn = true
                            mimoLoggedIn = true
                            statusMessage = L("Sessão do MiMo ativa — uso automático.")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                Spacer()
            }
            if mimoLoggedIn {
                Text(L("A sessão sobrevive a reinícios e se renova sozinha quando o console expira — só pede login de novo se a conta Xiaomi deslogar de verdade."))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Estimativa manual (sem sessão):")).font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        TextField(L("Franquia (Credits)"), text: $mimoAllowance).textFieldStyle(.roundedBorder)
                        TextField(L("Usados"), text: $mimoUsed).textFieldStyle(.roundedBorder)
                        Button(L("Salvar")) {
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
        statusMessage = L("Abrindo o navegador…")
        Task {
            do {
                _ = try await browserFlow.login(config: config)
                await MainActor.run { flag.wrappedValue = true; statusMessage = L("Conectado.") }
            } catch {
                await MainActor.run { statusMessage = error.localizedDescription }
            }
        }
    }

    private func beginClaudeLogin() {
        claudePastedCode = ""
        claudeSession = manualFlow.begin(config: ClaudeOAuth.config)
        statusMessage = L("Abrindo o navegador — copie o código e cole aqui.")
    }

    private func completeClaudeLogin() {
        guard let session = claudeSession else { return }
        let pasted = claudePastedCode
        statusMessage = L("Validando código…")
        Task {
            do {
                _ = try await manualFlow.complete(pasted: pasted, session: session)
                await MainActor.run {
                    claudeLoggedIn = true; claudeSession = nil; claudePastedCode = ""; statusMessage = L("Conectado.")
                }
            } catch {
                await MainActor.run { statusMessage = error.localizedDescription }
            }
        }
    }

    private func loginSuperGrok() {
        statusMessage = L("Solicitando código de dispositivo…")
        Task {
            do {
                let request = try await deviceCodeFlow.requestDeviceCode(config: SuperGrokOAuth.config)
                await MainActor.run {
                    superGrokDeviceCode = request.info
                    statusMessage = L("Digite o código no navegador para continuar.")
                    NSWorkspace.shared.open(request.info.verificationURL)
                }
                _ = try await deviceCodeFlow.poll(request, config: SuperGrokOAuth.config)
                await MainActor.run { superGrokLoggedIn = true; superGrokDeviceCode = nil; statusMessage = L("Conectado.") }
            } catch {
                await MainActor.run { superGrokDeviceCode = nil; statusMessage = error.localizedDescription }
            }
        }
    }

    private func saveSecret(_ label: String, _ save: () throws -> Void) {
        do {
            try save()
            statusMessage = LF("%@: chave salva.", label)
        } catch {
            statusMessage = LF("%@: falha ao salvar chave — %@", label, error.localizedDescription)
        }
    }

    private func logout(providerId: String, flag: Binding<Bool>) {
        try? tokenStore.delete(providerId: providerId)
        flag.wrappedValue = false
        statusMessage = L("Desconectado.")
    }
}


// MARK: - General pane

/// Ajustes gerais: pinos da barra de menu, alertas e atualização. Refresh intervals were
/// deliberately left out: the store's per-provider interval is not wired into the
/// Scheduler, so a UI for it would lie.
private struct GeneralPane: View {
    @ObservedObject var appModel: AppModel
    let preferencesStore: PreferencesStore
    let providerName: (String) -> String

    @State private var alertsEnabled = true
    @State private var percentSteps: Set<Double> = []
    @State private var lowBalanceText = ""
    @State private var savedFlash = false
    @FocusState private var lowBalanceFocused: Bool

    /// 50/70/80/90/100 — nenhuma migração necessária: `alertPercentThresholds` já persiste
    /// uma lista arbitrária de frações e o `AlertEngine` mapeia qualquer lista, então quem
    /// tinha 70/90/100 salvo continua com 70/90/100.
    private static let percentOptions: [Double] = [0.5, 0.7, 0.8, 0.9, 1.0]

    var body: some View {
        Form {
            Section(L("Barra de menu")) {
                if appModel.menuBarPins.isEmpty {
                    Text(L("Nada fixado — a barra mostra automaticamente a janela mais próxima do limite."))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(appModel.menuBarPins, id: \.stored) { pin in
                        pinRow(pin)
                    }
                }
                Text(L("Arraste para reordenar. Fixe janelas pelo alfinete no menu do OkTally — cada uma vira um número colorido na barra."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(L("Alertas")) {
                Toggle(L("Notificações de cota"), isOn: $alertsEnabled)
                    .toggleStyle(.switch)
                    .onChange(of: alertsEnabled) { _, newValue in
                        preferencesStore.alertsEnabled = newValue
                    }
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text(L("Avisar quando o uso cruzar:")).font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: Theme.Space.sm) {
                        ForEach(Self.percentOptions, id: \.self) { step in
                            thresholdChip(step)
                        }
                    }
                }
                HStack(spacing: Theme.Space.sm) {
                    Text(L("Saldo baixo (USD):")).font(.caption).foregroundStyle(.secondary)
                    TextField("5.00", text: $lowBalanceText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .focused($lowBalanceFocused)
                        .onSubmit(saveLowBalance)
                        .onChange(of: lowBalanceFocused) { _, focused in
                            // Auto-save também ao perder o foco: o botão "Salvar" saiu.
                            if !focused { saveLowBalance() }
                        }
                    if savedFlash {
                        Text(L("Salvo")).font(.caption).foregroundStyle(.green).transition(.opacity)
                    }
                }
            }
            .disabled(!alertsEnabled)
            .opacity(alertsEnabled ? 1 : 0.5)

            Section(L("Atualizações")) {
                if let update = appModel.availableUpdate {
                    HStack(spacing: Theme.Space.sm) {
                        Label(LF("Versão %@ disponível", update.version), systemImage: "arrow.down.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.orange)
                        Spacer()
                        Button(L("Abrir no GitHub")) { NSWorkspace.shared.open(update.url) }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                } else {
                    Text(L("Você está na versão mais recente."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            alertsEnabled = preferencesStore.alertsEnabled
            percentSteps = Set(preferencesStore.alertPercentThresholds)
            lowBalanceText = String(format: "%.2f", preferencesStore.alertLowBalanceThreshold)
        }
    }

    /// Linha de pino. O reordenamento é por arrastar-e-soltar: as setinhas ▲▼ saíram, e um
    /// `List` com `onMove` dentro do `Form` exigiria altura fixa — justamente o que este
    /// redesign proíbe.
    private func pinRow(_ pin: AppModel.MenuBarPin) -> some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Text(ProviderPalette.glyph(forId: pin.providerId))
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(ProviderPalette.color(for: pin.providerId))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5)
                    .fill(ProviderPalette.color(for: pin.providerId).opacity(0.16)))
            Text("\(providerName(pin.providerId)) · \(WindowLabelCatalog.displayLabel(pin.windowLabel))")
                .font(Theme.Font.body)
            Spacer()
            Button {
                appModel.menuBarPins.removeAll { $0.stored == pin.stored }
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L("Remover da barra de menu"))
        }
        .contentShape(Rectangle())
        .draggable(pin.stored)
        .dropDestination(for: String.self) { items, _ in
            guard let dragged = items.first else { return false }
            return movePin(stored: dragged, toPositionOf: pin)
        }
    }

    /// Move o pino arrastado para o índice do alvo, preservando a ordem dos demais.
    private func movePin(stored: String, toPositionOf target: AppModel.MenuBarPin) -> Bool {
        guard let from = appModel.menuBarPins.firstIndex(where: { $0.stored == stored }) else { return false }
        var pins = appModel.menuBarPins
        let moved = pins.remove(at: from)
        guard let to = pins.firstIndex(where: { $0.stored == target.stored }) else { return false }
        pins.insert(moved, at: to)
        appModel.menuBarPins = pins
        return true
    }

    /// Chip selecionável — substitui a checkbox solta.
    private func thresholdChip(_ step: Double) -> some View {
        let selected = percentSteps.contains(step)
        return Button {
            if selected { percentSteps.remove(step) } else { percentSteps.insert(step) }
            preferencesStore.alertPercentThresholds = percentSteps.sorted()
        } label: {
            Text("\(Int(step * 100))%")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .padding(.horizontal, Theme.Space.md)
                .padding(.vertical, Theme.Space.xs)
                .background(Capsule().fill(selected ? Color.accentColor.opacity(0.25) : Theme.surface()))
                .overlay(Capsule().strokeBorder(selected ? Color.accentColor.opacity(0.6) : Theme.border()))
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    /// Auto-save do saldo baixo. Todo o parsing vive no `FieldCommit`: campo vazio ou
    /// inalterado não grava nada, e lixo (inclusive notação científica como "1e3") é
    /// recusado e o campo volta ao valor salvo.
    private func saveLowBalance() {
        let stored = String(format: "%.2f", preferencesStore.alertLowBalanceThreshold)
        guard let candidate = FieldCommit.sanitized(lowBalanceText, previous: stored),
              let value = FieldCommit.lowBalance(candidate) else {
            lowBalanceText = stored
            return
        }
        preferencesStore.alertLowBalanceThreshold = value
        lowBalanceText = String(format: "%.2f", value)
        withAnimation { savedFlash = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { savedFlash = false }
        }
    }
}
