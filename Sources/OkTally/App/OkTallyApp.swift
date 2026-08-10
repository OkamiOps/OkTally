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
    private let claudeProvider: ClaudeUsageProvider
    private let mimoSessionStore = MiMoSessionStore()

    init() {
        let appSupportDir = NSHomeDirectory() + "/Library/Application Support/OkTally"
        try? FileManager.default.createDirectory(atPath: appSupportDir, withIntermediateDirectories: true)

        let registry = PluginRegistry()
        let preferencesStore = PreferencesStore()
        let storage = Self.openStorage(at: appSupportDir + "/usage.sqlite")
        let alertEngine = AlertEngine()
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

        let claudeProvider = ClaudeUsageProvider(oauthManager: oauthManager, tokenStore: tokenStore)
        claudeProvider.importLegacyCredentialsIfAvailable()
        self.claudeProvider = claudeProvider

        registry.register(claudeProvider)
        registry.register(CodexUsageProvider(oauthManager: oauthManager, tokenStore: tokenStore))
        registry.register(OpenRouterUsageProvider(apiKeyProvider: { preferencesStore.openRouterAPIKey }))
        registry.register(MiniMaxUsageProvider(
            apiKeyProvider: { preferencesStore.minimaxAPIKey },
            region: { preferencesStore.minimaxRegionRaw == "china" ? .china : .global }
        ))
        registry.register(CursorUsageProvider())
        registry.register(OpenCodeUsageProvider(apiKeyProvider: { preferencesStore.openCodeAPIKey }))
        registry.register(MiMoUsageProvider(
            sessionStore: mimoSessionStore,
            usageFetcher: MiMoWebSession.shared,
            allowanceProvider: { preferencesStore.mimoMonthlyAllowanceCredits },
            usedCreditsProvider: { preferencesStore.mimoUsedCredits }
        ))
        registry.register(SuperGrokUsageProvider(oauthManager: oauthManager, tokenStore: tokenStore))

        let model = AppModel(registry: registry, scheduler: scheduler)
        _appModel = StateObject(wrappedValue: model)

        Task { await notificationSender.requestAuthorizationIfNeeded() }
        model.start()
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(appModel: appModel)
        } label: {
            Image(nsImage: MenuBarLabelRenderer.image(for: appModel.menuBarSegments))
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView(
                preferencesStore: preferencesStore,
                tokenStore: tokenStore,
                browserFlow: browserFlow,
                manualFlow: manualFlow,
                deviceCodeFlow: deviceCodeFlow,
                mimoSessionStore: mimoSessionStore,
                appModel: appModel,
                onImportClaudeLegacy: { claudeProvider.importLegacyCredentialsIfAvailable() }
            )
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
