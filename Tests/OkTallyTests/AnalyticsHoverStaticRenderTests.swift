import AppKit
import SwiftUI
import XCTest
@testable import OkTally

/// Prova por imagem que o hover DESENHA o que prometeu e não vaza do gráfico.
///
/// Dois limites do harness explicam a forma deste arquivo. O primeiro: `ImageRenderer` não
/// garante a árvore de marcas do Swift Charts, então o desenho passa por `NSHostingView` +
/// `cacheDisplay(in:to:)` — mesmo caminho do `ForecastStaticRenderTests`. A janela existe
/// só para hospedar a árvore offscreen; nunca é aberta nem ativada.
///
/// O segundo: não há cursor num render offscreen. `onContinuousHover` e
/// `chartAngleSelection` nunca disparam, e o estado mais fácil de estragar — cartão cortado
/// pela borda do card — seria justamente o que nenhuma imagem mostraria. Daí
/// `ChartHoverPreview` no ambiente, que força a seleção pelo mesmo mecanismo com que
/// `isStaticRender` já troca os controles do AppKit. O app nunca preenche nenhum dos dois.
@MainActor
final class AnalyticsHoverStaticRenderTests: XCTestCase {
    /// Hoje, à meia-noite. Não dá para cravar uma data fixa aqui: as views recortam a
    /// janela com `Date()` por dentro (`TrendSeries.points`, `TokenHeatmapView`), então uma
    /// série ancorada num dia fixo cairia fora da janela de 30 dias e a aba inteira
    /// renderizaria "Sem dados no período" — um PNG verde que não prova nada. O formato dos
    /// valores continua determinístico: `tokens(offset:)` é função pura do deslocamento.
    private let now = Calendar(identifier: .gregorian).startOfDay(for: Date())

    private var artifactsDir: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("OkTally-hover", isDirectory: true)
    }

    // MARK: - Área do herói

    func test_heroAreaChartDrawsNoCardUntilADayIsSelected() throws {
        let clean = try render(
            heroStage { DailyTokensAreaChart(points: series, color: Theme.onHero, hover: .card) },
            size: CGSize(width: 420, height: 170),
            name: "hero-sem-hover"
        )
        // O cartão é a ÚNICA coisa escura dentro de um bloco de gradiente ciano: se ele não
        // foi desenhado, não existe pixel de superfície nenhum ali.
        XCTAssertLessThan(surfacePixels(in: clean), 60, "cartão apareceu sem seleção nenhuma")
    }

    func test_heroAreaChartDrawsTheCardForTheSelectedDay() throws {
        let hovered = try render(
            heroStage { DailyTokensAreaChart(points: series, color: Theme.onHero, hover: .card) },
            size: CGSize(width: 420, height: 170),
            name: "hero-hover-meio",
            preview: ChartHoverPreview(day: series[6].day)
        )
        XCTAssertGreaterThan(surfacePixels(in: hovered), 600, "o cartão do herói não desenhou")
    }

    func test_heroCardFlipsSidesOnTheLastDayInsteadOfBeingClipped() throws {
        // O último dia é o que o dono mais olha e o pior caso da posição: "ao lado direito
        // do cursor" colocaria o cartão fora do gráfico.
        let bitmap = try render(
            heroStage { DailyTokensAreaChart(points: series, color: Theme.onHero, hover: .card) },
            size: CGSize(width: 420, height: 170),
            name: "hero-hover-ultimo-dia",
            preview: ChartHoverPreview(day: series.last!.day)
        )
        let card = try XCTUnwrap(surfaceBounds(in: bitmap), "cartão ausente no último dia")
        XCTAssertGreaterThan(card.minX, 0, "cartão cortado à esquerda")
        XCTAssertLessThan(card.maxX, CGFloat(bitmap.pixelsWide) - 1, "cartão cortado à direita")
        XCTAssertGreaterThan(card.minY, 0, "cartão cortado na base")
        XCTAssertLessThan(card.maxY, CGFloat(bitmap.pixelsHigh) - 1, "cartão cortado no topo")
    }

    func test_heroCardStaysInsideEvenOnTheFirstDay() throws {
        let bitmap = try render(
            heroStage { DailyTokensAreaChart(points: series, color: Theme.onHero, hover: .card) },
            size: CGSize(width: 420, height: 170),
            name: "hero-hover-primeiro-dia",
            preview: ChartHoverPreview(day: series[0].day)
        )
        let card = try XCTUnwrap(surfaceBounds(in: bitmap), "cartão ausente no primeiro dia")
        XCTAssertGreaterThan(card.minX, 0, "cartão cortado à esquerda")
        XCTAssertLessThan(card.maxX, CGFloat(bitmap.pixelsWide) - 1, "cartão cortado à direita")
    }

    // MARK: - Barras empilhadas

    func test_stackedBarsChangeWhenADayIsSelected() throws {
        let clean = try render(
            cardStage { StackedProviderBarChart(points: trendPoints, providerName: { $0.capitalized }) },
            size: CGSize(width: 620, height: 240),
            name: "barras-sem-hover"
        )
        let hovered = try render(
            cardStage { StackedProviderBarChart(points: trendPoints, providerName: { $0.capitalized }) },
            size: CGSize(width: 620, height: 240),
            name: "barras-hover",
            preview: ChartHoverPreview(day: trendPoints[10].day)
        )
        // O rebaixamento das outras barras mais o cartão mexem em muito pixel; um gráfico
        // que ignorasse a seleção sairia idêntico.
        XCTAssertGreaterThan(differingPixels(clean, hovered), 3_000, "as barras não reagiram à seleção")
        assertUnclipped(hovered, named: "barras-hover")
    }

    // MARK: - Heatmap

    func test_heatmapChangesWhenACellIsSelected() throws {
        let analytics = TokenAnalytics(dailyBuckets: dailyBuckets(days: 120, scale: 1))
        let clean = try render(
            cardStage { TokenHeatmapView(analytics: analytics) },
            size: CGSize(width: 620, height: 200),
            name: "heatmap-sem-hover"
        )
        let hovered = try render(
            cardStage { TokenHeatmapView(analytics: analytics) },
            size: CGSize(width: 620, height: 200),
            name: "heatmap-hover",
            preview: ChartHoverPreview(day: dayKey(offsetFromToday: 9))
        )
        XCTAssertGreaterThan(differingPixels(clean, hovered), 800, "a célula não reagiu à seleção")
        assertUnclipped(hovered, named: "heatmap-hover")
    }

    // MARK: - Donut

    func test_donutHighlightsTheSelectedSector() throws {
        let share = [
            (providerId: "claude", tokens: 520_000_000),
            (providerId: "codex", tokens: 310_000_000),
            (providerId: "opencode", tokens: 90_000_000)
        ]
        let clean = try render(
            cardStage { ProviderShareDonut(share: share, providerName: { $0.capitalized }).frame(height: 150) },
            size: CGSize(width: 240, height: 200),
            name: "donut-sem-hover"
        )
        let hovered = try render(
            cardStage { ProviderShareDonut(share: share, providerName: { $0.capitalized }).frame(height: 150) },
            size: CGSize(width: 240, height: 200),
            name: "donut-hover",
            preview: ChartHoverPreview(providerId: "codex")
        )
        // A fatia cresce, as outras caem para 28% e o miolo troca de texto.
        XCTAssertGreaterThan(differingPixels(clean, hovered), 1_500, "o donut não reagiu à seleção")
        assertUnclipped(hovered, named: "donut-hover")
    }

    // MARK: - Previsão

    func test_forecastChartShowsEverySeriesAtTheHoveredInstant() throws {
        let clean = try render(
            cardStage {
                ForecastChartView(forecast: forecast, providerColor: ProviderPalette.color(for: "claude"), now: now)
            },
            size: CGSize(width: 620, height: 260),
            name: "previsao-sem-hover"
        )
        let hovered = try render(
            cardStage {
                ForecastChartView(forecast: forecast, providerColor: ProviderPalette.color(for: "claude"), now: now)
            },
            size: CGSize(width: 620, height: 260),
            name: "previsao-hover",
            // Qualquer preview basta: a previsão encaixa no último ponto do histórico, que
            // é o vértice mais à direita do dado REAL — e o pior caso de posição.
            preview: ChartHoverPreview(day: dayKey(offsetFromToday: 0))
        )
        XCTAssertGreaterThan(differingPixels(clean, hovered), 1_500, "a previsão não reagiu à seleção")
        assertUnclipped(hovered, named: "previsao-hover")
    }

    private var forecast: UsageForecast {
        let hour: TimeInterval = 3_600
        return UsageForecast(
            id: ForecastWindowID(providerId: "claude", windowLabel: "weekly"),
            cadence: .weekly,
            currentUsedPercent: 56,
            samples: [
                UsageHistoryPoint(date: now.addingTimeInterval(-20 * hour), usedPercent: 28),
                UsageHistoryPoint(date: now.addingTimeInterval(-14 * hour), usedPercent: 35),
                UsageHistoryPoint(date: now.addingTimeInterval(-8 * hour), usedPercent: 41),
                UsageHistoryPoint(date: now.addingTimeInterval(-2 * hour), usedPercent: 49),
                UsageHistoryPoint(date: now, usedPercent: 56)
            ],
            ratePerDay: 28,
            safeRatePerDay: 14,
            exhaustionAt: now.addingTimeInterval(16 * hour),
            resetAt: now.addingTimeInterval(24 * hour),
            gap: 8 * hour,
            state: .slowDown
        )
    }

    // MARK: - A aba inteira

    func test_analyticsDashboardRendersEveryTooltipUnclipped() async throws {
        let model = try await demoModel()
        let view = AnalyticsDashboardView(appModel: model)
            .environment(\.isStaticRender, true)
            .padding(24)
            .frame(width: 860)

        let clean = try render(view, size: CGSize(width: 860, height: 980), name: "aba-sem-hover")
        let hovered = try render(
            view,
            size: CGSize(width: 860, height: 980),
            name: "aba-hover",
            preview: ChartHoverPreview(day: dayKey(offsetFromToday: 0), providerId: "codex")
        )
        XCTAssertGreaterThan(differingPixels(clean, hovered), 4_000, "a aba não reagiu à seleção")
        assertUnclipped(hovered, named: "aba-hover")
    }

    // MARK: - Dados

    /// Catorze dias com um vale no meio: uma série plana não distingue "encaixou no dia
    /// certo" de "encaixou em qualquer dia".
    private var series: [DailyTokens] {
        dailyBuckets(days: 14, scale: 1)
    }

    private var trendPoints: [TrendPoint] {
        let providers: [(String, Double)] = [("claude", 1), ("codex", 0.55), ("opencode", 0.22)]
        return (0..<30).flatMap { offset -> [TrendPoint] in
            providers.map { id, scale in
                TrendPoint(day: dayKey(offsetFromToday: offset),
                           providerId: id,
                           tokens: tokens(offset: offset, scale: scale))
            }
        }
        .sorted { ($0.day, $0.providerId) < ($1.day, $1.providerId) }
    }

    private func dailyBuckets(days: Int, scale: Double) -> [DailyTokens] {
        (0..<days).reversed().map { offset in
            DailyTokens(day: dayKey(offsetFromToday: offset), tokens: tokens(offset: offset, scale: scale))
        }
    }

    /// Forma determinística (nada de aleatório: o PNG tem de ser o mesmo a cada execução),
    /// com um dia zerado para o heatmap ter célula apagada e o cartão ter o caso "sem uso".
    private func tokens(offset: Int, scale: Double) -> Int {
        if offset == 4 { return 0 }
        let wave = 1 + sin(Double(offset) * 0.7) * 0.6
        return Int(Double(38_000_000) * wave * scale) + offset * 210_000
    }

    private func dayKey(offsetFromToday offset: Int) -> String {
        let date = Calendar(identifier: .gregorian).date(byAdding: .day, value: -offset, to: now)!
        return TokenAnalytics.dayKey(date)
    }

    /// Modelo mínimo para a aba: três fontes de analytics e nenhum snapshot. Sem loaders a
    /// aba renderiza só o estado vazio, e sem snapshot a faixa de cotas simplesmente não
    /// aparece — que é o recorte que estes PNGs precisam olhar.
    private func demoModel() async throws -> AppModel {
        let registry = PluginRegistry()
        for (id, name) in [("claude", "Claude Code"), ("codex", "Codex"), ("opencode", "OpenCode")] {
            registry.register(FakeUsageProvider(id: id, displayName: name))
        }
        let defaults = UserDefaults(suiteName: "AnalyticsHoverStaticRenderTests")!
        defaults.removePersistentDomain(forName: "AnalyticsHoverStaticRenderTests")
        let storage = FakeStorage()
        let scheduler = Scheduler(
            registry: registry,
            storage: storage,
            alertEngine: AlertEngine(),
            alertDispatcher: AlertDispatcher(sender: FakeNotificationSender())
        )
        let model = AppModel(registry: registry, scheduler: scheduler, storage: storage, defaults: defaults)
        let scales: [String: Double] = ["claude": 1, "codex": 0.55, "opencode": 0.22]
        for (id, scale) in scales {
            model.analyticsLoaders[id] = { [self] in
                TokenAnalytics(
                    lifetimeTokens: Int(2_200_000_000 * scale),
                    peakDailyTokens: Int(385_400_000 * scale),
                    currentStreakDays: 6,
                    longestStreakDays: 9,
                    longestRunningTurnSeconds: 2_673,
                    dailyBuckets: dailyBuckets(days: 120, scale: scale)
                )
            }
        }
        await model.loadAllAnalyticsIfStale()
        return model
    }

    // MARK: - Palcos

    /// O bloco-herói: gradiente ciano saturado. É contra ele que o cartão escuro precisa
    /// se destacar, e é nele que um cartão translúcido teria sido reprovado.
    private func heroStage<V: View>(@ViewBuilder content: () -> V) -> some View {
        content()
            .padding(Theme.Space.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .heroSurface(Theme.accent)
    }

    private func cardStage<V: View>(@ViewBuilder content: () -> V) -> some View {
        DashboardCard { content() }
    }

    // MARK: - Render

    private func render<V: View>(
        _ content: V,
        size: CGSize,
        name: String,
        preview: ChartHoverPreview? = nil
    ) throws -> NSBitmapImageRep {
        let view = ZStack {
            Rectangle().fill(Theme.pageBackground)
            content.padding(Theme.Space.md)
        }
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, .dark)
        .environment(\.chartHoverPreview, preview)

        let host = NSHostingView(rootView: AnyView(view))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.frame = window.contentView?.bounds ?? NSRect(origin: .zero, size: size)
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        window.display()
        // Um giro do run loop para o Swift Charts concluir a árvore de marcas — e, aqui,
        // para o `onGeometryChange` que mede o cartão fechar o ciclo antes do bitmap.
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        window.display()

        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds), "sem bitmap para \(name)")
        host.cacheDisplay(in: host.bounds, to: bitmap)

        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]), "falha ao codificar \(name)")
        try FileManager.default.createDirectory(at: artifactsDir, withIntermediateDirectories: true)
        let url = artifactsDir.appendingPathComponent("\(name).png")
        try png.write(to: url, options: .atomic)
        print("hover render: \(url.path)")
        return bitmap
    }

    // MARK: - Leitura do bitmap

    /// Pixels na cor da superfície de card no escuro (`#1B1D20`) — a assinatura do cartão.
    private func surfacePixels(in bitmap: NSBitmapImageRep) -> Int {
        var count = 0
        forEachPixel(bitmap) { _, _, pixel in
            if isSurface(pixel) { count += 1 }
        }
        return count
    }

    private func surfaceBounds(in bitmap: NSBitmapImageRep) -> CGRect? {
        var bounds: CGRect?
        var count = 0
        forEachPixel(bitmap) { x, y, pixel in
            guard isSurface(pixel) else { return }
            count += 1
            let point = CGRect(x: x, y: y, width: 1, height: 1)
            bounds = bounds.map { $0.union(point) } ?? point
        }
        return count > 400 ? bounds : nil
    }

    private func isSurface(_ pixel: NSColor) -> Bool {
        let target = NSColor(hex: 0x1B1D20).usingColorSpace(.sRGB) ?? .black
        return max(
            abs(pixel.redComponent - target.redComponent),
            abs(pixel.greenComponent - target.greenComponent),
            abs(pixel.blueComponent - target.blueComponent)
        ) < 0.02
    }

    private func differingPixels(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep) -> Int {
        guard lhs.pixelsWide == rhs.pixelsWide, lhs.pixelsHigh == rhs.pixelsHigh else {
            XCTFail("bitmaps de tamanhos diferentes")
            return 0
        }
        var count = 0
        for y in 0..<lhs.pixelsHigh {
            for x in 0..<lhs.pixelsWide {
                guard let a = lhs.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      let b = rhs.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let delta = max(
                    abs(a.redComponent - b.redComponent),
                    abs(a.greenComponent - b.greenComponent),
                    abs(a.blueComponent - b.blueComponent)
                )
                if delta > 0.04 { count += 1 }
            }
        }
        return count
    }

    private func assertUnclipped(_ bitmap: NSBitmapImageRep, named name: String) {
        guard let background = bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB) else {
            return XCTFail("\(name): não foi possível ler o fundo")
        }
        var bounds: CGRect?
        var ink = 0
        forEachPixel(bitmap) { x, y, pixel in
            let differs = max(
                abs(pixel.redComponent - background.redComponent),
                abs(pixel.greenComponent - background.greenComponent),
                abs(pixel.blueComponent - background.blueComponent)
            ) > 0.04
            guard differs else { return }
            ink += 1
            let point = CGRect(x: x, y: y, width: 1, height: 1)
            bounds = bounds.map { $0.union(point) } ?? point
        }
        XCTAssertGreaterThan(ink, 500, "\(name): conteúdo insuficiente")
        guard let bounds else { return }
        XCTAssertGreaterThan(bounds.minX, 1, "\(name): conteúdo cortado à esquerda")
        XCTAssertGreaterThan(bounds.minY, 1, "\(name): conteúdo cortado na base")
        XCTAssertLessThan(bounds.maxX, CGFloat(bitmap.pixelsWide - 1), "\(name): conteúdo cortado à direita")
        XCTAssertLessThan(bounds.maxY, CGFloat(bitmap.pixelsHigh - 1), "\(name): conteúdo cortado no topo")
    }

    private func forEachPixel(_ bitmap: NSBitmapImageRep, _ body: (Int, Int, NSColor) -> Void) {
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                body(x, y, pixel)
            }
        }
    }
}
