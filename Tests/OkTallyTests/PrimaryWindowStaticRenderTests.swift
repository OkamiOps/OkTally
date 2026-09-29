// Tests/OkTallyTests/PrimaryWindowStaticRenderTests.swift
import AppKit
import SwiftUI
import XCTest
@testable import OkTally

/// Prova por imagem que a cota secundária deixou de ser "um textinho quase
/// imperceptível": a linha da sessão de 5h de uma conta Business do Codex tem que
/// desenhar uma BARRA na cor da escala de uso, e não só texto.
///
/// Mesma técnica dos outros renders estáticos (`ForecastStaticRenderTests`,
/// `PreferencesAddAccountStaticRenderTests`): `NSHostingView` + `cacheDisplay(in:to:)`,
/// o único caminho que desenha `Form`, `Picker` e o vidro de verdade.
@MainActor
final class PrimaryWindowStaticRenderTests: XCTestCase {
    private var artifactsDir: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("OkTally-primary-window", isDirectory: true)
    }

    override func setUp() {
        super.setUp()
        AccountDirectoryHolder.current = .empty
        UsageColorScaleHolder.current = .standard
    }

    override func tearDown() {
        AccountDirectoryHolder.current = .empty
        super.tearDown()
    }

    // MARK: - Popover

    /// Conta Business com a semanal folgada (84% de sobra) e a sessão de 5h inteira
    /// (100%): a semanal é a principal (mais apertada entre as gerais) e a 5h fica
    /// abaixo — com BARRA. Era exatamente aqui que ela era "quase imperceptível".
    func test_popoverRow_secondaryWindowDrawsItsOwnBar() throws {
        let bitmap = try renderPopover(fiveHourRemaining: 1.0, name: "codex-business-5h-cheia")
        assertBar(in: bitmap, remaining: 1.0, minimumRun: 120, named: "sessão de 5h cheia")
    }

    /// Com a 5h em 20%, ela passa a ser a PRINCIPAL sozinha (a regra automática nova) e a
    /// semanal desce para secundária — que continua com a sua própria barra.
    func test_popoverRow_tightGeneralWindowBecomesTheMainBar() throws {
        let bitmap = try renderPopover(fiveHourRemaining: 0.2, name: "codex-business-5h-apertada")
        assertBar(in: bitmap, remaining: 0.84, minimumRun: 120, named: "semanal secundária")
    }

    /// Escolha explícita do dono ("usar a semanal como principal"): a 5h apertada volta
    /// para baixo, e é aí que a barra tem que gritar — na cor da escala para 20%.
    func test_popoverRow_tightSecondaryWindowDrawsInTheDangerColor() throws {
        let model = try popoverModel(fiveHourRemaining: 0.2)
        model.setPrimaryWindow(providerId: "codex", windowLabel: "weekly")
        let bitmap = try render(PopoverContentView(appModel: model).frame(width: 410),
                                size: CGSize(width: 410, height: 560), name: "codex-semanal-escolhida")
        assertBar(in: bitmap, remaining: 0.2, minimumRun: 40, named: "sessão de 5h apertada")
    }

    /// Metade de baixo do bitmap: o card "Outras cotas" mora aí, abaixo do bloco-herói.
    /// Em fração e não em pixels porque o bitmap sai em 1× ou 2× conforme a tela.
    private func othersCard(_ bitmap: NSBitmapImageRep) -> CGRect {
        CGRect(x: 0, y: Double(bitmap.pixelsHigh) * 0.53,
               width: Double(bitmap.pixelsWide), height: Double(bitmap.pixelsHigh) * 0.47)
    }

    /// Uma BARRA e não um texto: o que separa os dois é o comprimento CONTÍNUO da cor.
    /// Nenhum glifo de 10pt produz uma faixa de dezenas de pixels seguidos na mesma cor.
    ///
    /// `minimumRun` acompanha a sobra porque a barra é PREENCHIDA pela sobra: a de 20%
    /// mede um quinto da de 100%, e exigir o mesmo comprimento das duas seria exigir que
    /// a barra mentisse.
    private func assertBar(in bitmap: NSBitmapImageRep, remaining: Double, minimumRun: Int, named: String) {
        let color = Color(usage: UsageColorScaleHolder.current.color(atRemaining: remaining))
        XCTAssertGreaterThan(longestRun(in: bitmap, matching: color, within: othersCard(bitmap)), minimumRun,
                             "\(named): não há barra contínua na cor da escala")
    }

    private func renderPopover(fiveHourRemaining: Double, name: String) throws -> NSBitmapImageRep {
        let model = try popoverModel(fiveHourRemaining: fiveHourRemaining)
        return try render(PopoverContentView(appModel: model).frame(width: 410),
                          size: CGSize(width: 410, height: 560), name: name)
    }

    /// Claude no aperto (vira o herói) + o Codex Business na lista de baixo — é a linha
    /// do Codex, com as duas janelas gerais, que esta prova está olhando.
    private func popoverModel(fiveHourRemaining: Double) throws -> AppModel {
        let now = Date()
        let registry = PluginRegistry()
        registry.register(FakeUsageProvider(id: "claude", displayName: "Claude Code"))
        registry.register(FakeUsageProvider(id: "codex", displayName: "Codex · OkamiOps"))

        let storage = FakeStorage()
        try storage.save(ProviderSnapshot(
            providerId: "claude", fetchedAt: now,
            quotas: [QuotaWindow(label: "5h", shape: .rollingWindow(
                used: 88, limit: 100, windowStart: now, resetAt: now.addingTimeInterval(2 * 3600)))],
            usageDetail: nil))
        try storage.save(ProviderSnapshot(
            providerId: "codex", fetchedAt: now,
            quotas: [
                QuotaWindow(label: "weekly", shape: .rollingWindow(
                    used: 16, limit: 100, windowStart: now, resetAt: now.addingTimeInterval(4 * 24 * 3600))),
                QuotaWindow(label: "5h", shape: .rollingWindow(
                    used: (1 - fiveHourRemaining) * 100, limit: 100, windowStart: now,
                    resetAt: now.addingTimeInterval(4 * 3600 + 55 * 60)))
            ],
            usageDetail: nil))

        let suite = "oktally.tests.primary-window-render.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let scheduler = Scheduler(registry: registry, storage: storage, alertEngine: AlertEngine(),
                                  alertDispatcher: AlertDispatcher(sender: FakeNotificationSender()))
        return AppModel(registry: registry, scheduler: scheduler, storage: storage, defaults: defaults)
    }

    // MARK: - Preferências

    /// O seletor "Cota principal" tem que existir e desenhar no painel da conta — sem
    /// ele, a única forma de trocar a cota principal seria o menu de contexto do popover.
    func test_preferencesAccountSection_drawsThePrimaryQuotaPicker() throws {
        let model = try preferencesModel()
        model.requestedPreferencesPane = "codex"
        let view = PreferencesView(
            preferencesStore: PreferencesStore(store: FakeKeyValueStore(), secretStore: FakeSecretStore()),
            tokenStore: FakeTokenStoreForPrimaryWindowRender(),
            browserFlow: BrowserOAuthFlow(manager: FakeOAuthManaging()),
            manualFlow: ManualCodeOAuthFlow(manager: FakeOAuthManaging()),
            deviceCodeFlow: DeviceCodeFlow(tokenStore: FakeTokenStoreForPrimaryWindowRender()),
            mimoSessionStore: FakeMiMoSessionForPrimaryWindowRender(),
            appModel: model,
            onImportClaudeLegacy: { true }
        )
        let bitmap = try renderHosted(view, size: CGSize(width: 760, height: 620), name: "preferences-cota-principal")
        // Faixa do painel de detalhe onde a seção "Conta" vive.
        let accountArea = CGRect(x: 190, y: 60, width: 560, height: 480)
        XCTAssertGreaterThan(inkPixels(in: bitmap, within: accountArea), 2_000,
                             "a seção Conta não desenhou o seletor de cota principal")
    }

    private func preferencesModel() throws -> AppModel {
        let now = Date()
        let registry = PluginRegistry()
        registry.register(FakeUsageProvider(id: "codex", displayName: "Codex · OkamiOps"))
        let storage = FakeStorage()
        try storage.save(ProviderSnapshot(
            providerId: "codex", fetchedAt: now,
            quotas: [
                QuotaWindow(label: "weekly", shape: .rollingWindow(
                    used: 16, limit: 100, windowStart: now, resetAt: now.addingTimeInterval(4 * 24 * 3600))),
                QuotaWindow(label: "5h", shape: .rollingWindow(
                    used: 80, limit: 100, windowStart: now, resetAt: now.addingTimeInterval(4 * 3600)))
            ],
            usageDetail: nil))
        let suite = "oktally.tests.primary-window-prefs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let preferences = PreferencesStore(store: defaults, secretStore: FakeSecretStore())
        preferences.accounts = [AccountInstance(id: "codex", kind: .codex, nickname: "OkamiOps",
                                                email: "ops@okami.example")]
        let scheduler = Scheduler(registry: registry, storage: storage, alertEngine: AlertEngine(),
                                  alertDispatcher: AlertDispatcher(sender: FakeNotificationSender()))
        return AppModel(registry: registry, scheduler: scheduler, storage: storage,
                        defaults: defaults, preferences: preferences)
    }

    // MARK: - Palco

    private func render<V: View>(_ content: V, size: CGSize, name: String) throws -> NSBitmapImageRep {
        try renderHosted(
            ZStack {
                Rectangle().fill(Theme.pageBackground)
                content
            }
            .frame(width: size.width, height: size.height),
            size: size, name: name)
    }

    private func renderHosted<V: View>(_ view: V, size: CGSize, name: String) throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: AnyView(view.environment(\.colorScheme, .dark)))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds), "sem bitmap para \(name)")
        window.display()
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]), "falha ao codificar \(name)")
        try FileManager.default.createDirectory(at: artifactsDir, withIntermediateDirectories: true)
        let url = artifactsDir.appendingPathComponent("\(name).png")
        try png.write(to: url, options: .atomic)
        print("primary window render: \(url.path)")
        return bitmap
    }

    /// A maior faixa horizontal CONTÍNUA de uma cor dentro de um retângulo. Contar
    /// pixels soltos não distinguiria uma barra de um número escrito na mesma cor; o
    /// comprimento contínuo distingue.
    private func longestRun(in bitmap: NSBitmapImageRep, matching color: Color, within rect: CGRect) -> Int {
        guard let target = NSColor(color).usingColorSpace(.sRGB) else { return 0 }
        var longest = 0
        let minX = max(0, Int(rect.minX)), maxX = min(bitmap.pixelsWide - 1, Int(rect.maxX))
        let minY = max(0, Int(rect.minY)), maxY = min(bitmap.pixelsHigh - 1, Int(rect.maxY))
        guard minX < maxX, minY < maxY else { return 0 }
        for y in minY...maxY {
            var run = 0
            for x in minX...maxX {
                let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
                let matches = pixel.map { p in
                    max(abs(p.redComponent - target.redComponent),
                        abs(p.greenComponent - target.greenComponent),
                        abs(p.blueComponent - target.blueComponent)) < 0.12
                } ?? false
                run = matches ? run + 1 : 0
                longest = max(longest, run)
            }
        }
        return longest
    }

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

private final class FakeTokenStoreForPrimaryWindowRender: TokenStoring {
    private var tokens: [String: OAuthToken] = [
        "codex": OAuthToken(accessToken: "demo", refreshToken: nil, expiresAt: nil, extra: [:])
    ]
    func save(_ token: OAuthToken, providerId: String) throws { tokens[providerId] = token }
    func load(providerId: String) -> OAuthToken? { tokens[providerId] }
    func delete(providerId: String) throws { tokens[providerId] = nil }
}

private final class FakeMiMoSessionForPrimaryWindowRender: MiMoSessionStoring {
    var isLoggedIn = false
}
