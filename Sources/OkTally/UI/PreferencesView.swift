// Sources/OkTally/UI/PreferencesView.swift
import SwiftUI
import AppKit

enum PreferencesPane: Hashable {
    case general
    case provider(String)
}

/// Conta sendo adicionada: ainda não está na lista, só tem o id reservado. Vira conta de
/// verdade quando o login grava a credencial e `AccountEnrollment.finish` aprova.
struct AccountDraft: Equatable {
    let id: String
    let kind: AccountKind
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
    /// Avisa quem cuida do painel do notch que a preferência mudou. Opcional porque o
    /// harness de render monta esta tela sem app vivo — lá não há painel para reavaliar.
    var onNotchPreferenceChanged: (() -> Void)?

    @State private var pane: PreferencesPane = .general

    // Estado por CONTA (chave = id da instância). Antes eram booleanos soltos por
    // provedor, o que não sobrevive a duas contas do mesmo tipo.
    /// Contas OAuth com token no Keychain.
    @State private var loggedIn: Set<String> = []
    @State private var claudeSessions: [String: ManualCodeSession] = [:]
    @State private var pastedCodes: [String: String] = [:]
    @State private var deviceCodes: [String: DeviceCodeInfo] = [:]
    /// Texto dos campos de chave de API, por conta.
    @State private var apiKeyFields: [String: String] = [:]
    @State private var minimaxChina: [String: Bool] = [:]
    @State private var nicknameFields: [String: String] = [:]
    /// Conta aguardando a confirmação de remoção.
    @State private var pendingRemoval: String?
    /// Conta sendo adicionada (menu "+").
    @State private var draft: AccountDraft?
    /// Logins do Cursor esperando o navegador (poll em andamento), por conta.
    @State private var cursorPolls: [String: Task<Void, Never>] = [:]

    @State private var mimoAllowance: String = ""
    @State private var mimoUsed: String = ""
    @State private var mimoLoggedIn = false
    @State private var statusMessage: String = ""

    /// Ordem da sidebar: a que o dono arrumou, persistida em `AppModel`. Sem
    /// arrasto salvo, o modelo cai na lista histórica das Preferências.
    private var providerIds: [String] { appModel.orderedProviders.map(\.id) }

    var body: some View {
        NavigationSplitView {
            List(selection: $pane) {
                Label(L("Geral"), systemImage: "slider.horizontal.3")
                    .tag(PreferencesPane.general)
                Section {
                    ForEach(providerIds, id: \.self) { id in
                        sidebarRow(id)
                            .tag(PreferencesPane.provider(id))
                            .contentShape(Rectangle())
                            .draggable(ProviderOrderTransfer(id: id))
                            .dropDestination(for: ProviderOrderTransfer.self) { items, _ in
                                guard let dragged = items.first else { return false }
                                return appModel.moveProvider(dragging: dragged.id, onto: id)
                            }
                    }
                    if let draft {
                        ProviderSidebarRow(
                            providerId: draft.id,
                            name: LF("Nova conta · %@", Self.kindName(draft.kind)),
                            statusColor: Color.secondary.opacity(0.35),
                            statusHelp: L("Não configurado")
                        )
                        .tag(PreferencesPane.provider(draft.id))
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
                        addAccountMenu
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
        } detail: {
            // Geral e os panes de provider são `Form` agrupados, que já rolam sozinhos —
            // o `ScrollView` que os panes de provider tinham daria rolagem aninhada.
            if case .general = pane {
                GeneralPane(appModel: appModel, preferencesStore: preferencesStore,
                            providerName: providerName,
                            onNotchPreferenceChanged: onNotchPreferenceChanged)
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
        .onChange(of: appModel.accounts) { _, _ in
            load()
        }
        .confirmationDialog(L("Remover esta conta?"),
                            isPresented: Binding(get: { pendingRemoval != nil },
                                                 set: { if !$0 { pendingRemoval = nil } }),
                            titleVisibility: .visible) {
            Button(L("Remover conta"), role: .destructive) {
                if let id = pendingRemoval { removeAccount(id) }
                pendingRemoval = nil
            }
            Button(L("Cancelar"), role: .cancel) { pendingRemoval = nil }
        } message: {
            Text(L("Remove a conta, o histórico e os pins. Não dá para desfazer."))
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

    /// "+" no cabeçalho das contas. Some enquanto nenhum tipo aceita segunda conta.
    @ViewBuilder private var addAccountMenu: some View {
        if !AccountKind.addableKinds.isEmpty {
            Menu {
                ForEach(AccountKind.addableKinds, id: \.self) { kind in
                    Button(Self.kindName(kind)) { beginAddAccount(kind) }
                }
            } label: {
                Image(systemName: "plus")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(L("Adicionar conta"))
        }
    }

    private func sidebarRow(_ id: String) -> some View {
        ProviderSidebarRow(
            providerId: id,
            name: providerName(id),
            statusColor: statusDotColor(id),
            statusHelp: statusDotHelp(id),
            subtitle: account(id)?.email
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

    private func account(_ id: String) -> AccountInstance? {
        appModel.accounts.first { $0.id == id }
    }

    /// Nome do TIPO, para o menu "+" e mensagens — o mesmo dos provedores legados.
    static func kindName(_ kind: AccountKind) -> String {
        switch kind {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .supergrok: return "SuperGrok"
        case .cursor: return "Cursor"
        case .grokbot: return "GrokBot"
        case .copilot: return "GitHub Copilot"
        case .antigravity: return "Antigravity"
        case .openrouter: return "OpenRouter"
        case .minimax: return "MiniMax"
        case .opencode: return "OpenCode"
        case .mimo: return "MiMo"
        }
    }

    private func isConfigured(_ id: String) -> Bool {
        switch AccountPaneRouting.route(for: id) {
        case .claude(let id), .codex(let id), .supergrok(let id):
            return loggedIn.contains(id)
        case .cursor(let id):
            // A conta legada lê a sessão do app Cursor sozinha.
            return AccountID.isLegacy(id) || loggedIn.contains(id)
        case .grokbot(let id):
            let cursorId = AccountPaneRouting.accountId(forProviderId: id)
            return AccountID.isLegacy(cursorId) || loggedIn.contains(cursorId)
        case .copilot:
            return CopilotTokenReader().firstToken() != nil
        case .antigravity(let id):
            return AccountID.isLegacy(id) ? AntigravityTokenReader().readTokens() != nil : loggedIn.contains(id)
        case .minimax(let id), .apiKey(let id, _):
            return !(apiKeyFields[id] ?? "").isEmpty
        case .mimo:
            return mimoLoggedIn || !mimoAllowance.isEmpty
        case .unknown:
            return false
        }
    }

    // MARK: - Detail routing

    @ViewBuilder private var detailContent: some View {
        switch pane {
        case .general:
            EmptyView() // tratado no branch anterior do detalhe, por rolar sozinho
        case .provider(let id) where draft?.id == id:
            if let draft { draftPane(draft) }
        case .provider(let id):
            switch AccountPaneRouting.route(for: id) {
            case .claude(let id): claudePane(id)
            case .codex(let id): codexPane(id)
            case .supergrok(let id): superGrokPane(id)
            case .cursor(let id): cursorPane(id)
            case .grokbot(let id): grokBotPane(id)
            case .copilot: copilotPane
            case .antigravity(let id): antigravityPane(id)
            case .minimax(let id): minimaxPane(id)
            case .apiKey(let id, _): keyPane(id)
            case .mimo: mimoPane
            case .unknown: EmptyView()
            }
        }
    }

    // MARK: - Seção "Conta"

    /// E-mail (quando conhecido), apelido e remoção. O apelido grava no Enter e ao perder
    /// o foco, como o resto da tela; vazio apaga o apelido — diferente das chaves, aqui
    /// "nada" é um valor legítimo.
    @ViewBuilder private func accountSection(_ id: String) -> some View {
        if AccountPaneRouting.showsAccountSection(id), let account = account(id) {
            if let email = account.email {
                LabeledContent(L("E-mail")) {
                    Text(email).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            AutoSaveField(placeholder: L("Apelido (opcional)"),
                          text: Binding(get: { nicknameFields[id] ?? account.nickname ?? "" },
                                        set: { nicknameFields[id] = $0 }),
                          onCommit: { appModel.renameAccount(id: id, nickname: nicknameFields[id] ?? account.nickname) })
                .frame(maxWidth: 380)
            if AccountPaneRouting.canRemove(id) {
                HStack {
                    Button(L("Remover conta…"), role: .destructive) { pendingRemoval = id }
                        .buttonStyle(.bordered)
                    Spacer()
                }
            }
        }
    }

    private func removeAccount(_ id: String) {
        do {
            try appModel.removeAccount(id: id)
            pane = .general
            statusMessage = ""
            load()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    // MARK: - Provider panes

    private func oauthStatus(_ id: String) -> ProviderPaneStatus {
        loggedIn.contains(id) ? .connected(L("Conectado")) : .notConfigured(L("Não conectado"))
    }

    private func claudePane(_ id: String) -> some View {
        ProviderPaneScaffold(
            providerId: id,
            snapshot: appModel.snapshotsByProvider[id],
            problem: appModel.errorsByProvider[id],
            name: providerName(id),
            status: oauthStatus(id)
        ) {
            HStack {
                if loggedIn.contains(id) {
                    Button(L("Sair")) { logout(providerId: id); claudeSessions[id] = nil }
                        .buttonStyle(.bordered)
                } else {
                    Button(L("Entrar…")) { beginClaudeLogin(id) }
                        .buttonStyle(.borderedProminent)
                    // O login do Claude Code CLI é um só na máquina: importar só faz
                    // sentido para a conta legada (é a única que ele semeia).
                    if AccountID.isLegacy(id) {
                        Button(L("Importar do Claude Code")) {
                            statusMessage = onImportClaudeLegacy() ? L("Login importado.") : L("Nenhum login do Claude Code encontrado.")
                            refreshLoggedIn(id)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                Spacer()
            }
            // O código colado continua sendo um passo da conexão — fica na mesma seção
            // dos botões para não virar um detalhe descolado do fluxo.
            claudeCodeEntry(id)
        } details: {
            Text(L("O uso de cota vem da conta; o volume em tokens é estimado dos transcritos locais."))
                .font(.caption).foregroundStyle(.secondary)
        } account: {
            accountSection(id)
        }
    }

    @ViewBuilder private func claudeCodeEntry(_ id: String) -> some View {
        if claudeSessions[id] != nil {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text(L("Autorize no navegador, copie o código e cole abaixo:"))
                    .font(.caption).foregroundStyle(.secondary)
                TextField("CÓDIGO#STATE", text: Binding(get: { pastedCodes[id] ?? "" }, set: { pastedCodes[id] = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                HStack {
                    Button(L("Concluir")) { completeClaudeLogin(id) }
                        .buttonStyle(.borderedProminent)
                        .disabled((pastedCodes[id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                    Button(L("Cancelar")) { claudeSessions[id] = nil; pastedCodes[id] = nil; statusMessage = "" }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private func codexPane(_ id: String) -> some View {
        ProviderPaneScaffold(
            providerId: id,
            snapshot: appModel.snapshotsByProvider[id],
            problem: appModel.errorsByProvider[id],
            name: providerName(id),
            status: oauthStatus(id)
        ) {
            if loggedIn.contains(id) {
                Button(L("Sair")) { logout(providerId: id) }.buttonStyle(.bordered)
            } else {
                Button(L("Entrar…")) { login(config: CodexOAuth.config.forInstance(id), id: id) }
                    .buttonStyle(.borderedProminent)
            }
        } details: {
            Text(L("Estatísticas de uso vêm da API da conta."))
                .font(.caption).foregroundStyle(.secondary)
        } account: {
            accountSection(id)
        }
    }

    private func superGrokPane(_ id: String) -> some View {
        ProviderPaneScaffold(
            providerId: id,
            snapshot: appModel.snapshotsByProvider[id],
            problem: appModel.errorsByProvider[id],
            name: providerName(id),
            status: oauthStatus(id)
        ) {
            if loggedIn.contains(id) {
                Button(L("Sair")) { logout(providerId: id) }
                    .buttonStyle(.bordered)
            } else {
                Button(L("Entrar…")) { loginSuperGrok(id) }.buttonStyle(.borderedProminent)
            }
        } details: {
            if let info = deviceCodes[id] {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(LF("Abra %@ e digite:", info.verificationURL.absoluteString))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(info.userCode).font(.title3.monospaced()).textSelection(.enabled)
                }
            } else {
                Text(L("O login usa código de dispositivo: o navegador abre e você digita o código mostrado aqui."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        } account: {
            accountSection(id)
        }
    }

    @ViewBuilder private func cursorPane(_ id: String) -> some View {
        if AccountID.isLegacy(id) {
            ProviderPaneScaffold(
                providerId: id,
                snapshot: appModel.snapshotsByProvider[id],
                problem: appModel.errorsByProvider[id],
                name: providerName(id),
                status: .connected(L("Lê a sessão do app Cursor automaticamente"))
            ) {
                Text(L("Nada a configurar — se o app Cursor estiver logado nesta máquina, o uso aparece sozinho."))
                    .font(.caption).foregroundStyle(.secondary)
            } details: {
                EmptyView()
            } account: {
                accountSection(id)
            }
        } else {
            ProviderPaneScaffold(
                providerId: id,
                snapshot: appModel.snapshotsByProvider[id],
                problem: appModel.errorsByProvider[id],
                name: providerName(id),
                status: oauthStatus(id)
            ) {
                HStack {
                    if loggedIn.contains(id) {
                        Button(L("Sair")) { logout(providerId: id) }.buttonStyle(.bordered)
                    } else {
                        cursorLoginButton(id)
                    }
                    Spacer()
                }
            } details: {
                Text(L("Sessão própria do OkTally — trocar de conta no Cursor não afeta esta conta. A sessão dura cerca de 60 dias; depois, é só entrar de novo."))
                    .font(.caption).foregroundStyle(.secondary)
            } account: {
                accountSection(id)
            }
        }
    }

    private func grokBotPane(_ id: String) -> some View {
        let cursorId = AccountPaneRouting.accountId(forProviderId: id)
        let isLegacy = AccountID.isLegacy(cursorId)
        return ProviderPaneScaffold(
            providerId: id,
            snapshot: appModel.snapshotsByProvider[id],
            problem: appModel.errorsByProvider[id],
            name: providerName(id),
            status: isLegacy
                ? .connected(L("Lê a sessão do app Cursor automaticamente"))
                : oauthStatus(cursorId)
        ) {
            Text(isLegacy
                 ? L("Nada a configurar — se o app Cursor estiver logado nesta máquina, o uso aparece sozinho.")
                 : LF("Segue a conta %@ — login, apelido e remoção ficam lá.", providerName(cursorId)))
                .font(.caption).foregroundStyle(.secondary)
        } details: {
            EmptyView()
        }
    }

    /// Botão do login próprio do Cursor. Enquanto o navegador não conclui, vira um
    /// indicador com "Cancelar".
    @ViewBuilder private func cursorLoginButton(_ id: String) -> some View {
        if cursorPolls[id] != nil {
            ProgressView().controlSize(.small)
            Text(L("Aguardando o login no navegador…")).font(.caption).foregroundStyle(.secondary)
            Button(L("Cancelar")) { cancelCursorLogin(id) }.buttonStyle(.bordered)
        } else {
            Button(L("Entrar no navegador…")) { loginCursor(id) }.buttonStyle(.borderedProminent)
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
        } account: {
            accountSection("copilot")
        }
    }

    @ViewBuilder private func antigravityPane(_ id: String) -> some View {
        if AccountID.isLegacy(id) {
            let detected = AntigravityTokenReader().readTokens() != nil
            ProviderPaneScaffold(
                providerId: id,
                snapshot: appModel.snapshotsByProvider[id],
                problem: appModel.errorsByProvider[id],
                name: providerName(id),
                status: detected
                    ? .connected(L("Login do IDE Antigravity detectado"))
                    : .notConfigured(L("Nenhum login do Antigravity encontrado"))
            ) {
                Text(L("Nada a configurar — detectado automaticamente a partir do login do IDE Antigravity neste Mac."))
                    .font(.caption).foregroundStyle(.secondary)
            } details: {
                EmptyView()
            } account: {
                accountSection(id)
            }
        } else {
            // Conta extra: login Google próprio do OkTally, independente do IDE.
            ProviderPaneScaffold(
                providerId: id,
                snapshot: appModel.snapshotsByProvider[id],
                problem: appModel.errorsByProvider[id],
                name: providerName(id),
                status: oauthStatus(id)
            ) {
                if loggedIn.contains(id) {
                    Button(L("Sair")) { logout(providerId: id) }.buttonStyle(.bordered)
                } else {
                    Button(L("Entrar…")) { login(config: AntigravityOAuth.config.forInstance(id), id: id) }
                        .buttonStyle(.borderedProminent)
                }
            } details: {
                Text(L("Login Google próprio do OkTally, separado do IDE Antigravity."))
                    .font(.caption).foregroundStyle(.secondary)
            } account: {
                accountSection(id)
            }
        }
    }

    /// Painel de chave de API. O botão "Salvar" saiu: o campo grava no Enter e ao perder
    /// o foco, e `saveSecret` recusa campo vazio ou inalterado para que um blur acidental
    /// não apague a chave que está no Keychain.
    private func keyPane(_ id: String) -> some View {
        let hasSavedKey = !(savedAPIKey(id) ?? "").isEmpty
        return ProviderPaneScaffold(
            providerId: id,
            snapshot: appModel.snapshotsByProvider[id],
            problem: appModel.errorsByProvider[id],
            name: providerName(id),
            status: hasSavedKey ? .connected(L("Chave salva")) : .notConfigured(L("Sem chave"))
        ) {
            AutoSaveField(placeholder: "API Key", text: apiKeyBinding(id), isSecure: true, onCommit: { saveAPIKey(id) })
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
                    Button(L("Remover chave"), role: .destructive) { removeAPIKey(id) }
                        .buttonStyle(.bordered)
                    Spacer()
                }
            }
        } details: {
            Text(L("A chave fica no Keychain desta máquina, nunca em texto puro."))
                .font(.caption).foregroundStyle(.secondary)
        } account: {
            accountSection(id)
        }
    }

    private func minimaxPane(_ id: String) -> some View {
        // Mesma regra do `keyPane`: pill e botão seguem o Keychain, não o texto do campo.
        let hasSavedKey = !(savedAPIKey(id) ?? "").isEmpty
        return ProviderPaneScaffold(
            providerId: id,
            snapshot: appModel.snapshotsByProvider[id],
            problem: appModel.errorsByProvider[id],
            name: providerName(id),
            status: hasSavedKey ? .connected(L("Chave salva")) : .notConfigured(L("Sem chave"))
        ) {
            AutoSaveField(placeholder: "API Key", text: apiKeyBinding(id), isSecure: true, onCommit: { saveAPIKey(id) })
                .frame(maxWidth: 380)
            if hasSavedKey {
                HStack {
                    Button(L("Remover chave"), role: .destructive) { removeAPIKey(id) }
                        .buttonStyle(.bordered)
                    Spacer()
                }
            }
            Toggle(L("Região China (minimaxi.com)"), isOn: Binding(
                get: { minimaxChina[id] ?? false },
                // A região é uma escolha binária: não há "valor vazio" que possa apagar
                // nada, então grava direto na troca.
                set: { isChina in
                    minimaxChina[id] = isChina
                    setMinimaxRegion(isChina ? "china" : "global", id: id)
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
        } details: {
            Text(L("A chave fica no Keychain desta máquina, nunca em texto puro."))
                .font(.caption).foregroundStyle(.secondary)
        } account: {
            accountSection(id)
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
        } account: {
            accountSection("mimo")
        }
    }

    // MARK: - State loading

    private func load() {
        for account in appModel.accounts {
            let id = account.id
            switch account.kind {
            case .claude, .codex, .supergrok, .cursor, .antigravity:
                refreshLoggedIn(id)
            case .openrouter, .opencode:
                apiKeyFields[id] = savedAPIKey(id) ?? ""
            case .minimax:
                apiKeyFields[id] = savedAPIKey(id) ?? ""
                minimaxChina[id] = minimaxRegion(id) == "china"
            case .grokbot, .copilot, .mimo:
                break
            }
            nicknameFields[id] = account.nickname ?? ""
        }
        mimoAllowance = preferencesStore.mimoMonthlyAllowanceCredits
            .map { PreferencesFieldCommit.credits($0) } ?? ""
        mimoUsed = PreferencesFieldCommit.credits(preferencesStore.mimoUsedCredits)
        mimoLoggedIn = mimoSessionStore.isLoggedIn
    }

    private func refreshLoggedIn(_ id: String) {
        if tokenStore.load(providerId: id) != nil {
            loggedIn.insert(id)
        } else {
            loggedIn.remove(id)
        }
    }

    // MARK: - Chaves de API por conta

    private func apiKeyBinding(_ id: String) -> Binding<String> {
        Binding(get: { apiKeyFields[id] ?? "" }, set: { apiKeyFields[id] = $0 })
    }

    private func savedAPIKey(_ id: String) -> String? {
        preferencesStore.apiKey(instanceId: id)
    }

    private func storeAPIKey(_ value: String?, id: String) throws {
        try preferencesStore.setAPIKey(value, instanceId: id)
    }

    private func minimaxRegion(_ id: String) -> String? {
        preferencesStore.minimaxRegionRaw(instanceId: id)
    }

    private func setMinimaxRegion(_ raw: String, id: String) {
        preferencesStore.setMinimaxRegionRaw(raw, instanceId: id)
    }

    private func saveAPIKey(_ id: String) {
        saveSecret(providerName(id), previous: savedAPIKey(id) ?? "", raw: apiKeyBinding(id)) {
            try storeAPIKey($0, id: id)
        }
    }

    private func removeAPIKey(_ id: String) {
        removeSecret(providerName(id), raw: apiKeyBinding(id)) {
            try storeAPIKey(nil, id: id)
        }
    }

    // MARK: - Login flows

    private func login(config: OAuthConfig, id: String) {
        statusMessage = L("Abrindo o navegador…")
        Task {
            do {
                _ = try await browserFlow.login(config: config)
                await MainActor.run { afterLogin(id) }
            } catch {
                await MainActor.run { statusMessage = error.localizedDescription }
            }
        }
    }

    private func beginClaudeLogin(_ id: String) {
        pastedCodes[id] = ""
        claudeSessions[id] = manualFlow.begin(config: ClaudeOAuth.config.forInstance(id))
        statusMessage = L("Abrindo o navegador — copie o código e cole aqui.")
    }

    private func completeClaudeLogin(_ id: String) {
        guard let session = claudeSessions[id] else { return }
        let pasted = pastedCodes[id] ?? ""
        statusMessage = L("Validando código…")
        Task {
            do {
                _ = try await manualFlow.complete(pasted: pasted, session: session)
                await MainActor.run {
                    claudeSessions[id] = nil; pastedCodes[id] = nil
                    afterLogin(id)
                }
            } catch {
                await MainActor.run { statusMessage = error.localizedDescription }
            }
        }
    }

    private func loginCursor(_ id: String) {
        let flow = CursorDeepLoginFlow(tokenStore: tokenStore)
        let start = flow.begin()
        flow.open(start)
        statusMessage = L("Conclua o login no navegador — o OkTally espera por até 20 minutos.")
        cursorPolls[id] = Task { @MainActor in
            do {
                _ = try await flow.poll(start, instanceId: id)
                cursorPolls[id] = nil
                afterLogin(id)
            } catch is CancellationError {
                cursorPolls[id] = nil
            } catch {
                cursorPolls[id] = nil
                statusMessage = error.localizedDescription
            }
        }
    }

    private func cancelCursorLogin(_ id: String) {
        cursorPolls[id]?.cancel()
        cursorPolls[id] = nil
        statusMessage = ""
    }

    private func loginSuperGrok(_ id: String) {
        statusMessage = L("Solicitando código de dispositivo…")
        let config = SuperGrokOAuth.config.forInstance(id)
        Task {
            do {
                let request = try await deviceCodeFlow.requestDeviceCode(config: config)
                await MainActor.run {
                    deviceCodes[id] = request.info
                    statusMessage = L("Digite o código no navegador para continuar.")
                    NSWorkspace.shared.open(request.info.verificationURL)
                }
                _ = try await deviceCodeFlow.poll(request, config: config)
                await MainActor.run { deviceCodes[id] = nil; afterLogin(id) }
            } catch {
                await MainActor.run { deviceCodes[id] = nil; statusMessage = error.localizedDescription }
            }
        }
    }

    // MARK: - Adicionar conta

    /// Painel do rascunho: os mesmos botões de login do tipo, gravando sob o id reservado.
    private func draftPane(_ draft: AccountDraft) -> some View {
        let id = draft.id
        return ProviderPaneScaffold(
            providerId: id,
            name: LF("Nova conta · %@", Self.kindName(draft.kind)),
            status: .notConfigured(L("Faça login para adicionar esta conta"))
        ) {
            HStack {
                draftLoginButton(draft)
                Button(L("Cancelar")) { cancelDraft() }
                    .buttonStyle(.bordered)
                Spacer()
            }
            if draft.kind == .openrouter || draft.kind == .minimax {
                AutoSaveField(placeholder: "API Key", text: apiKeyBinding(id), isSecure: true,
                              onCommit: { saveDraftKey(id) })
                    .frame(maxWidth: 380)
            }
            if draft.kind == .minimax {
                Toggle(L("Região China (minimaxi.com)"), isOn: Binding(
                    get: { minimaxChina[id] ?? false },
                    set: { isChina in
                        minimaxChina[id] = isChina
                        setMinimaxRegion(isChina ? "china" : "global", id: id)
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            if draft.kind == .antigravity {
                // Aviso pedido pelo dono antes de liberar o login Google fora do IDE.
                Label(L("Login direto na Google fora do IDE pode violar os termos do Antigravity; use por sua conta."),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.Brand.heatOrange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if draft.kind == .claude { claudeCodeEntry(id) }
            if draft.kind == .supergrok, let info = deviceCodes[id] {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(LF("Abra %@ e digite:", info.verificationURL.absoluteString))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(info.userCode).font(.title3.monospaced()).textSelection(.enabled)
                }
            }
        } details: {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                ForEach(draftNotes(draft.kind), id: \.self) { Text($0) }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Avisos do painel de adicionar, por tipo.
    private func draftNotes(_ kind: AccountKind) -> [String] {
        var notes: [String] = []
        if kind == .cursor {
            notes.append(L("Sessão própria do OkTally — trocar de conta no Cursor não afeta esta conta."))
        }
        switch kind {
        case .claude, .codex, .supergrok, .antigravity, .cursor:
            notes.append(L("Entre com a OUTRA conta. Se o navegador já estiver logado na conta atual, troque de conta (ou use uma janela anônima) antes de autorizar."))
        default:
            break
        }
        if kind == .codex {
            notes.append(L("O login do Codex usa a porta 1455 — feche o Codex CLI se ele estiver fazendo login ao mesmo tempo."))
        }
        if kind == .openrouter || kind == .minimax {
            notes.append(L("Cole a chave da outra conta e tecle Enter. A chave fica no Keychain desta máquina; a mesma chave duas vezes não é adicionada."))
        }
        notes.append(L("A conta nova aparece ao lado da atual, rotulada pelo e-mail. Se for a mesma conta, nada é adicionado."))
        return notes
    }

    @ViewBuilder private func draftLoginButton(_ draft: AccountDraft) -> some View {
        let id = draft.id
        switch draft.kind {
        case .claude:
            Button(L("Entrar…")) { beginClaudeLogin(id) }.buttonStyle(.borderedProminent)
        case .codex:
            Button(L("Entrar…")) { login(config: CodexOAuth.config.forInstance(id), id: id) }.buttonStyle(.borderedProminent)
        case .supergrok:
            Button(L("Entrar…")) { loginSuperGrok(id) }.buttonStyle(.borderedProminent)
        case .antigravity:
            Button(L("Entrar com Google…")) { login(config: AntigravityOAuth.config.forInstance(id), id: id) }
                .buttonStyle(.borderedProminent)
        case .cursor:
            cursorLoginButton(id)
        default:
            EmptyView()
        }
    }

    /// Chave colada num rascunho: grava sob o id reservado e, se gravou de fato, segue o
    /// mesmo caminho de um login concluído.
    private func saveDraftKey(_ id: String) {
        let before = savedAPIKey(id) ?? ""
        saveAPIKey(id)
        let after = savedAPIKey(id) ?? ""
        if !after.isEmpty, after != before { afterLogin(id) }
    }

    private func beginAddAccount(_ kind: AccountKind) {
        if draft != nil { cancelDraft() }
        let enrollment = AccountEnrollment(model: appModel)
        let next = AccountDraft(id: enrollment.beginDraft(kind: kind), kind: kind)
        draft = next
        pane = .provider(next.id)
        statusMessage = ""
    }

    private func cancelDraft() {
        guard let current = draft else { return }
        cursorPolls[current.id]?.cancel()
        cursorPolls[current.id] = nil
        AccountEnrollment(model: appModel).abandon(draftId: current.id, kind: current.kind)
        claudeSessions[current.id] = nil
        pastedCodes[current.id] = nil
        deviceCodes[current.id] = nil
        apiKeyFields[current.id] = nil
        loggedIn.remove(current.id)
        draft = nil
        pane = .general
        statusMessage = ""
    }

    /// Login concluído. Numa conta existente só marca conectado; num rascunho, é a hora
    /// de descobrir quem é a conta e decidir se entra.
    private func afterLogin(_ id: String) {
        loggedIn.insert(id)
        guard let current = draft, current.id == id else {
            statusMessage = L("Conectado.")
            return
        }
        statusMessage = L("Identificando a conta…")
        Task { @MainActor in
            let result = await AccountEnrollment(model: appModel).finish(draftId: current.id, kind: current.kind)
            switch result {
            case .committed:
                draft = nil
                pane = .provider(current.id)
                load()
                statusMessage = appModel.accounts.first(where: { $0.id == current.id })?.email == nil
                    ? L("Conta adicionada — dê um apelido para distinguir das outras.")
                    : L("Conta adicionada.")
            case .duplicate(let email):
                // O rascunho continua aberto: o dono pode trocar de conta no navegador e
                // tentar de novo, ou cancelar.
                loggedIn.remove(current.id)
                apiKeyFields[current.id] = ""
                statusMessage = email.map { LF("%@ já está no OkTally — nada foi adicionado.", $0) }
                    ?? L("Esta conta já está no OkTally — nada foi adicionado.")
            case .failed:
                loggedIn.remove(current.id)
                statusMessage = L("Não foi possível adicionar a conta.")
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

    private func logout(providerId: String) {
        try? tokenStore.delete(providerId: providerId)
        loggedIn.remove(providerId)
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
    var onNotchPreferenceChanged: (() -> Void)?

    @State private var alertsEnabled = true
    @State private var notchHUDEnabled = true
    @State private var percentSteps: Set<Double> = []
    @State private var lowBalanceText = ""
    @State private var savedFlash = false
    /// Texto EM EDIÇÃO do percentual de cada parada, por id.
    ///
    /// O campo não pode ler direto do modelo: a escala se reordena a cada gravação, e
    /// gravar a cada tecla faria a linha saltar de posição no meio da digitação de "85"
    /// (o "8" sozinho já a mandaria para o começo). O rascunho segura o texto até o
    /// Enter ou a perda de foco, que é a mesma regra de auto-save do resto da tela.
    @State private var percentDrafts: [UUID: String] = [:]
    @FocusState private var lowBalanceFocused: Bool
    @FocusState private var focusedStop: UUID?

    /// 50/70/80/90/100 — nenhuma migração necessária: `alertPercentThresholds` já persiste
    /// uma lista arbitrária de frações e o `AlertEngine` mapeia qualquer lista, então quem
    /// tinha 70/90/100 salvo continua com 70/90/100.
    private static let percentOptions: [Double] = [0.5, 0.7, 0.8, 0.9, 1.0]

    /// Mesma ordem da sidebar — a que o dono arrumou, ou a lista histórica das
    /// Preferências quando ele ainda não tocou em nada.
    private var providerIds: [String] { appModel.orderedProviders.map(\.id) }

    var body: some View {
        VStack(spacing: 0) {
            brandHero
            Form {
                // Primeira seção da tela de propósito: é a única cujo efeito se vê na
                // hora, e o dono é visual — a barra de preview logo abaixo do herói é o
                // que faz a escala ser entendida sem ler uma linha de texto.
                Section(L("Escala de cores")) {
                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                        UsageScalePreviewBar(scale: appModel.usageColorScale)
                        Text(L("A cor de cada percentual RESTANTE. Entre duas paradas a cor migra suavemente — a barra acima é a escala inteira, ao vivo."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(appModel.usageColorScale.stops) { stop in
                        stopRow(stop)
                    }
                    HStack(spacing: Theme.Space.sm) {
                        Button(L("Adicionar parada")) {
                            appModel.usageColorScale = appModel.usageColorScale.addingStop()
                        }
                        .controlSize(.small)
                        Spacer()
                        Button(L("Restaurar padrão")) {
                            appModel.usageColorScale = .standard
                            percentDrafts = [:]
                        }
                        .controlSize(.small)
                    }
                }

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
                         ? L("Fixe janelas pelo alfinete no menu do OkTally — os pinos são o conjunto que os seletores abaixo usam no modo automático.")
                         : L("Arraste para reordenar. Os pinos são o conjunto que os seletores abaixo usam no modo automático."))
                        .font(.caption).foregroundStyle(.secondary)

                    // Os cinco lugares onde um número do app aparece o dia inteiro. Cada um
                    // escolhe a sua cota; "Automático" mantém a regra antiga (a mais
                    // apertada) e continua sendo o padrão.
                    slotPicker(L("Valor na barra"), selection: $appModel.menuBarSlot)
                    slotPicker(L("Notch — lado esquerdo"), selection: $appModel.notchLeadingSlot)
                    slotPicker(L("Notch — lado direito"), selection: $appModel.notchTrailingSlot)
                    slotPicker(L("Notch — barra inferior"), selection: $appModel.notchBottomSlot)
                    // O card-herói do popover — o bloco grande em gradiente no topo do
                    // menu, antes travado na pior cota. É o pedido do dono: "eu não
                    // consigo trocar esse card principal".
                    slotPicker(L("Destaque do menu"), selection: $appModel.popoverHeroSlot)
                    forecastSlotPicker(selection: $appModel.forecastSlot)
                    Text(L("A estimativa usa a variação líquida observada nas últimas 24 horas e não depende dos pinos da barra."))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(L("Em automático, o lado esquerdo mostra a cota mais apertada e o direito a seguinte; a barra inferior mostra sempre a mais apertada; o destaque do menu mostra a mais crítica entre todas. Uma cota escolhida que deixe de existir volta para automático sozinha."))
                        .font(.caption).foregroundStyle(.secondary)

                    // Um switch só governa os DOIS modos (colado ao notch e ilha
                    // flutuante), então o rótulo não pode mais dizer "notch": de tampa
                    // fechada ele estaria mentindo sobre o que liga.
                    Toggle(L("Painel no topo da tela"), isOn: $notchHUDEnabled)
                        .toggleStyle(.switch)
                        .onChange(of: notchHUDEnabled) { _, newValue in
                            preferencesStore.notchHUDEnabled = newValue
                            onNotchPreferenceChanged?()
                        }
                    Text(L("Na tela do MacBook o painel abraça o notch. Sem notch — monitor externo, tampa fechada, iMac — ele vira uma ilha flutuante no topo da tela principal, com o mesmo conteúdo."))
                        .font(.caption).foregroundStyle(.secondary)
                }

                // Filtro só do POPOVER — pinos, notch e alertas continuam vendo a conta
                // normalmente mesmo desmarcada aqui. É a resposta direta ao pedido "não
                // consigo escolher quem aparece no menu": antes o popover mostrava todo
                // mundo sempre, incluindo os provedores ainda não configurados na seção
                // de problemas.
                Section(L("Mostrar no menu")) {
                    ForEach(providerIds, id: \.self) { id in
                        showInMenuRow(id)
                    }
                    Text(L("Desmarque as contas que você não quer ver no menu do OkTally. Pinos, notch e alertas continuam funcionando."))
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
            notchHUDEnabled = preferencesStore.notchHUDEnabled
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
                MenuBarLabelView(segment: appModel.menuBarSegment)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                    .fill(Color.black.opacity(0.55)))
            }
        }
    }

    /// Uma parada: percentual, seletor de cor nativo e o botão de remover.
    private func stopRow(_ stop: UsageColorStop) -> some View {
        HStack(spacing: Theme.Space.sm) {
            // Amostra da própria parada à esquerda: sem ela a linha é um número e um
            // controle do sistema, e o dono teria que abrir o seletor para saber que cor
            // ele já escolheu.
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(usage: stop.color))
                .frame(width: 22, height: 14)
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Theme.border()))
            TextField("", text: percentBinding(stop))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .frame(width: 56)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .focused($focusedStop, equals: stop.id)
                .onSubmit { commitPercent(stop) }
                .onChange(of: focusedStop) { previous, _ in
                    if previous == stop.id { commitPercent(stop) }
                }
            Text(L("% restante")).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: Theme.Space.sm)
            // `ColorPicker` nativo: é o seletor do sistema, com a paleta, o conta-gotas e
            // a favoritos que o dono já usa em todo lugar do macOS.
            ColorPicker("", selection: colorBinding(stop), supportsOpacity: false)
                .labelsHidden()
            Button {
                appModel.usageColorScale = appModel.usageColorScale.removing(id: stop.id)
                percentDrafts[stop.id] = nil
            } label: {
                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            // Duas paradas é o mínimo para existir degradê — abaixo disso a escala vira
            // uma cor chapada.
            .disabled(appModel.usageColorScale.stops.count <= UsageColorScale.minimumStops)
            .help(L("Remover parada"))
        }
    }

    private func percentBinding(_ stop: UsageColorStop) -> Binding<String> {
        Binding(
            get: { percentDrafts[stop.id] ?? PreferencesFieldCommit.percent(stop.percent) },
            set: { percentDrafts[stop.id] = $0 }
        )
    }

    /// Cor: grava na hora, sem rascunho. O `ColorPicker` já é um commit por si — e ver a
    /// barra de preview mudar enquanto se arrasta o seletor é metade do ponto da seção.
    private func colorBinding(_ stop: UsageColorStop) -> Binding<Color> {
        Binding(
            get: { Color(usage: stop.color) },
            set: { appModel.usageColorScale = appModel.usageColorScale.replacingColor(id: stop.id, color: $0.usageRGB) }
        )
    }

    /// Auto-save do percentual, pela mesma regra dos outros campos: vazio ou inalterado
    /// não grava, lixo é recusado e o campo volta ao salvo, fora de 0–100 é grampeado.
    private func commitPercent(_ stop: UsageColorStop) {
        switch PreferencesFieldCommit.scalePercent(raw: percentDrafts[stop.id] ?? "", saved: stop.percent) {
        case .ignored(let restore):
            percentDrafts[stop.id] = restore
        case .commit(let value, let display):
            percentDrafts[stop.id] = display
            appModel.usageColorScale = appModel.usageColorScale.replacingPercent(id: stop.id, percent: value)
        }
    }

    /// Um seletor de slot: "Automático" mais todas as janelas conhecidas agora.
    ///
    /// `Picker` nativo e não uma lista própria: é um menu de escolha única entre poucas
    /// dezenas de itens, exatamente o que o controle do sistema faz melhor (e de graça:
    /// teclado, VoiceOver, rolagem).
    private func slotPicker(_ title: String, selection: Binding<QuotaSlot>) -> some View {
        Picker(title, selection: selection) {
            ForEach(options(including: selection.wrappedValue), id: \.self) { slot in
                Text(slotLabel(slot)).tag(slot)
            }
        }
    }

    private func forecastSlotPicker(selection: Binding<ForecastSlot>) -> some View {
        Picker(L("Previsão de consumo"), selection: selection) {
            ForEach(forecastOptions(including: selection.wrappedValue), id: \.self) { slot in
                Text(forecastSlotLabel(slot)).tag(slot)
            }
        }
    }

    private func forecastOptions(including selection: ForecastSlot) -> [ForecastSlot] {
        var options: [ForecastSlot] = [.automatic] + appModel.availableForecastSlots
        if !options.contains(selection) { options.append(selection) }
        return options
    }

    private func forecastSlotLabel(_ slot: ForecastSlot) -> String {
        switch slot {
        case .automatic:
            return L("Automático — maior risco")
        case .window(let providerId, let windowLabel):
            let name = QuotaSlotLabel.text(providerName: providerName(providerId), windowLabel: windowLabel)
            let exists = appModel.availableForecastSlots.contains(slot)
            return exists ? name : LF("%@ (indisponível)", name)
        }
    }

    /// As opções oferecidas, com a escolha corrente garantidamente entre elas.
    ///
    /// A garantia importa: se o provedor escolhido estiver deslogado, a janela some da
    /// lista e um `Picker` sem a própria seleção desenha um menu VAZIO — o dono acharia
    /// que a preferência dele foi apagada, quando na verdade ela está guardada e só caiu
    /// para automático na exibição.
    private func options(including selection: QuotaSlot) -> [QuotaSlot] {
        var options: [QuotaSlot] = [.automatic] + appModel.availableQuotaSlots
        if !options.contains(selection) { options.append(selection) }
        return options
    }

    private func slotLabel(_ slot: QuotaSlot) -> String {
        switch slot {
        case .automatic:
            return L("Automático (mais crítico)")
        case .window(let providerId, let windowLabel):
            let name = QuotaSlotLabel.text(providerName: providerName(providerId), windowLabel: windowLabel)
            let exists = appModel.snapshotsByProvider[providerId]?.quotas.contains { $0.label == windowLabel } ?? false
            return exists ? name : LF("%@ (indisponível)", name)
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
            Text(QuotaSlotLabel.text(providerName: providerName(pin.providerId), windowLabel: pin.windowLabel))
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

    /// Uma linha do "Mostrar no menu": chip + nome, igual à sidebar, com um switch no
    /// lugar do ponto de status. O binding lê/grava direto em `popoverHiddenProviders`
    /// — não há rascunho porque, ao contrário dos campos de texto ao redor, um switch já
    /// É o commit.
    private func showInMenuRow(_ id: String) -> some View {
        HStack(spacing: Theme.Space.sm) {
            IconChip(glyph: ProviderPalette.glyph(forId: id), color: ProviderPalette.color(for: id), size: 18)
            Text(providerName(id)).font(Theme.Font.body)
            Spacer()
            Toggle("", isOn: Binding(
                get: { !appModel.popoverHiddenProviders.contains(id) },
                set: { shown in
                    if shown {
                        appModel.popoverHiddenProviders.remove(id)
                    } else {
                        appModel.popoverHiddenProviders.insert(id)
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
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

// MARK: - Preview da escala

/// A escala inteira desenhada como um degradê, do 0% (esquerda) ao 100% (direita).
///
/// Não usa `LinearGradient` com as paradas do dono direto: o gradiente do SwiftUI
/// interpola em RGB, e é justamente esse caminho que passa por um cinza lavado entre o
/// azul e o amarelo — o preview mostraria uma escala que o app não desenha. Aqui a barra
/// é AMOSTRADA da mesma função que pinta os números (`UsageColorScale.color(atPercent:)`),
/// de um em um por cento, então o que se vê é literalmente o que o app usa. Um em um e
/// não dois em dois: o crossfade amarelo→azul cabe inteiro em ~4% da barra, e com passo
/// de 2 o mergulho viraria dois degraus visíveis em vez de uma junção.
struct UsageScalePreviewBar: View {
    let scale: UsageColorScale
    /// Traço, não layout — a mesma convenção da `QuotaCapsuleBar` e da barra do notch: a
    /// espessura É a identidade do elemento, e ele não tem conteúdo para se dimensionar.
    var height: CGFloat = 18

    private var gradient: Gradient {
        Gradient(stops: stride(from: 0.0, through: 100.0, by: 1.0).map { percent in
            Gradient.Stop(color: Color(usage: scale.color(atPercent: percent)), location: percent / 100)
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            LinearGradient(gradient: gradient, startPoint: .leading, endPoint: .trailing)
                .frame(height: height)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Theme.border()))
            HStack {
                Text("0%")
                Spacer()
                Text("50%")
                Spacer()
                Text("100%")
            }
            .font(.system(size: 9, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.tertiary)
        }
    }
}
