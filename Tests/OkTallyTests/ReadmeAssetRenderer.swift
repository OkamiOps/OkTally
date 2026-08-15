// Tests/OkTallyTests/ReadmeAssetRenderer.swift
//
// Not a test of behavior: renders the real SwiftUI views with demo data into
// docs/assets/*.png for the README. Runs only when RENDER_README_ASSETS=1 so the
// normal suite stays fast:
//
//   RENDER_README_ASSETS=1 swift test --filter ReadmeAssetRenderer
//
import XCTest
import SwiftUI
@testable import OkTally

@MainActor
final class ReadmeAssetRenderer: XCTestCase {
    private var assetsDir: URL {
        // Tests run from the package root.
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/assets")
    }

    func test_renderReadmeAssets() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RENDER_README_ASSETS"] == "1")
        try FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)

        let model = try await demoModel()
        try write(view: PopoverContentView(appModel: model)
                    .environment(\.isStaticRender, true)
                    .frame(width: 360)
                    .background(Color(nsColor: .windowBackgroundColor)),
                  to: "popover.png")
        try write(view: menuBarStrip(model), to: "menubar.png")
        try write(view: OverviewScreen(
                        appModel: model,
                        entries: model.orderedProviders.compactMap { provider in
                            model.snapshotsByProvider[provider.id].map { (provider, $0) }
                        },
                        onSelect: { _ in })
                    .padding(24)
                    .frame(width: 760)
                    .background(Color(nsColor: .windowBackgroundColor)),
                  to: "overview.png")
        // `isStaticRender` troca só os controles do AppKit por um desenho equivalente:
        // o `ImageRenderer` não sabe desenhá-los e o PNG sairia com um retângulo amarelo
        // no lugar do seletor de janela. O app não liga essa flag.
        try write(view: AnalyticsDashboardView(appModel: model)
                    .environment(\.isStaticRender, true)
                    .padding(24)
                    .frame(width: 860)
                    .background(Color(nsColor: .windowBackgroundColor)),
                  to: "analytics.png")
        // O `ProviderPaneScaffold` ficou de fora de propósito: o `ImageRenderer` não
        // desenha `Form` agrupado (o mesmo motivo pelo qual o pane Geral também não é
        // renderizado aqui) e o PNG saía inteiramente em branco. Os painéis de provider
        // se conferem abrindo o app.
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

    /// The menu bar label on a dark menu-bar-like strip.
    private func menuBarStrip(_ model: AppModel) -> some View {
        MenuBarLabelView(segments: model.menuBarSegments)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.12)))
            .padding(8)
    }

    // MARK: - Rendering

    private func write<V: View>(view: V, to filename: String) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("failed to render \(filename)")
            return
        }
        let url = assetsDir.appendingPathComponent(filename)
        try png.write(to: url)
        print("wrote \(url.path)")
    }
}
