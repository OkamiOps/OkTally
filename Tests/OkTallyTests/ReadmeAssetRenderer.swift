// Tests/OkTallyTests/ReadmeAssetRenderer.swift
//
// Not a test of behavior: renders the real SwiftUI views with demo data into
// docs/assets/*.png for the README. Runs only when RENDER_README_ASSETS=1 so the
// normal suite stays fast:
//
//   RENDER_README_ASSETS=1 swift test --filter ReadmeAssetRenderer
//
// IMPORTANTE — o harness renderiza em TEMA ESCURO. Ele nasceu sem forçar esquema e
// pintando `.windowBackgroundColor` por baixo; dentro do processo de teste isso resolvia
// para CLARO. Ou seja: todo o design do app foi julgado num contexto que o dono nunca
// usa (ele roda no escuro, e as referências visuais dele são dashboards escuros). Duas
// coisas são necessárias e nenhuma sozinha basta:
//
//   1. `.environment(\.colorScheme, .dark)` — governa `.primary`/`.secondary` e o resto
//      da hierarquia semântica do SwiftUI;
//   2. `NSAppearance(named: .darkAqua).performAsCurrentDrawingAppearance` — governa a
//      resolução dos `NSColor(name:dynamicProvider:)` que estão por trás dos tokens de
//      superfície do `Theme`. O ambiente do SwiftUI não alcança esses.
//
// O fundo também é explícito (`Theme.pageBackground`): `.windowBackgroundColor` é cinza
// de sistema e não é a base quase preta da identidade.
import XCTest
import SwiftUI
import AppKit
@testable import OkTally

@MainActor
final class ReadmeAssetRenderer: XCTestCase {
    private var assetsDir: URL {
        // Tests run from the package root.
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/assets")
    }

    /// Variante clara, fora do caminho que o README referencia — serve de conferência de
    /// legibilidade, não de material de divulgação.
    private var lightDir: URL { assetsDir.appendingPathComponent("light") }

    func test_renderReadmeAssets() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RENDER_README_ASSETS"] == "1")
        try FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: lightDir, withIntermediateDirectories: true)

        let model = try await demoModel()
        // O escuro é o que vale para julgar o design; o claro é gerado junto só para
        // provar que continua legível (o app suporta os dois temas).
        for scheme in [ColorScheme.dark, .light] {
            try write(view: PopoverContentView(appModel: model)
                        .environment(\.isStaticRender, true)
                        .frame(width: 360),
                      to: "popover.png", scheme: scheme)
            try write(view: menuBarStrip(model, scheme: scheme), to: "menubar.png", scheme: scheme)
            try write(view: OverviewScreen(
                            appModel: model,
                            entries: model.orderedProviders.compactMap { provider in
                                model.snapshotsByProvider[provider.id].map { (provider, $0) }
                            },
                            onSelect: { _ in })
                        .padding(24)
                        .frame(width: 760),
                      to: "overview.png", scheme: scheme)
            try write(view: OverviewScreen(
                            appModel: model,
                            entries: model.orderedProviders.compactMap { provider in
                                model.snapshotsByProvider[provider.id].map { (provider, $0) }
                            },
                            onSelect: { _ in })
                        .padding(24)
                        .frame(width: 500),
                      to: "overview-narrow.png", scheme: scheme)
            // `isStaticRender` troca só os controles do AppKit por um desenho equivalente:
            // o `ImageRenderer` não sabe desenhá-los e o PNG sairia com um retângulo amarelo
            // no lugar do seletor de janela. O app não liga essa flag.
            try write(view: AnalyticsDashboardView(appModel: model)
                        .environment(\.isStaticRender, true)
                        .padding(24)
                        .frame(width: 860),
                      to: "analytics.png", scheme: scheme)
            // Detalhe do provedor: era a única das quatro telas sem PNG — e justamente a que
            // carregava a inconsistência de cromo com a aba Análise. `ProviderDetailScreen`
            // deixou de ser `private` só para isto.
            guard let claude = model.orderedProviders.first(where: { $0.id == "claude" }),
                  let snapshot = model.snapshotsByProvider["claude"] else {
                XCTFail("demo model sem snapshot do Claude para o PNG de detalhe")
                return
            }
            try write(view: ProviderDetailScreen(appModel: model, provider: claude, snapshot: snapshot)
                        .environment(\.isStaticRender, true)
                        .padding(24)
                        .frame(width: 760),
                      to: "provider-detail.png", scheme: scheme)
        }
        // O painel do notch: a JANELA em si (NSPanel flutuante, forma de "asa", hover)
        // não tem como ser renderizada fielmente por `ImageRenderer`, mas o conteúdo
        // SwiftUI dela tem — e é o conteúdo que decide se o painel se lê. Os dois PNGs
        // saem sobre um fundo claro de propósito: é contra uma janela clara que um painel
        // "quase preto" denunciaria que não é o notch.
        try write(view: notchStage { NotchCollapsedMock(appModel: model) },
                  to: "notch-collapsed.png", scheme: .dark)
        try write(view: notchStage { NotchExpandedMock(appModel: model) },
                  to: "notch-expanded.png", scheme: .dark)

        // A ilha flutuante — o painel quando NENHUMA tela tem recorte (clamshell, monitor
        // externo, iMac). Aqui a `NotchIslandView` é a própria view do app, sem maquete:
        // ela não depende de geometria de hardware nenhuma, então o que sai no PNG é
        // literalmente o que a janela desenha. O palco tem gradiente ESCURO de propósito —
        // é contra um wallpaper escuro que uma pílula preta sem borda vira um buraco sem
        // forma, e é isso que a borda de branco a 8% existe para evitar.
        try write(view: islandStage {
                      NotchIslandView(appModel: model, isExpanded: false, onOpen: {}, onHover: { _ in })
                  },
                  to: "island-collapsed.png", scheme: .dark)
        try write(view: islandStage {
                      NotchIslandView(appModel: model, isExpanded: true, onOpen: {}, onHover: { _ in })
                  },
                  to: "island-expanded.png", scheme: .dark)

        // Preferências vai por outro caminho: `ImageRenderer` NÃO desenha `Form`
        // agrupado (sai em branco), então a tela nunca pôde ser olhada sem abrir o app —
        // e foi exatamente por isso que ela atravessou o redesenho inteiro sem ser
        // redesenhada. `NSHostingView` + `cacheDisplay(in:to:)` desenha pelo caminho do
        // AppKit, que sabe desenhar `Form`, `TextField` e `Toggle`.
        try await renderPreferences()
    }

    /// Os dois estados que valem a pena olhar: o painel Geral (que abre por padrão) e um
    /// painel de provedor (a casca que vale para os dez).
    private func renderPreferences() async throws {
        let model = try await demoPreferencesModel()
        let store = PreferencesStore(store: FakeKeyValueStore(), secretStore: FakeSecretStore())
        let tokens = FakeTokenStore()
        let oauth = FakeOAuthManaging()
        let view = PreferencesView(
            preferencesStore: store,
            tokenStore: tokens,
            browserFlow: BrowserOAuthFlow(manager: oauth),
            manualFlow: ManualCodeOAuthFlow(manager: oauth),
            deviceCodeFlow: DeviceCodeFlow(tokenStore: tokens),
            mimoSessionStore: FakePreferencesMiMoSession(),
            appModel: model,
            onImportClaudeLegacy: { true }
        )
        try writeHosted(view: view, to: "preferences-general.png", size: CGSize(width: 760, height: 600))
        model.requestedPreferencesPane = "claude"
        try writeHosted(view: view, to: "preferences-provider.png", size: CGSize(width: 760, height: 600))
        // Um painel de CHAVE também: é o que tem campo, botão destrutivo e rodapé, ou
        // seja, o painel com mais conteúdo dos dez.
        model.requestedPreferencesPane = "openrouter"
        try writeHosted(view: view, to: "preferences-key.png", size: CGSize(width: 760, height: 600))
    }

    /// Modelo mínimo para a tela de Preferências: um snapshot por provedor (o cabeçalho
    /// mostra a cota) e três pinos (a faixa da marca mostra a barra de menu de verdade).
    private func demoPreferencesModel() async throws -> AppModel {
        let now = Date()
        let registry = PluginRegistry()
        let claude = FakeUsageProvider(id: "claude", displayName: "Claude Code")
        claude.snapshotToReturn = ProviderSnapshot(
            providerId: "claude", fetchedAt: now,
            quotas: [QuotaWindow(label: "5h", shape: .rollingWindow(
                used: 22, limit: 100, windowStart: now, resetAt: now.addingTimeInterval(9700)))],
            usageDetail: nil)
        registry.register(claude)
        for (id, name) in [("codex", "Codex"), ("supergrok", "SuperGrok"), ("cursor", "Cursor"),
                           ("copilot", "GitHub Copilot"), ("antigravity", "Antigravity"),
                           ("openrouter", "OpenRouter"), ("minimax", "MiniMax"),
                           ("opencode", "OpenCode"), ("mimo", "MiMo")] {
            let provider = FakeUsageProvider(id: id, displayName: name)
            // O OpenRouter entra com FALHA de propósito: o painel de chave é justamente
            // onde a tela mais precisa funcionar, e o estado de erro nunca tinha sido
            // olhado em Preferências.
            if id == "openrouter" {
                provider.errorToThrow = DemoProviderError(
                    message: L("Configure sua chave de API do OpenRouter nas Preferências."))
            }
            // Todo provider precisa de snapshot: o dublê força-desembrulha o valor no
            // `fetch`, e um provedor sem resposta derruba o processo de teste inteiro.
            provider.snapshotToReturn = ProviderSnapshot(
                providerId: id, fetchedAt: now,
                quotas: [QuotaWindow(label: "weekly", shape: .rollingWindow(
                    used: 41, limit: 100, windowStart: now,
                    resetAt: now.addingTimeInterval(3 * 24 * 3600)))],
                usageDetail: nil)
            registry.register(provider)
        }
        let defaults = UserDefaults(suiteName: "PreferencesAssetRenderer")!
        defaults.removePersistentDomain(forName: "PreferencesAssetRenderer")
        let storage = FakeStorage()
        let scheduler = Scheduler(registry: registry, storage: storage,
                                  alertEngine: AlertEngine(),
                                  alertDispatcher: AlertDispatcher(sender: FakeNotificationSender()))
        let model = AppModel(registry: registry, scheduler: scheduler, storage: storage, defaults: defaults)
        await model.refreshNow()
        try await Task.sleep(nanoseconds: 200_000_000)
        model.menuBarPins = [
            AppModel.MenuBarPin(providerId: "claude", windowLabel: "5h"),
            AppModel.MenuBarPin(providerId: "codex", windowLabel: "semanal")
        ]
        return model
    }

    /// Render pelo AppKit. `ImageRenderer` (SwiftUI puro) devolve branco para `Form`
    /// agrupado; `cacheDisplay` desenha a árvore de `NSView` real, com os controles do
    /// sistema no lugar. A janela é obrigatória: fora dela o `NSHostingView` não recebe
    /// a aparência nem completa o layout dos controles.
    private func writeHosted<V: View>(view: V, to filename: String, size: CGSize) throws {
        let host = NSHostingView(rootView: AnyView(view.environment(\.colorScheme, .dark)))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame,
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        // Sem trazer a janela para a tela, a sidebar do `NavigationSplitView` (que é um
        // `NSVisualEffectView`) nunca desenha e sai como um retângulo branco no PNG.
        window.makeKeyAndOrderFront(nil)
        window.layoutIfNeeded()
        // O `Form` só termina o layout depois de um giro de run loop: sem isto o PNG sai
        // com a sidebar desenhada e o detalhe ainda vazio.
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            XCTFail("sem bitmap para \(filename)")
            return
        }
        window.display()
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("falha ao codificar \(filename)")
            return
        }
        let url = assetsDir.appendingPathComponent(filename)
        try png.write(to: url)
        print("wrote \(url.path)")
    }

    /// Deterministic pseudo-random daily buckets (LCG) so re-rendering doesn't churn
    /// the committed PNG. `seed` e `scale` dão a cada provider um perfil próprio, para o
    /// empilhado e o donut da aba Análise não saírem com três séries idênticas.
    private func demoAnalytics(
        seed: UInt64 = 0x5DEECE66D,
        scale: Double = 1.0,
        idleOdds: UInt64 = 4,
        lifetimeTokens: Int = 2_200_000_000,
        peakDailyTokens: Int = 385_400_000,
        currentStreakDays: Int = 6,
        longestStreakDays: Int = 8,
        longestRunningTurnSeconds: Int = 2673
    ) -> TokenAnalytics {
        var state: UInt64 = seed
        func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state >> 33
        }
        var buckets: [DailyTokens] = []
        for offset in stride(from: 180, through: 0, by: -1) {
            let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date())!
            let roll = next() % 10
            let raw = roll < idleOdds ? 0 : Int(next() % 90_000_000) + 100_000
            buckets.append(DailyTokens(day: TokenAnalytics.dayKey(date), tokens: Int(Double(raw) * scale)))
        }
        return TokenAnalytics(
            lifetimeTokens: lifetimeTokens,
            peakDailyTokens: peakDailyTokens,
            currentStreakDays: currentStreakDays,
            longestStreakDays: longestStreakDays,
            longestRunningTurnSeconds: longestRunningTurnSeconds,
            dailyBuckets: buckets
        )
    }

    // MARK: - Demo data (fictitious but realistic)

    private func demoModel() async throws -> AppModel {
        let now = Date()
        func rolling(_ usedPercent: Double, hours: Double) -> QuotaShape {
            .rollingWindow(used: usedPercent, limit: 100, windowStart: now,
                           resetAt: now.addingTimeInterval(hours * 3600))
        }

        let registry = PluginRegistry()
        let entries: [(String, String, [QuotaWindow])] = [
            ("claude", "Claude Code", [
                QuotaWindow(label: "5h", shape: rolling(22, hours: 2.7)),
                QuotaWindow(label: "weekly", shape: rolling(53, hours: 41))
            ]),
            ("codex", "Codex", [
                QuotaWindow(label: "semanal", shape: rolling(14, hours: 126)),
                QuotaWindow(label: "GPT-5.3-Codex-Spark (semanal)", shape: rolling(0, hours: 168))
            ]),
            ("openrouter", "OpenRouter", [
                QuotaWindow(label: "balance", shape: .creditBalance(remaining: Decimal(19.82), currency: "USD"))
            ]),
            ("minimax", "MiniMax", [
                QuotaWindow(label: "5h", shape: rolling(1, hours: 0.1)),
                QuotaWindow(label: "weekly", shape: rolling(1, hours: 0.1))
            ]),
            ("cursor", "Cursor", [
                QuotaWindow(label: "percent", shape: rolling(74, hours: 15.4))
            ]),
            ("copilot", "GitHub Copilot", [
                QuotaWindow(label: "premium", shape: rolling(35, hours: 460)),
                QuotaWindow(label: "chat", shape: rolling(12, hours: 460))
            ]),
            ("mimo", "MiMo", [
                QuotaWindow(label: "mensal", shape: rolling(6, hours: 500))
            ]),
            // OpenCode expõe janelas de orçamento estimadas a partir dos tokens locais —
            // é assim que o provider real monta o snapshot, e é também a terceira fonte
            // de analytics da aba Análise.
            ("opencode", "OpenCode", [
                QuotaWindow(label: "mensal", shape: .estimated(
                    used: 38.4, limit: 100, basis: .localTokenCount,
                    resetAt: now.addingTimeInterval(11 * 24 * 3600)))
            ])
        ]
        for (id, name, quotas) in entries {
            let provider = FakeUsageProvider(id: id, displayName: name)
            // O OpenRouter entra com FALHA de propósito: o painel de chave é justamente
            // onde a tela mais precisa funcionar, e o estado de erro nunca tinha sido
            // olhado em Preferências.
            if id == "openrouter" {
                provider.errorToThrow = DemoProviderError(
                    message: L("Configure sua chave de API do OpenRouter nas Preferências."))
            }
            provider.snapshotToReturn = ProviderSnapshot(providerId: id, fetchedAt: now, quotas: quotas, usageDetail: nil)
            registry.register(provider)
        }

        let defaults = UserDefaults(suiteName: "ReadmeAssetRenderer")!
        defaults.removePersistentDomain(forName: "ReadmeAssetRenderer")
        // Histórico de 24h seed para os sparklines dos cards aparecerem no screenshot:
        // uma curva de uso subindo suavemente por provider.
        let storage = FakeStorage()
        for (id, _, quotas) in entries {
            for step in 0..<12 {
                let age = Double(12 - step) * 2 * 3600
                let factor = 0.35 + Double(step) * 0.05
                let past = quotas.map { window -> QuotaWindow in
                    guard case .rollingWindow(let used, let limit, let start, let reset) = window.shape else { return window }
                    return QuotaWindow(label: window.label, shape: .rollingWindow(
                        used: used * factor, limit: limit, windowStart: start, resetAt: reset))
                }
                try storage.save(ProviderSnapshot(
                    providerId: id,
                    fetchedAt: now.addingTimeInterval(-age),
                    quotas: past,
                    usageDetail: nil
                ))
            }
        }
        let scheduler = Scheduler(
            registry: registry,
            storage: storage,
            alertEngine: AlertEngine(),
            alertDispatcher: AlertDispatcher(sender: FakeNotificationSender())
        )
        let model = AppModel(registry: registry, scheduler: scheduler, storage: storage, defaults: defaults)
        await model.refreshNow()
        try await Task.sleep(nanoseconds: 200_000_000) // let onResult callbacks land
        // As três fontes de analytics reais do app (Codex, Claude Code, OpenCode). Sem
        // loaders, a aba Análise renderiza só o estado vazio.
        model.analyticsLoaders["claude"] = { [self] in
            demoAnalytics(seed: 0x5DEECE66D, scale: 1.0,
                          lifetimeTokens: 2_200_000_000, peakDailyTokens: 385_400_000,
                          currentStreakDays: 6, longestStreakDays: 8,
                          longestRunningTurnSeconds: 2673)
        }
        model.analyticsLoaders["codex"] = { [self] in
            demoAnalytics(seed: 0x1B0CA55E7, scale: 0.55, idleOdds: 3,
                          lifetimeTokens: 940_000_000, peakDailyTokens: 158_200_000,
                          currentStreakDays: 11, longestStreakDays: 19,
                          longestRunningTurnSeconds: 1412)
        }
        model.analyticsLoaders["opencode"] = { [self] in
            demoAnalytics(seed: 0x7F4A7C15, scale: 0.22, idleOdds: 6,
                          lifetimeTokens: 310_000_000, peakDailyTokens: 46_800_000,
                          currentStreakDays: 2, longestStreakDays: 5,
                          longestRunningTurnSeconds: 604)
        }
        await model.loadAllAnalyticsIfStale()
        model.menuBarPins = [
            .init(providerId: "claude", windowLabel: "5h"),
            .init(providerId: "codex", windowLabel: "semanal"),
            .init(providerId: "cursor", windowLabel: "percent")
        ]
        return model
    }

    /// Palco do painel do notch: uma faixa de "desktop" clara com o topo da tela, para o
    /// preto do painel ser julgado contra algo em vez de contra o vazio.
    private func notchStage<V: View>(@ViewBuilder content: () -> V) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, 26)
            .background(
                LinearGradient(colors: [Color(hex: 0x2C3E63), Color(hex: 0x7A5C8E)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .frame(width: 700)
    }

    /// Palco da ilha: um "desktop" ESCURO, com respiro em volta.
    ///
    /// Escuro e não claro, ao contrário do palco do notch, porque o risco muda de lado: a
    /// pílula é preta e flutua sobre o wallpaper, então o teste que importa é se ela ainda
    /// tem contorno contra um fundo escuro. Contra um fundo claro qualquer coisa preta se
    /// lê.
    private func islandStage<V: View>(@ViewBuilder content: () -> V) -> some View {
        content()
            .padding(.vertical, 30)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(
                LinearGradient(colors: [Color(hex: 0x14161C), Color(hex: 0x241C2E)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .frame(width: 700)
    }

    /// O rótulo sobre uma faixa com a cor da barra de menu REAL de cada tema — escura no
    /// escuro, clara no claro. A faixa era escura nos dois, e foi assim que um símbolo
    /// cinza-médio atravessou o redesenho parecendo aceitável: nunca tinha sido olhado
    /// contra a barra clara, e contra a escura ele passava por "discreto".
    private func menuBarStrip(_ model: AppModel, scheme: ColorScheme) -> some View {
        let dark = scheme == .dark
        return MenuBarLabelView(segment: model.menuBarSegment, onDarkBar: dark)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: dark ? 0.12 : 0.95)))
            .padding(8)
    }

    // MARK: - Rendering

    private func write<V: View>(view: V, to filename: String, scheme: ColorScheme = .dark) throws {
        // Dois eixos, porque o SwiftUI e o AppKit resolvem cor por caminhos diferentes:
        // o `environment` governa `.primary`/`.secondary`, e a aparência corrente governa
        // os `NSColor` dinâmicos dos tokens do `Theme`.
        // Ordem importa: o `.background` precisa estar DENTRO do `.environment`, senão
        // ele vira uma camada irmã, resolvida no esquema de fora — o primeiro corte saiu
        // com texto claro (esquema aplicado) sobre fundo off-white (esquema ignorado).
        let content = view
            .background(Theme.pageBackground)
            .environment(\.colorScheme, scheme)
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)!
        var png: Data?
        appearance.performAsCurrentDrawingAppearance {
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            if let image = renderer.nsImage,
               let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff) {
                png = rep.representation(using: .png, properties: [:])
            }
        }
        guard let png else {
            XCTFail("failed to render \(filename) (\(scheme))")
            return
        }
        let url = (scheme == .dark ? assetsDir : lightDir).appendingPathComponent(filename)
        try png.write(to: url)
        print("wrote \(url.path)")
    }
}


// MARK: - Dublês só para a tela de Preferências

private final class FakeTokenStore: TokenStoring {
    private var tokens: [String: OAuthToken] = [
        "claude": OAuthToken(accessToken: "demo", refreshToken: nil, expiresAt: nil, extra: [:])
    ]
    func save(_ token: OAuthToken, providerId: String) throws { tokens[providerId] = token }
    func load(providerId: String) -> OAuthToken? { tokens[providerId] }
    func delete(providerId: String) throws { tokens[providerId] = nil }
}

private struct DemoProviderError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private final class FakePreferencesMiMoSession: MiMoSessionStoring {
    var isLoggedIn = false
}


// MARK: - Maquetes do painel do notch

/// A forma do painel: preto sólido, topo reto (encosta na borda da tela) e cantos
/// INFERIORES arredondados — a "asa" que faz o painel parecer o próprio notch crescendo.
/// `DynamicNotchKit` desenha isto com uma `NotchShape` interna ao pacote; aqui a forma é
/// reproduzida só para o PNG, porque o que precisa ser julgado no render é o CONTEÚDO.
private struct NotchChrome<Content: View>: View {
    var bottomRadius: CGFloat = 22
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(
                UnevenRoundedRectangle(
                    bottomLeadingRadius: bottomRadius,
                    bottomTrailingRadius: bottomRadius,
                    style: .continuous
                ).fill(.black)
            )
    }
}

/// Altura do notch físico num MacBook Pro (`safeAreaInsets.top`), e largura típica do
/// recorte. Números do hardware, não escolha de layout — a maquete precisa deles para o
/// conteúdo cair onde vai cair de verdade.
private enum NotchMetrics {
    static let height: CGFloat = 32
    static let width: CGFloat = 190

    /// Os respiros que o `DynamicNotchKit` aplica a CADA asa (`NotchView.compactContent`:
    /// 8pt do lado de fora, 4pt em cima, 8pt embaixo). A maquete precisa dos mesmos
    /// números, senão a barra inferior — que vive dentro do respiro de baixo — aparece no
    /// PNG num lugar onde ela não vai ficar no app.
    static func wingInsets(edge: HorizontalEdge) -> EdgeInsets {
        EdgeInsets(top: 4,
                   leading: edge == .leading ? 8 : 0,
                   bottom: 8,
                   trailing: edge == .trailing ? 8 : 0)
    }
}

/// Fechado: uma cota de cada lado do recorte e a barra contínua correndo pela borda de
/// baixo, de ponta a ponta (a asa esquerda desenha a barra inteira — ver `NotchBottomRule`).
private struct NotchCollapsedMock: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        NotchChrome(bottomRadius: 14) {
            HStack(spacing: 0) {
                NotchCompactLeading(appModel: appModel)
                    .padding(NotchMetrics.wingInsets(edge: .leading))
                Spacer().frame(width: NotchMetrics.width)
                NotchCompactTrailing(appModel: appModel)
                    .padding(NotchMetrics.wingInsets(edge: .trailing))
            }
            .frame(height: NotchMetrics.height)
        }
        .fixedSize()
    }
}

/// Expandido: o recorte no topo e a lista densa embaixo dele.
private struct NotchExpandedMock: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        NotchChrome {
            VStack(spacing: 0) {
                // O conteúdo nunca sobe para debaixo do recorte físico.
                Color.clear.frame(height: NotchMetrics.height)
                NotchExpandedView(appModel: appModel, onOpen: {})
                    .padding(.horizontal, 15)
                    .padding(.bottom, 15)
            }
        }
        .fixedSize()
    }
}
