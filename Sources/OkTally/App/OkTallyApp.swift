// Sources/OkTally/App/OkTallyApp.swift
import SwiftUI

@main
struct OkTallyApp: App {
    @StateObject private var appModel: AppModel
    private let preferencesStore = PreferencesStore()

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
        let claudeProvider = ClaudeUsageProvider(oauthManager: oauthManager, tokenStore: tokenStore)
        claudeProvider.importLegacyCredentialsIfAvailable()
        registry.register(claudeProvider)
        registry.register(OpenRouterUsageProvider(apiKeyProvider: { preferencesStore.openRouterAPIKey }))

        let model = AppModel(registry: registry, scheduler: scheduler)
        _appModel = StateObject(wrappedValue: model)

        Task { await notificationSender.requestAuthorizationIfNeeded() }
        model.start()
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(appModel: appModel)
        } label: {
            Text(MenuBarStateCalculator.labelText(for: appModel.menuBarState))
                .foregroundStyle(Self.color(for: MenuBarStateCalculator.colorName(for: appModel.menuBarState)))
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView(preferencesStore: preferencesStore)
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

    private static func color(for colorName: String) -> Color {
        switch colorName {
        case "red": return .red
        case "yellow": return .yellow
        case "gray": return .gray
        default: return .green
        }
    }
}
