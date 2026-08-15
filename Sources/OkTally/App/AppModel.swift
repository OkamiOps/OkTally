// Sources/OkTally/App/AppModel.swift
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshotsByProvider: [String: ProviderSnapshot] = [:]
    @Published private(set) var errorsByProvider: [String: String] = [:]
    /// Kept alongside `errorsByProvider`'s `String` messages (unchanged, still what the
    /// menu bar/cards display as text) so callers can also classify the failure — e.g.
    /// `ProviderCardView` uses this to avoid painting "not configured yet" the same red
    /// as a real fetch failure.
    @Published private(set) var errorKindByProvider: [String: ProviderErrorPresentation] = [:]

    /// 24h de histórico por provider (worst-window used%), para o sparkline dos cards.
    /// Recomputado a partir do SQLite no seed inicial e após cada fetch bem-sucedido.
    @Published private(set) var historyByProvider: [String: [UsageHistoryPoint]] = [:]

    /// Custo estimado (USD) por provider, calculado quando um snapshot traz `usageDetail`
    /// e o `PricingEngine` conhece os modelos. Ausente = sem dados para precificar.
    @Published private(set) var estimatedCostByProvider: [String: Decimal] = [:]

    /// Deep-link das Preferências: setado pelos botões "Reconectar"/"Configurar" do
    /// popover imediatamente antes de abrir Ajustes; `PreferencesView` consome e zera.
    @Published var requestedPreferencesPane: String?

    /// Release do GitHub mais nova que a versão instalada, quando existe. Checado ao
    /// iniciar e a cada 24h; falha de rede deixa como está.
    @Published private(set) var availableUpdate: UpdateInfo?
    var updateFetcher: LatestReleaseFetching?
    var currentVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

    func checkForUpdates() async {
        guard let updateFetcher else { return }
        guard let remote = try? await updateFetcher.fetchLatestRelease() else { return }
        availableUpdate = UpdateChecker.availableUpdate(remote: remote, currentVersion: currentVersion)
    }

    /// Estatísticas de uso em tokens por provider (heatmap/streaks), carregadas sob
    /// demanda quando as páginas de análise abrem. Fontes registradas em
    /// `analyticsLoaders` pelo app (Codex via OAuth; Claude/OpenCode lendo disco local).
    @Published private(set) var analyticsByProvider: [String: TokenAnalytics] = [:]
    private var analyticsLoadedAt: [String: Date] = [:]
    var analyticsLoaders: [String: () async -> TokenAnalytics?] = [:]

    /// Providers com fonte de analytics, na ordem do registry (para a aba "Análise").
    var analyticsProviderIds: [String] {
        orderedProviders.map(\.id).filter { analyticsLoaders[$0] != nil }
    }

    var aggregatedAnalytics: TokenAnalytics? {
        TokenAnalytics.aggregate(analyticsProviderIds.compactMap { analyticsByProvider[$0] })
    }

    func loadAnalyticsIfStale(providerId: String, maxAge: TimeInterval = 300) async {
        if let loadedAt = analyticsLoadedAt[providerId], Date().timeIntervalSince(loadedAt) < maxAge { return }
        guard let loader = analyticsLoaders[providerId] else { return }
        if let analytics = await loader() {
            analyticsByProvider[providerId] = analytics
            analyticsLoadedAt[providerId] = Date()
        }
    }

    func loadAllAnalyticsIfStale() async {
        for providerId in analyticsProviderIds {
            await loadAnalyticsIfStale(providerId: providerId)
        }
    }

    /// The quota windows shown in the menu bar, in the order they were pinned. Empty =
    /// automatic (worst window across all providers). Persisted across relaunches.
    @Published var menuBarPins: [MenuBarPin] {
        didSet {
            let joined = menuBarPins.map(\.stored).joined(separator: "\u{2}")
            if joined.isEmpty {
                defaults.removeObject(forKey: Self.menuBarPinsKey)
            } else {
                defaults.set(joined, forKey: Self.menuBarPinsKey)
            }
        }
    }
    /// Escolha de exibição de cada lugar: as duas asas do notch fechado e o número da
    /// barra de menu. `@Published` (e não lido do store a cada acesso) porque as views do
    /// notch observam este modelo — trocar o picker nas Preferências tem que repintar a
    /// asa na hora, sem reabrir nada. A gravação vai para o `PreferencesStore`, que é onde
    /// mora toda a preferência do app.
    @Published var notchLeadingSlot: QuotaSlot { didSet { preferences.notchLeadingSlot = notchLeadingSlot } }
    @Published var notchTrailingSlot: QuotaSlot { didSet { preferences.notchTrailingSlot = notchTrailingSlot } }
    @Published var notchBottomSlot: QuotaSlot { didSet { preferences.notchBottomSlot = notchBottomSlot } }
    @Published var menuBarSlot: QuotaSlot { didSet { preferences.menuBarSlot = menuBarSlot } }
    /// O card-herói do popover — quinto lugar escolhível, junto dos quatro acima. Mora
    /// aqui e não só no `PreferencesStore` pelo mesmo motivo dos outros quatro: o
    /// popover observa este modelo, e trocar o picker tem que repintar o card na hora.
    @Published var popoverHeroSlot: QuotaSlot { didSet { preferences.popoverHeroSlot = popoverHeroSlot } }

    /// A escala de cor do uso. `@Published` pelo mesmo motivo dos slots: editar as
    /// paradas em Preferências tem que repintar TODA a tela na hora, e as views observam
    /// este modelo.
    ///
    /// O `didSet` mantém três coisas em sincronia: o disco (`PreferencesStore`), o holder
    /// global que `QuotaPresentation` consulta (`UsageColorScaleHolder`, que é o único
    /// caminho possível para um enum estático chamado de dentro do `ImageRenderer` da
    /// barra de menu) e a própria publicação. A fonte de verdade é esta propriedade;
    /// ninguém mais escreve no holder.
    @Published var usageColorScale: UsageColorScale {
        didSet {
            preferences.usageColorScale = usageColorScale
            UsageColorScaleHolder.current = usageColorScale
        }
    }

    private static let menuBarPinsKey = "menuBarPins"
    private static let legacyMenuBarPinKey = "menuBarPin"
    private let defaults: UserDefaults

    struct MenuBarPin: Equatable {
        let providerId: String
        let windowLabel: String
        var stored: String { "\(providerId)\u{1}\(windowLabel)" }
        init(providerId: String, windowLabel: String) {
            self.providerId = providerId
            self.windowLabel = windowLabel
        }
        init?(stored: String?) {
            guard let parts = stored?.split(separator: "\u{1}", maxSplits: 1), parts.count == 2 else { return nil }
            self.providerId = String(parts[0])
            self.windowLabel = String(parts[1])
        }
    }

    private let registry: PluginRegistry
    private let scheduler: Scheduler
    private let storage: StorageManaging?
    private let pricingEngine: PricingEngine?
    private let preferences: PreferencesStore

    init(
        registry: PluginRegistry,
        scheduler: Scheduler,
        storage: StorageManaging? = nil,
        pricingEngine: PricingEngine? = nil,
        defaults: UserDefaults = .standard,
        preferences: PreferencesStore? = nil
    ) {
        self.registry = registry
        self.scheduler = scheduler
        self.storage = storage
        self.pricingEngine = pricingEngine
        self.defaults = defaults
        // Sobre os MESMOS `defaults` do modelo: um store construído à parte apontaria
        // para `UserDefaults.standard` e um teste com suite própria vazaria para a
        // preferência real do dono.
        let preferences = preferences ?? PreferencesStore(store: defaults)
        self.preferences = preferences
        self.notchLeadingSlot = preferences.notchLeadingSlot
        self.notchTrailingSlot = preferences.notchTrailingSlot
        self.notchBottomSlot = preferences.notchBottomSlot
        self.menuBarSlot = preferences.menuBarSlot
        self.popoverHeroSlot = preferences.popoverHeroSlot
        self.usageColorScale = preferences.usageColorScale
        if let joined = defaults.string(forKey: Self.menuBarPinsKey) {
            self.menuBarPins = joined.split(separator: "\u{2}").compactMap { MenuBarPin(stored: String($0)) }
        } else if let legacy = MenuBarPin(stored: defaults.string(forKey: Self.legacyMenuBarPinKey)) {
            self.menuBarPins = [legacy]
            defaults.removeObject(forKey: Self.legacyMenuBarPinKey)
        } else {
            self.menuBarPins = []
        }
        // Seed from the last persisted snapshot per provider so a relaunch (or a provider
        // whose next fetch fails) shows the last known usage instead of nothing. Each
        // snapshot carries its own `fetchedAt`, so the UI can label it as stale.
        if let storage {
            for provider in registry.providers {
                if let snapshot = try? storage.latestSnapshot(providerId: provider.id), !snapshot.quotas.isEmpty {
                    snapshotsByProvider[provider.id] = snapshot
                }
                refreshHistory(providerId: provider.id)
            }
        }
        // O holder só é povoado depois de `self` estar inteiro (o `didSet` não roda para
        // atribuições feitas dentro do `init`).
        UsageColorScaleHolder.current = usageColorScale
        scheduler.onResult = { [weak self] result in
            Task { @MainActor in self?.apply(result) }
        }
    }

    func togglePin(providerId: String, windowLabel: String) {
        let pin = MenuBarPin(providerId: providerId, windowLabel: windowLabel)
        if let index = menuBarPins.firstIndex(of: pin) {
            menuBarPins.remove(at: index)
        } else {
            menuBarPins.append(pin)
        }
    }

    func isPinned(providerId: String, windowLabel: String) -> Bool {
        menuBarPins.contains(MenuBarPin(providerId: providerId, windowLabel: windowLabel))
    }

    func start() {
        scheduler.startPeriodicLoop()
        Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkForUpdates()
                try? await Task.sleep(nanoseconds: 24 * 3600 * 1_000_000_000)
            }
        }
    }

    func refreshNow() async {
        _ = await scheduler.fetchAll()
    }

    /// O único número da barra de menu — o do slot escolhido, ou o mais crítico quando
    /// o slot é automático.
    var menuBarSegment: MenuBarSegment {
        MenuBarLabelModel.segment(
            slot: menuBarSlot,
            pins: menuBarPins,
            snapshots: snapshotsByProvider,
            hasAnyError: !errorsByProvider.isEmpty
        )
    }

    /// As duas asas do notch fechado. Resolvidas juntas para que, em automático, elas não
    /// mostrem a mesma cota dos dois lados.
    var notchWings: (leading: MenuBarSegment?, trailing: MenuBarSegment?) {
        let pair = QuotaSlotResolver.wings(
            leading: notchLeadingSlot,
            trailing: notchTrailingSlot,
            pins: menuBarPins,
            snapshots: snapshotsByProvider,
            providerOrder: orderedProviders.map(\.id)
        )
        return (pair.leading.map(MenuBarLabelModel.segment(for:)),
                pair.trailing.map(MenuBarLabelModel.segment(for:)))
    }

    /// A barra fina da borda inferior do notch fechado. `nil` quando não há nenhuma
    /// janela com percentual — a barra some em vez de inventar um preenchimento.
    var notchBottomBar: NotchBottomBar? {
        QuotaSlotResolver.bottomBar(
            slot: notchBottomSlot,
            pins: menuBarPins,
            snapshots: snapshotsByProvider,
            providerOrder: orderedProviders.map(\.id)
        )
    }

    /// As janelas que os `Picker`s das Preferências oferecem, além de "Automático".
    var availableQuotaSlots: [QuotaSlot] {
        QuotaSlotResolver.availableWindows(
            snapshots: snapshotsByProvider,
            providerOrder: orderedProviders.map(\.id)
        )
    }

    /// As cotas do painel do notch — as mesmas fechado e expandido.
    var notchEntries: [NotchQuotaEntry] {
        NotchHUDModel.entries(
            pins: menuBarPins,
            snapshots: snapshotsByProvider,
            providerOrder: orderedProviders.map(\.id)
        )
    }

    var orderedProviders: [UsageProvider] { registry.providers }

    /// Série sob demanda com janela arbitrária (a janela principal mostra 7 dias; o
    /// popover usa o `historyByProvider` de 24h já publicado).
    func history(providerId: String, hours: Int, now: Date = Date()) -> [UsageHistoryPoint] {
        guard let storage else { return [] }
        let since = now.addingTimeInterval(-Double(hours) * 3600)
        guard let snapshots = try? storage.snapshots(providerId: providerId, since: since) else { return [] }
        return UsageHistory.worstUsedSeries(snapshots)
    }

    private func refreshHistory(providerId: String, now: Date = Date()) {
        guard let storage else { return }
        let since = now.addingTimeInterval(-24 * 3600)
        guard let snapshots = try? storage.snapshots(providerId: providerId, since: since) else { return }
        let series = UsageHistory.worstUsedSeries(snapshots)
        // Só publica séries plotáveis; um ponto único não desenha linha.
        historyByProvider[providerId] = series.count >= 2 ? series : []
    }

    private func refreshEstimatedCost(for snapshot: ProviderSnapshot) {
        guard let pricingEngine, let details = snapshot.usageDetail, !details.isEmpty else { return }
        let providerId = snapshot.providerId
        Task { [weak self] in
            // Falha de rede na tabela de preços não é erro do provider — só deixa o
            // custo ausente até a próxima tentativa.
            try? await pricingEngine.refreshIfStale()
            let cost = await pricingEngine.estimatedCost(for: details)
            await MainActor.run { [weak self] in
                self?.estimatedCostByProvider[providerId] = cost
            }
        }
    }

    private func apply(_ result: SchedulerFetchResult) {
        switch result.outcome {
        case .success(let snapshot):
            snapshotsByProvider[result.providerId] = snapshot
            errorsByProvider[result.providerId] = nil
            errorKindByProvider[result.providerId] = nil
            refreshHistory(providerId: result.providerId)
            refreshEstimatedCost(for: snapshot)
        case .failure(let error):
            errorsByProvider[result.providerId] = error.localizedDescription
            errorKindByProvider[result.providerId] = ProviderErrorPresentation.classify(error)
        }
    }
}
