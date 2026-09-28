// Sources/OkTally/App/OkTallyApp.swift
import SwiftUI

@main
struct OkTallyApp: App {
    @StateObject private var appModel: AppModel
    private let preferencesStore = PreferencesStore()
    private let tokenStore: TokenStoring
    private let browserFlow: BrowserOAuthFlow
    private let manualFlow: ManualCodeOAuthFlow
    private let deviceCodeFlow: DeviceCodeFlow
    private let claudeProvider: ClaudeUsageProvider?
    private let mimoSessionStore = MiMoSessionStore()
    /// O painel do notch. Criado aqui e mantido vivo pelo `App`: ele não pertence a cena
    /// nenhuma (é uma janela flutuante própria), então precisa de um dono com o mesmo
    /// tempo de vida do app.
    private let notchController: NotchHUDController

    init() {
        let appSupportDir = NSHomeDirectory() + "/Library/Application Support/OkTally"
        try? FileManager.default.createDirectory(atPath: appSupportDir, withIntermediateDirectories: true)

        let registry = PluginRegistry()
        let preferencesStore = PreferencesStore()
        let storage = Self.openStorage(at: appSupportDir + "/usage.sqlite")
        // Retention: the snapshots table grows on every poll (~2.3k rows/dia com 8
        // providers); 30 dias cobrem qualquer janela de cota exibida com folga.
        try? storage.prune(olderThan: Date().addingTimeInterval(-30 * 24 * 3600))
        let alertEngine = AlertEngine(
            percentThresholds: { preferencesStore.alertPercentThresholds },
            lowBalanceLimit: { Decimal(preferencesStore.alertLowBalanceThreshold) },
            isEnabled: { preferencesStore.alertsEnabled }
        )
        let notificationSender = UNNotificationSender()
        let alertDispatcher = AlertDispatcher(sender: notificationSender)
        let scheduler = Scheduler(
            registry: registry,
            storage: storage,
            alertEngine: alertEngine,
            alertDispatcher: alertDispatcher,
            thresholdsProvider: { _ in [:] }
        )

        let tokenStore = KeychainTokenStore()
        let oauthManager = OAuthManager(store: tokenStore)
        let browserFlow = BrowserOAuthFlow(manager: oauthManager)
        let manualFlow = ManualCodeOAuthFlow(manager: oauthManager)
        let deviceCodeFlow = DeviceCodeFlow(tokenStore: tokenStore)
        self.tokenStore = tokenStore
        self.browserFlow = browserFlow
        self.manualFlow = manualFlow
        self.deviceCodeFlow = deviceCodeFlow

        // O registry nasce das contas persistidas. Sem nenhuma conta extra, isto rende
        // exatamente os mesmos ids, na mesma ordem e com os mesmos nomes de antes.
        let factory = ProviderFactory(dependencies: .init(
            oauthManager: oauthManager,
            tokenStore: tokenStore,
            preferences: preferencesStore,
            mimoSessionStore: mimoSessionStore
        ))
        let accounts = preferencesStore.accounts
        for account in accounts {
            factory.providers(for: account, all: accounts).forEach(registry.register)
        }
        // O import do login do Claude Code CLI só semeia a conta legada — e só se ela
        // ainda existe na lista (o dono pode tê-la removido).
        let claudeProvider = registry.providers
            .first { $0.id == AccountKind.claude.rawValue }
            .flatMap { ($0 as? LabeledProvider)?.base as? ClaudeUsageProvider }
        claudeProvider?.importLegacyCredentialsIfAvailable()
        self.claudeProvider = claudeProvider

        let pricingEngine = PricingEngine(source: OpenRouterPricingSource())
        let model = AppModel(registry: registry, scheduler: scheduler, storage: storage, pricingEngine: pricingEngine,
                             preferences: preferencesStore)
        model.providerFactory = { account in factory.providers(for: account, all: preferencesStore.accounts) }
        model.credentialEraser = { account in try Self.eraseCredential(of: account, tokenStore: tokenStore, preferences: preferencesStore) }
        let emailResolver = AccountEmailResolver(
            tokenStore: tokenStore,
            oauthManager: oauthManager,
            claudeProfile: ClaudeProfileClient(),
            cursorEmail: { CursorTokenReader().readEmail() },
            antigravityEmail: { AntigravityTokenReader().readEmail() }
        )
        model.identityResolver = { account in await emailResolver.resolve(account) }
        model.updateFetcher = GitHubLatestReleaseFetcher()
        let codexAnalyticsFetcher = CodexAnalyticsFetcher()
        model.analyticsLoaders["codex"] = {
            guard let accessToken = try? await oauthManager.validAccessToken(providerId: "codex", config: CodexOAuth.config) else {
                return nil
            }
            let accountId = tokenStore.load(providerId: "codex")?.extra["account_id"]
            return try? await codexAnalyticsFetcher.fetch(accessToken: accessToken, accountId: accountId)
        }
        // Fontes locais: leitura de disco potencialmente pesada (o corpus do Claude Code
        // passa de centenas de MB no primeiro parse) — sempre fora da main thread.
        let claudeScanner = ClaudeLocalUsageScanner()
        model.analyticsLoaders["claude"] = {
            await Task.detached(priority: .utility) { claudeScanner.analytics() }.value
        }
        let openCodeAnalyticsEstimator = OpenCodeLocalEstimator()
        model.analyticsLoaders["opencode"] = {
            await Task.detached(priority: .utility) {
                openCodeAnalyticsEstimator.dailyTokens(windowDays: 365, now: Date()).flatMap { buckets in
                    buckets.isEmpty ? nil : TokenAnalytics(dailyBuckets: buckets)
                }
            }.value
        }
        _appModel = StateObject(wrappedValue: model)

        let notchController = NotchHUDController(appModel: model, preferences: preferencesStore, isEnabled: { preferencesStore.notchHUDEnabled })
        self.notchController = notchController

        Task { await notificationSender.requestAuthorizationIfNeeded() }
        model.start()
        // Depois do launch, não durante o `init`: criar uma janela flutuante antes de o
        // NSApp terminar de subir deixa o painel fora da tela (as métricas do notch ainda
        // não estão disponíveis). Se o app já estiver ativo — recarga do SwiftUI —
        // começamos na hora.
        if NSApp?.isRunning == true {
            Task { @MainActor in notchController.start() }
        } else {
            NotificationCenter.default.addObserver(
                forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main
            ) { _ in
                Task { @MainActor in notchController.start() }
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(appModel: appModel)
        } label: {
            MenuBarExtraLabel(appModel: appModel)
        }
        .menuBarExtraStyle(.window)

        Window(L("OkTally — Visão geral"), id: "main") {
            MainWindowView(appModel: appModel)
        }
        .defaultSize(width: 860, height: 560)

        Settings {
            PreferencesView(
                preferencesStore: preferencesStore,
                tokenStore: tokenStore,
                browserFlow: browserFlow,
                manualFlow: manualFlow,
                deviceCodeFlow: deviceCodeFlow,
                mimoSessionStore: mimoSessionStore,
                appModel: appModel,
                onImportClaudeLegacy: { claudeProvider?.importLegacyCredentialsIfAvailable() ?? false },
                onNotchPreferenceChanged: { notchController.refresh() }
            )
        }
    }

    /// O rótulo da barra como VIEW, e não como `Image` solta no closure.
    ///
    /// É o que dá acesso ao `colorScheme` do ambiente — a barra de menu do macOS segue a
    /// aparência do sistema, e o rótulo é um bitmap não-template que ninguém adapta por
    /// nós (ver `MenuBarInk`). Como o ambiente muda quando o sistema troca de tema, a
    /// imagem é remontada na hora, sem reiniciar o app.
    private struct MenuBarExtraLabel: View {
        @ObservedObject var appModel: AppModel
        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            Image(nsImage: MenuBarLabelRenderer.image(for: appModel.menuBarSegment,
                                                      onDarkBar: colorScheme == .dark))
        }
    }

    /// Apaga a credencial de uma conta removida. Contas OAuth guardam o token no
    /// Keychain sob o próprio id; as de chave de API, no Keychain de segredos.
    private static func eraseCredential(of account: AccountInstance, tokenStore: TokenStoring, preferences: PreferencesStore) throws {
        switch account.kind {
        case .openrouter where AccountID.isLegacy(account.id):
            try preferences.setOpenRouterAPIKey(nil)
        case .minimax where AccountID.isLegacy(account.id):
            try preferences.setMinimaxAPIKey(nil)
        case .opencode where AccountID.isLegacy(account.id):
            try preferences.setOpenCodeAPIKey(nil)
        default:
            try tokenStore.delete(providerId: account.id)
        }
    }

    private static func openStorage(at path: String) -> SQLiteStorage {
        if let storage = try? SQLiteStorage(path: path) {
            return storage
        }
        try? FileManager.default.removeItem(atPath: path)
        if let storage = try? SQLiteStorage(path: path) {
            return storage
        }
        return try! SQLiteStorage(path: ":memory:")
    }
}
