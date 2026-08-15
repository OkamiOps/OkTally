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
                                .background(Capsule().fill(Theme.Brand.heatOrange.opacity(0.25)))
                                .foregroundStyle(Theme.Brand.heatOrange)
                                .help(L("Contas com credencial expirada"))
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 180, max: 200)
        } detail: {
            // Geral e os panes de provider são `Form` agrupados, que já rolam sozinhos —
            // o `ScrollView` que os panes de provider tinham daria rolagem aninhada.
            if case .general = pane {
                GeneralPane(appModel: appModel, preferencesStore: preferencesStore, providerName: providerName)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    detailContent
                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(.horizontal, Theme.Space.xl)
                            .padding(.bottom, Theme.Space.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
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
        if appModel.errorKindByProvider[id] == .needsReauth { return Theme.Brand.heatOrange }
        // Verde da marca-vizinha, não `.green` do sistema: contra a base quase preta o
        // verde do sistema é a única cor da tela que não veio da paleta.
        return isConfigured(id) ? Color(hex: 0x35D07F) : Color.secondary.opacity(0.35)
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
            EmptyView() // tratado no branch anterior do detalhe, por rolar sozinho
        case .provider("claude"): claudePane
        case .provider("codex"): codexPane
        case .provider("supergrok"): superGrokPane
        case .provider("cursor"): cursorPane
        case .provider("copilot"): copilotPane
        case .provider("antigravity"): antigravityPane
        case .provider("openrouter"):
            keyPane("openrouter",
                    text: $openRouterAPIKey,
                    hasSavedKey: !(preferencesStore.openRouterAPIKey ?? "").isEmpty,
                    save: {
                        saveSecret("OpenRouter", previous: preferencesStore.openRouterAPIKey ?? "", raw: $openRouterAPIKey) {
                            try preferencesStore.setOpenRouterAPIKey($0)
                        }
                    },
                    remove: {
                        removeSecret("OpenRouter", raw: $openRouterAPIKey) {
                            try preferencesStore.setOpenRouterAPIKey(nil)
                        }
                    })
        case .provider("minimax"): minimaxPane
        case .provider("opencode"):
            keyPane("opencode",
                    text: $openCodeAPIKey,
                    hasSavedKey: !(preferencesStore.openCodeAPIKey ?? "").isEmpty,
                    save: {
                        saveSecret("OpenCode", previous: preferencesStore.openCodeAPIKey ?? "", raw: $openCodeAPIKey) {
                            try preferencesStore.setOpenCodeAPIKey($0)
                        }
                    },
                    remove: {
                        removeSecret("OpenCode", raw: $openCodeAPIKey) {
                            try preferencesStore.setOpenCodeAPIKey(nil)
                        }
                    })
        case .provider("mimo"): mimoPane
        case .provider: EmptyView()
        }
    }

    // MARK: - Provider panes

    private var claudePane: some View {
        ProviderPaneScaffold(
            providerId: "claude",
            snapshot: appModel.snapshotsByProvider["claude"],
            problem: appModel.errorsByProvider["claude"],
            name: providerName("claude"),
            status: claudeLoggedIn ? .connected(L("Conectado")) : .notConfigured(L("Não conectado"))
        ) {
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
            // O código colado continua sendo um passo da conexão — fica na mesma seção
            // dos botões para não virar um detalhe descolado do fluxo.
            if claudeSession != nil {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text(L("Autorize no navegador, copie o código e cole abaixo:"))
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("CÓDIGO#STATE", text: $claudePastedCode)
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                    HStack {
                        Button(L("Concluir")) { completeClaudeLogin() }
                            .buttonStyle(.borderedProminent)
                            .disabled(claudePastedCode.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button(L("Cancelar")) { claudeSession = nil; claudePastedCode = ""; statusMessage = "" }
                            .buttonStyle(.bordered)
                    }
                }
            }
        } details: {
            Text(L("O uso de cota vem da conta; o volume em tokens é estimado dos transcritos locais."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var codexPane: some View {
        ProviderPaneScaffold(
            providerId: "codex",
            snapshot: appModel.snapshotsByProvider["codex"],
            problem: appModel.errorsByProvider["codex"],
            name: providerName("codex"),
            status: codexLoggedIn ? .connected(L("Conectado")) : .notConfigured(L("Não conectado"))
        ) {
            if codexLoggedIn {
                Button(L("Sair")) { logout(providerId: "codex", flag: $codexLoggedIn) }.buttonStyle(.bordered)
            } else {
                Button(L("Entrar…")) { login(config: CodexOAuth.config, flag: $codexLoggedIn) }
                    .buttonStyle(.borderedProminent)
            }
        } details: {
            Text(L("Estatísticas de uso vêm da API da conta."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var superGrokPane: some View {
        ProviderPaneScaffold(
            providerId: "supergrok",
            snapshot: appModel.snapshotsByProvider["supergrok"],
            problem: appModel.errorsByProvider["supergrok"],
            name: providerName("supergrok"),
            status: superGrokLoggedIn ? .connected(L("Conectado")) : .notConfigured(L("Não conectado"))
        ) {
            if superGrokLoggedIn {
                Button(L("Sair")) { logout(providerId: SuperGrokOAuth.providerId, flag: $superGrokLoggedIn) }
                    .buttonStyle(.bordered)
            } else {
                Button(L("Entrar…")) { loginSuperGrok() }.buttonStyle(.borderedProminent)
            }
        } details: {
            if let info = superGrokDeviceCode {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(LF("Abra %@ e digite:", info.verificationURL.absoluteString))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(info.userCode).font(.title3.monospaced()).textSelection(.enabled)
                }
            } else {
                Text(L("O login usa código de dispositivo: o navegador abre e você digita o código mostrado aqui."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var cursorPane: some View {
        ProviderPaneScaffold(
            providerId: "cursor",
            snapshot: appModel.snapshotsByProvider["cursor"],
            problem: appModel.errorsByProvider["cursor"],
            name: providerName("cursor"),
            status: .connected(L("Lê a sessão do app Cursor automaticamente"))
        ) {
            Text(L("Nada a configurar — se o app Cursor estiver logado nesta máquina, o uso aparece sozinho."))
                .font(.caption).foregroundStyle(.secondary)
        } details: {
            EmptyView()
        }
    }

    private var copilotPane: some View {
        let detected = CopilotTokenReader().firstToken() != nil
        return ProviderPaneScaffold(
            providerId: "copilot",
            snapshot: appModel.snapshotsByProvider["copilot"],
            problem: appModel.errorsByProvider["copilot"],
            name: providerName("copilot"),
            status: detected
                ? .connected(L("Login do Copilot/gh CLI detectado"))
                : .notConfigured(L("Nenhum login do Copilot/gh CLI encontrado"))
        ) {
            Text(L("Nada a configurar — detectado automaticamente a partir do login do Copilot ou do gh CLI neste Mac."))
                .font(.caption).foregroundStyle(.secondary)
        } details: {
            EmptyView()
        }
    }

    private var antigravityPane: some View {
        let detected = AntigravityTokenReader().readTokens() != nil
        return ProviderPaneScaffold(
            providerId: "antigravity",
            snapshot: appModel.snapshotsByProvider["antigravity"],
            problem: appModel.errorsByProvider["antigravity"],
            name: providerName("antigravity"),
            status: detected
                ? .connected(L("Login do IDE Antigravity detectado"))
                : .notConfigured(L("Nenhum login do Antigravity encontrado"))
        ) {
            Text(L("Nada a configurar — detectado automaticamente a partir do login do IDE Antigravity neste Mac."))
                .font(.caption).foregroundStyle(.secondary)
        } details: {
            EmptyView()
        }
    }

    /// Painel de chave de API. O botão "Salvar" saiu: o campo grava no Enter e ao perder
    /// o foco, e `saveSecret` recusa campo vazio ou inalterado para que um blur acidental
    /// não apague a chave que está no Keychain.
    private func keyPane(_ id: String,
                         text: Binding<String>,
                         hasSavedKey: Bool,
                         save: @escaping () -> Void,
                         remove: @escaping () -> Void) -> some View {
        ProviderPaneScaffold(
            providerId: id,
            snapshot: appModel.snapshotsByProvider[id],
            problem: appModel.errorsByProvider[id],
            name: providerName(id),
            status: hasSavedKey ? .connected(L("Chave salva")) : .notConfigured(L("Sem chave"))
        ) {
            AutoSaveField(placeholder: "API Key", text: text, isSecure: true, onCommit: save)
                .frame(maxWidth: 380)
            // Esvaziar o campo não apaga nada (é a regra do auto-save), então revogar a
            // credencial precisa de um gesto deliberado — sem este botão não haveria
            // nenhuma forma de desconectar o provedor pelo app.
            //
            // A condição é o valor *salvo*, nunca o texto do campo: quem quer revogar
            // seleciona tudo e apaga, e o botão sumiria exatamente aí. O espelho também
            // importa — digitar num provedor sem chave não pode anunciar "Chave salva".
            if hasSavedKey {
                HStack {
                    Button(L("Remover chave"), role: .destructive, action: remove)
                        .buttonStyle(.bordered)
                    Spacer()
                }
            }
        } details: {
            Text(L("A chave fica no Keychain desta máquina, nunca em texto puro."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var minimaxPane: some View {
        // Mesma regra do `keyPane`: pill e botão seguem o Keychain, não o texto do campo.
        let hasSavedKey = !(preferencesStore.minimaxAPIKey ?? "").isEmpty
        return ProviderPaneScaffold(
            providerId: "minimax",
            snapshot: appModel.snapshotsByProvider["minimax"],
            problem: appModel.errorsByProvider["minimax"],
            name: providerName("minimax"),
            status: hasSavedKey ? .connected(L("Chave salva")) : .notConfigured(L("Sem chave"))
        ) {
            AutoSaveField(placeholder: "API Key", text: $minimaxAPIKey, isSecure: true, onCommit: saveMinimaxKey)
                .frame(maxWidth: 380)
            if hasSavedKey {
                HStack {
                    Button(L("Remover chave"), role: .destructive) {
                        removeSecret("MiniMax", raw: $minimaxAPIKey) {
                            try preferencesStore.setMinimaxAPIKey(nil)
                        }
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
            }
            Toggle(L("Região China (minimaxi.com)"), isOn: $minimaxRegionIsChina)
                .toggleStyle(.switch)
                .controlSize(.small)
                // A região é uma escolha binária: não há "valor vazio" que possa apagar
                // nada, então grava direto na troca.
                .onChange(of: minimaxRegionIsChina) { _, isChina in
                    preferencesStore.minimaxRegionRaw = isChina ? "china" : "global"
                }
        } details: {
            Text(L("A chave fica no Keychain desta máquina, nunca em texto puro."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var mimoPane: some View {
        ProviderPaneScaffold(
            providerId: "mimo",
            snapshot: appModel.snapshotsByProvider["mimo"],
            problem: appModel.errorsByProvider["mimo"],
            name: providerName("mimo"),
            status: mimoLoggedIn
                ? .connected(L("Sessão ativa — uso automático"))
                : .notConfigured(L("Sem sessão (usa estimativa manual)"))
        ) {
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
        } details: {
            if mimoLoggedIn {
                Text(L("A sessão sobrevive a reinícios e se renova sozinha quando o console expira — só pede login de novo se a conta Xiaomi deslogar de verdade."))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text(L("Estimativa manual (sem sessão):")).font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: Theme.Space.sm) {
                        AutoSaveField(placeholder: L("Franquia (Credits)"),
                                      text: $mimoAllowance,
                                      onCommit: saveMiMoAllowance)
                        AutoSaveField(placeholder: L("Usados"),
                                      text: $mimoUsed,
                                      onCommit: saveMiMoUsed)
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
        mimoAllowance = preferencesStore.mimoMonthlyAllowanceCredits
            .map { PreferencesFieldCommit.credits($0) } ?? ""
        mimoUsed = PreferencesFieldCommit.credits(preferencesStore.mimoUsedCredits)
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

    // MARK: - Auto-save

    /// Gravação de credencial. A decisão inteira ("grava ou ignora, e para que texto o
    /// campo volta") vive no `PreferencesFieldCommit`, que é coberto por teste; aqui só
    /// sobra o efeito colateral no Keychain.
    private func saveSecret(_ label: String, previous: String, raw: Binding<String>, _ save: (String) throws -> Void) {
        switch PreferencesFieldCommit.secret(raw: raw.wrappedValue, saved: previous) {
        case .ignored(let restore):
            raw.wrappedValue = restore
        case .commit(let value, let display):
            do {
                try save(value)
                raw.wrappedValue = display
                statusMessage = LF("%@: chave salva.", label)
            } catch {
                statusMessage = LF("%@: falha ao salvar chave — %@", label, error.localizedDescription)
            }
        }
    }

    /// Revogação explícita — o único caminho que apaga credencial. Fica atrás de um botão
    /// justamente porque a regra do auto-save recusa campo vazio: um clique consciente não
    /// é a mesma coisa que um blur acidental.
    private func removeSecret(_ label: String, raw: Binding<String>, _ delete: () throws -> Void) {
        do {
            try delete()
            raw.wrappedValue = ""
            statusMessage = LF("%@: chave removida.", label)
        } catch {
            statusMessage = LF("%@: falha ao remover chave — %@", label, error.localizedDescription)
        }
    }

    private func saveMinimaxKey() {
        saveSecret("MiniMax", previous: preferencesStore.minimaxAPIKey ?? "", raw: $minimaxAPIKey) {
            try preferencesStore.setMinimaxAPIKey($0)
        }
    }

    /// Franquia do MiMo. Antes isto era `= Double(mimoAllowance)` atrás de um botão: com o
    /// campo vazio virava `nil` e apagava a franquia salva.
    private func saveMiMoAllowance() {
        switch PreferencesFieldCommit.allowance(raw: mimoAllowance,
                                                saved: preferencesStore.mimoMonthlyAllowanceCredits) {
        case .ignored(let restore):
            mimoAllowance = restore
        case .commit(let value, let display):
            preferencesStore.mimoMonthlyAllowanceCredits = value
            mimoAllowance = display
        }
    }

    /// Créditos usados. Zero é legítimo aqui (mês recém-começado).
    private func saveMiMoUsed() {
        switch PreferencesFieldCommit.used(raw: mimoUsed, saved: preferencesStore.mimoUsedCredits) {
        case .ignored(let restore):
            mimoUsed = restore
        case .commit(let value, let display):
            preferencesStore.mimoUsedCredits = value
            mimoUsed = display
        }
    }

    private func logout(providerId: String, flag: Binding<Bool>) {
        try? tokenStore.delete(providerId: providerId)
        flag.wrappedValue = false
        statusMessage = L("Desconectado.")
    }
}


// MARK: - General pane

/// Ajustes gerais: pinos da barra de menu, alertas e atualização. Os intervalos de refresh
/// ficaram de fora de propósito: o intervalo por provedor do store não está ligado ao
/// Scheduler, então uma UI para ele mentiria.
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
        VStack(spacing: 0) {
            brandHero
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
                    // Sem pinos não há o que arrastar — o rodapé não promete reordenação.
                    Text(appModel.menuBarPins.isEmpty
                         ? L("Fixe janelas pelo alfinete no menu do OkTally — cada uma vira um número colorido na barra.")
                         : L("Arraste para reordenar. Fixe janelas pelo alfinete no menu do OkTally — cada uma vira um número colorido na barra."))
                        .font(.caption).foregroundStyle(.secondary)
                }

                // Quem impede o bug é o `.disabled` estar no `Group` dos detalhes, mais
                // abaixo — não esta separação. Ela é uma segunda barreira barata: enquanto o
                // toggle mestre estiver sozinho na própria `Section`, um `.disabled` aplicado
                // à seção dos detalhes não tem como alcançá-lo.
                //
                // O bug que isso previne: `.disabled(true)` propaga para os descendentes e
                // nenhum filho pode revertê-lo. Quando o toggle dividia a seção com os
                // detalhes, desligar as notificações apagava o próprio switch e não havia como
                // religá-las pela UI — só por `defaults write`.
                Section(L("Alertas")) {
                    Toggle(L("Notificações de cota"), isOn: $alertsEnabled)
                        .toggleStyle(.switch)
                        .onChange(of: alertsEnabled) { _, newValue in
                            preferencesStore.alertsEnabled = newValue
                        }
                }

                // Com título próprio: sem ele esta era a única seção sem cabeçalho da
                // tela e parecia um cartão órfão colado embaixo de "Alertas".
                Section(L("Limiares")) {
                    Group {
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
                                // Dentro do `Form` o título do TextField vira rótulo visível, e o
                                // "5.00" aparecia duas vezes ao lado do campo.
                                .labelsHidden()
                                .frame(width: 80)
                                .focused($lowBalanceFocused)
                                .onSubmit(saveLowBalance)
                                .onChange(of: lowBalanceFocused) { _, focused in
                                    // Auto-save também ao perder o foco: o botão "Salvar" saiu.
                                    if !focused { saveLowBalance() }
                                }
                            if savedFlash {
                                Text(L("Salvo")).font(.caption).foregroundStyle(Theme.accent).transition(.opacity)
                            }
                        }
                    }
                    .disabled(!alertsEnabled)
                    .opacity(alertsEnabled ? 1 : 0.5)
                }

                Section(L("Atualizações")) {
                    if let update = appModel.availableUpdate {
                        HStack(spacing: Theme.Space.sm) {
                            Label(LF("Versão %@ disponível", update.version), systemImage: "arrow.down.circle.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.Brand.heatOrange)
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
        }
        .onAppear {
            alertsEnabled = preferencesStore.alertsEnabled
            percentSteps = Set(preferencesStore.alertPercentThresholds)
            lowBalanceText = String(format: "%.2f", preferencesStore.alertLowBalanceThreshold)
        }
    }

    /// A faixa de destaque do painel Geral — e o único lugar do app onde a MARCA aparece
    /// escrita. O símbolo já estava no header do popover; a grafia não estava em lugar
    /// nenhum, e Preferências é onde ela cabe sem virar enfeite: é a tela do app sobre o
    /// app.
    ///
    /// Do lado direito, o conteúdo que faz a faixa valer mais que um logo: a barra de
    /// menu DE VERDADE, renderizada com os mesmos segmentos que o `MenuBarExtra` usa.
    /// A primeira seção do `Form` logo abaixo é justamente a que configura esses pinos —
    /// agora se vê o efeito da configuração na mesma tela em que ela é feita.
    private var brandHero: some View {
        PaneHero(tint: Theme.accent) {
            HStack(spacing: Theme.Space.md) {
                BrandMark(size: 30)
                    .foregroundStyle(Theme.onHero)
                VStack(alignment: .leading, spacing: 2) {
                    Text("OkTally")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.onHero)
                    Text(LF("versão %@", appModel.currentVersion))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.onHero.opacity(0.75))
                }
            }
        } trailing: {
            VStack(alignment: .trailing, spacing: 5) {
                SectionHeader(L("Na barra de menu"), onHero: true)
                // Pílula quase preta: é a cor real da barra de menu no escuro, e sem ela
                // os números coloridos ficariam sobre ciano saturado, que é exatamente o
                // fundo que eles nunca têm.
                Group {
                    if appModel.menuBarSegments.isEmpty {
                        Text(L("automático"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.onHero.opacity(0.75))
                    } else {
                        MenuBarLabelView(segments: appModel.menuBarSegments)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                    .fill(Color.black.opacity(0.55)))
            }
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
            IconChip(glyph: ProviderPalette.glyph(forId: pin.providerId),
                     color: ProviderPalette.color(for: pin.providerId),
                     size: 18)
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
        .draggable(MenuBarPinTransfer(stored: pin.stored))
        // Tipo próprio em vez de `String`: texto de outro app não marca mais a linha como
        // alvo válido, e o id interno do pino não vaza como texto para fora do app.
        .dropDestination(for: MenuBarPinTransfer.self) { items, _ in
            guard let dragged = items.first else { return false }
            return movePin(stored: dragged.stored, toPositionOf: pin)
        }
    }

    /// Move o pino arrastado para a posição do alvo. A regra vive em `PinReorder`, que é
    /// coberta por teste — o cálculo do índice aqui dentro já saiu errado uma vez.
    private func movePin(stored: String, toPositionOf target: AppModel.MenuBarPin) -> Bool {
        guard let order = PinReorder.reordered(appModel.menuBarPins.map(\.stored),
                                               dragging: stored,
                                               onto: target.stored) else { return false }
        appModel.menuBarPins = order.compactMap { AppModel.MenuBarPin(stored: $0) }
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
                // `AnyShapeStyle` porque os dois ramos têm tipos diferentes desde que as
                // superfícies viraram tokens dependentes do esquema (`ThemeColor`).
                .background(Capsule().fill(selected ? AnyShapeStyle(Theme.accent.opacity(0.25)) : AnyShapeStyle(Theme.surface())))
                .overlay(Capsule().strokeBorder(selected ? AnyShapeStyle(Theme.accent.opacity(0.6)) : AnyShapeStyle(Theme.border())))
                .foregroundStyle(selected ? Theme.accent : Color.secondary)
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
