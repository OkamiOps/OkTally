// Tests/OkTallyTests/PreferencesAddAccountStaticRenderTests.swift
import AppKit
import SwiftUI
import XCTest
@testable import OkTally

/// Prova por imagem que os três pontos de entrada de "adicionar conta" pedidos pelo dono
/// realmente desenham algo visível — antes disso a única forma de descobrir era abrir o
/// app, e foi assim que ele não achou a função por conta própria.
///
/// Mesma técnica do `ReadmeAssetRenderer.writeHosted`: `ImageRenderer` (SwiftUI puro)
/// devolve `Form` agrupado em branco, então o desenho passa por `NSHostingView` +
/// `cacheDisplay(in:to:)`, o caminho que sabe desenhar `Form`, `Menu` e `TextField` de
/// verdade.
@MainActor
final class PreferencesAddAccountStaticRenderTests: XCTestCase {
    private var artifactsDir: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("OkTally-preferences-add-account", isDirectory: true)
    }

    private let size = CGSize(width: 760, height: 600)

    /// Rodapé da sidebar: o botão cheio "Adicionar conta…" tem que desenhar tinta na
    /// faixa colada à base da PRIMEIRA coluna do `NavigationSplitView` — se
    /// `.safeAreaInset` não estivesse surtindo efeito, ali seria só o fundo da lista.
    func test_sidebarBottomButtonDrawsAFullWidthStrip() throws {
        let bitmap = try renderView(name: "sidebar-bottom-button")
        let strip = CGRect(x: 2, y: 2, width: 180, height: 34)
        XCTAssertGreaterThan(inkPixels(in: bitmap, within: strip), 150,
                              "o botão \"Adicionar conta…\" não desenhou no rodapé da sidebar")
    }

    /// O painel do Claude (única conta cadastrada, tipo addable): a seção "Conta" tem que
    /// desenhar mais do que o e-mail sozinho — o rótulo "Apelido", o campo com o novo
    /// placeholder e o botão "Adicionar outra conta Claude Code" moram todos ali.
    func test_claudePaneAccountSectionDrawsBeyondJustEmail() throws {
        let bitmap = try renderView(name: "claude-pane-account-section", pane: "claude")
        // Faixa abaixo do cabeçalho colorido (herói) e acima do rodapé da janela — onde a
        // seção "Conta" do Form agrupado vive.
        let accountArea = CGRect(x: 190, y: 140, width: 550, height: 400)
        XCTAssertGreaterThan(inkPixels(in: bitmap, within: accountArea), 800,
                              "a seção Conta do painel do Claude não desenhou o suficiente")
    }

    // MARK: - Palco

    /// Uma conta só (Claude), do tipo que aceita segunda conta e com e-mail conhecido —
    /// o caso que exercita e-mail + apelido + "Adicionar outra conta" ao mesmo tempo.
    private func demoModel() throws -> AppModel {
        let registry = PluginRegistry()
        let claude = FakeUsageProvider(id: "claude", displayName: "Claude Code")
        claude.snapshotToReturn = ProviderSnapshot(
            providerId: "claude", fetchedAt: Date(),
            quotas: [QuotaWindow(label: "5h", shape: .rollingWindow(
                used: 22, limit: 100, windowStart: Date(), resetAt: Date().addingTimeInterval(9_700)))],
            usageDetail: nil)
        registry.register(claude)
        let defaults = UserDefaults(suiteName: "PreferencesAddAccountStaticRenderTests")!
        defaults.removePersistentDomain(forName: "PreferencesAddAccountStaticRenderTests")
        let storage = FakeStorage()
        let scheduler = Scheduler(registry: registry, storage: storage,
                                  alertEngine: AlertEngine(),
                                  alertDispatcher: AlertDispatcher(sender: FakeNotificationSender()))
        let model = AppModel(registry: registry, scheduler: scheduler, storage: storage, defaults: defaults)
        return model
    }

    private func preferencesView(model: AppModel) -> PreferencesView {
        let store = PreferencesStore(store: FakeKeyValueStore(), secretStore: FakeSecretStore())
        let tokens = FakeTokenStoreForAddAccountRender()
        let oauth = FakeOAuthManaging()
        return PreferencesView(
            preferencesStore: store,
            tokenStore: tokens,
            browserFlow: BrowserOAuthFlow(manager: oauth),
            manualFlow: ManualCodeOAuthFlow(manager: oauth),
            deviceCodeFlow: DeviceCodeFlow(tokenStore: tokens),
            mimoSessionStore: FakeMiMoSessionForAddAccountRender(),
            appModel: model,
            onImportClaudeLegacy: { true }
        )
    }

    private func renderView(name: String, pane: String? = nil) throws -> NSBitmapImageRep {
        let model = try demoModel()
        let view = preferencesView(model: model)
        if let pane { model.requestedPreferencesPane = pane }
        return try renderHosted(view, size: size, name: name)
    }

    /// Render pelo AppKit — ver comentário do arquivo. A janela é obrigatória: fora dela o
    /// `NSHostingView` não recebe a aparência nem completa o layout dos controles.
    private func renderHosted<V: View>(_ view: V, size: CGSize, name: String) throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: AnyView(view.environment(\.colorScheme, .dark)))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds), "sem bitmap para \(name)")
        window.display()
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]), "falha ao codificar \(name)")
        try FileManager.default.createDirectory(at: artifactsDir, withIntermediateDirectories: true)
        let url = artifactsDir.appendingPathComponent("\(name).png")
        try png.write(to: url, options: .atomic)
        print("preferences add-account render: \(url.path)")
        return bitmap
    }

    /// Pixels que destoam do fundo da janela dentro de um retângulo — a mesma ideia de
    /// `assertUnclipped` do `AnalyticsHoverStaticRenderTests`, restrita a uma região.
    private func inkPixels(in bitmap: NSBitmapImageRep, within rect: CGRect) -> Int {
        guard let background = bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB) else { return 0 }
        var count = 0
        let minX = max(0, Int(rect.minX)), maxX = min(bitmap.pixelsWide - 1, Int(rect.maxX))
        let minY = max(0, Int(rect.minY)), maxY = min(bitmap.pixelsHigh - 1, Int(rect.maxY))
        guard minX < maxX, minY < maxY else { return 0 }
        for y in minY...maxY {
            for x in minX...maxX {
                guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let differs = max(
                    abs(pixel.redComponent - background.redComponent),
                    abs(pixel.greenComponent - background.greenComponent),
                    abs(pixel.blueComponent - background.blueComponent)
                ) > 0.04
                if differs { count += 1 }
            }
        }
        return count
    }
}

// MARK: - Dublês só deste arquivo

private final class FakeTokenStoreForAddAccountRender: TokenStoring {
    private var tokens: [String: OAuthToken] = [
        "claude": OAuthToken(accessToken: "demo", refreshToken: nil, expiresAt: nil, extra: [:])
    ]
    func save(_ token: OAuthToken, providerId: String) throws { tokens[providerId] = token }
    func load(providerId: String) -> OAuthToken? { tokens[providerId] }
    func delete(providerId: String) throws { tokens[providerId] = nil }
}

private final class FakeMiMoSessionForAddAccountRender: MiMoSessionStoring {
    var isLoggedIn = false
}
