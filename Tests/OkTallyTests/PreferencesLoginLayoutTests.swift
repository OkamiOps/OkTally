import AppKit
import SwiftUI
import XCTest
import Vision
@testable import OkTally

@MainActor
final class PreferencesLoginLayoutTests: XCTestCase {
    private let artifacts = FileManager.default.temporaryDirectory
        .appendingPathComponent("OkTally-login-layout", isDirectory: true)

    func test_kimiDeviceCodeAndCancelFitAtMinimumSize() throws {
        let authorization = KimiDeviceAuthorization(userCode: "KM-TEST", deviceCode: "synthetic",
            verificationURL: URL(string: "https://auth.kimi.com/")!, expiresAt: .distantFuture, interval: 5)
        let view = ProviderPaneScaffold(providerId: "kimi", name: "Kimi Code",
                                        status: .notConfigured(L("Faça login para adicionar esta conta"))) {
            KimiConnectionControls(isConnected: false, isBusy: true, authorization: authorization,
                                   onLogin: {}, onCancel: {}, onDisconnect: {})
        } details: { Text("Kimi Code") }
        let window = host(view, size: CGSize(width: 490, height: 520))
        defer { window.close() }
        let text = try recognizedText(in: capture(window, name: "kimi-code-490x520"))
        XCTAssertTrue(text.contains { $0 == "KM-TEST" })
        XCTAssertTrue(text.contains { normalized($0) == normalized(L("Cancelar login")) })
    }

    func test_kiroImportActionsFitAtMinimumSize() throws {
        let view = ProviderPaneScaffold(providerId: "kiro", name: "Kiro",
                                        status: .notConfigured(L("Faça login para adicionar esta conta"))) {
            KiroConnectionControls(isConnected: false, isBusy: false,
                                   onImportCLI: {}, onDisconnect: {})
        } details: {
            Text(L("Créditos mensais, saldo restante e renovação aparecem no menu e no histórico desta conta."))
        }
        let window = host(view, size: CGSize(width: 490, height: 520))
        defer { window.close() }
        let text = try recognizedText(in: capture(window, name: "kiro-import-490x520"))
        XCTAssertTrue(text.contains { $0 == L("Importar do Kiro CLI") })
    }

    func test_newAPIConnectionHasVisibleSaveActionAtMinimumSize() throws {
        let tokens = InMemoryTokenStore()
        let preferences = PreferencesStore(store: FakeKeyValueStore(), secretStore: FakeSecretStore())
        preferences.accounts = [AccountInstance(id: "deepseek", kind: .deepseek)]
        let registry = PluginRegistry()
        registry.register(FakeUsageProvider(id: "deepseek", displayName: "DeepSeek API"))
        let storage = FakeStorage()
        let scheduler = Scheduler(registry: registry, storage: storage, alertEngine: AlertEngine(),
                                  alertDispatcher: AlertDispatcher(sender: FakeNotificationSender()))
        let suite = "PreferencesAPIConnectionLayoutTests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(registry: registry, scheduler: scheduler, storage: storage, defaults: defaults, preferences: preferences)
        model.requestedPreferencesPane = "deepseek"
        let oauth = FakeOAuthManaging()
        let view = PreferencesView(preferencesStore: preferences, tokenStore: tokens,
                                   browserFlow: BrowserOAuthFlow(manager: oauth), manualFlow: ManualCodeOAuthFlow(manager: oauth),
                                   deviceCodeFlow: DeviceCodeFlow(tokenStore: tokens), mimoSessionStore: LoginLayoutMiMoSession(),
                                   appModel: model, onImportClaudeLegacy: { false })
        let window = host(view, size: CGSize(width: 680, height: 520))
        defer { window.close() }
        let text = try recognizedText(in: capture(window, name: "api-connection-680x520"))
        XCTAssertTrue(text.contains { normalized($0) == normalized(L("Validar e salvar")) })
        XCTAssertTrue(text.contains { normalized($0) == normalized(L("Adicionar conta…")) })
    }

    func test_loginControlsFitAtMinimumWindowSizeAndAccountDetailsScroll() throws {
        let view = ProviderPaneScaffold(
            providerId: "claude", name: "Claude Code", status: .needsAttention(L("Reconectar"))
        ) {
            ClaudeLoginCodeEntry(code: .constant("example-code#example-state"),
                                 onComplete: {}, onCancel: {})
        } details: {
            Text("Login layout regression")
        } account: {
            ForEach(0..<20) { index in
                LabeledContent("Account setting \(index)", value: "Example")
            }
        }
        for size in [CGSize(width: 680, height: 520), CGSize(width: 900, height: 564)] {
            let window = host(view, size: size)
            defer { window.close() }
            let content = try XCTUnwrap(window.contentView)
            let bitmap = try capture(window, name: "login-\(Int(size.width))x\(Int(size.height))")
            let text = try recognizedText(in: bitmap)
            XCTAssertTrue(text.contains { $0 == L("Concluir") }, "Done must be fully visible without scrolling")
            XCTAssertTrue(text.contains { $0 == "example-code#example-state" }, "The code field must be visible")
            let form = try XCTUnwrap(scrollViews(in: content).first)
            XCTAssertGreaterThan(try XCTUnwrap(form.documentView).bounds.height, form.contentView.bounds.height,
                                 "Long account details must create scrollable content")
            XCTAssertTrue(content.bounds.contains(content.convert(form.contentView.bounds, from: form.contentView)),
                          "The scroll viewport must fit inside the window")
            form.documentView?.scrollToVisible(CGRect(x: 0, y: form.documentView!.bounds.maxY - 1,
                                                      width: 1, height: 1))
            settle(window)
            XCTAssertGreaterThan(form.contentView.bounds.origin.y, 0, "Account details must actually scroll")
        }
    }

    func test_expiredStoredTokenOffersReconnectAndKeepsSidebarFooterInsideWindow() async throws {
        let provider = FakeUsageProvider(id: "claude", displayName: "Claude Code")
        provider.errorToThrow = OAuthError.refreshFailed(400)
        let registry = PluginRegistry()
        registry.register(provider)
        let storage = FakeStorage()
        let scheduler = Scheduler(registry: registry, storage: storage, alertEngine: AlertEngine(),
                                  alertDispatcher: AlertDispatcher(sender: FakeNotificationSender()))
        let suite = "PreferencesLoginLayoutTests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(registry: registry, scheduler: scheduler, storage: storage, defaults: defaults)
        await model.refreshNow()
        XCTAssertEqual(model.errorKindByProvider["claude"], .needsReauth)
        model.requestedPreferencesPane = "claude"
        let tokens = InMemoryTokenStore()
        try tokens.save(OAuthToken(accessToken: "example", refreshToken: "example", expiresAt: nil, extra: [:]),
                        providerId: "claude")
        let oauth = FakeOAuthManaging()
        let view = PreferencesView(
            preferencesStore: PreferencesStore(store: FakeKeyValueStore(), secretStore: FakeSecretStore()),
            tokenStore: tokens, browserFlow: BrowserOAuthFlow(manager: oauth),
            manualFlow: ManualCodeOAuthFlow(manager: oauth), deviceCodeFlow: DeviceCodeFlow(tokenStore: tokens),
            mimoSessionStore: LoginLayoutMiMoSession(), appModel: model, onImportClaudeLegacy: { false })
        let window = host(view, size: CGSize(width: 680, height: 520))
        defer { window.close() }
        let content = try XCTUnwrap(window.contentView)
        let bitmap = try capture(window, name: "expired-token-680x520")
        let text = try recognizedText(in: bitmap)
        XCTAssertTrue(text.contains { $0 == L("Reconectar") },
                      "A rejected stored token must offer a visible reconnect button")
        XCTAssertTrue(text.contains { normalized($0) == normalized(L("Adicionar conta…")) },
                      "Add account must stay inside the window")
        for scroll in scrollViews(in: content) {
            XCTAssertTrue(content.bounds.contains(content.convert(scroll.contentView.bounds, from: scroll.contentView)),
                          "All scroll viewports must fit inside the window")
        }
        XCTAssertNotNil(tokens.load(providerId: "claude"), "Offering reconnect must preserve the existing credential")
    }

    private func host<V: View>(_ view: V, size: CGSize) -> NSWindow {
        let content = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled, .resizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = content
        window.makeKeyAndOrderFront(nil)
        settle(window)
        return window
    }

    private func settle(_ window: NSWindow) {
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        window.layoutIfNeeded()
    }

    // Read rendered controls rather than private SwiftUI accessibility nodes, which
    // are not exposed by the hosted XCTest process. Exact text catches clipped labels.
    private func recognizedText(in bitmap: NSBitmapImageRep) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US", "pt-BR"]
        try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage), options: [:]).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }

    private func normalized(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private func scrollViews(in root: NSView) -> [NSScrollView] {
        (root as? NSScrollView).map { [$0] } ?? root.subviews.flatMap { scrollViews(in: $0) }
    }

    private func capture(_ window: NSWindow, name: String) throws -> NSBitmapImageRep {
        let content = try XCTUnwrap(window.contentView)
        let bitmap = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
        window.display()
        content.cacheDisplay(in: content.bounds, to: bitmap)
        try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: artifacts.appendingPathComponent("\(name).png"))
        print("Login layout artifact: \(artifacts.appendingPathComponent(name).path).png")
        return bitmap
    }
}

private final class LoginLayoutMiMoSession: MiMoSessionStoring {
    var isLoggedIn = false
}
