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

    init(
        registry: PluginRegistry,
        scheduler: Scheduler,
        storage: StorageManaging? = nil,
        pricingEngine: PricingEngine? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.registry = registry
        self.scheduler = scheduler
        self.storage = storage
        self.pricingEngine = pricingEngine
        self.defaults = defaults
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
    }

    func refreshNow() async {
        _ = await scheduler.fetchAll()
    }

    var menuBarSegments: [MenuBarSegment] {
        MenuBarLabelModel.segments(
            pins: menuBarPins,
            snapshots: snapshotsByProvider,
            hasAnyError: !errorsByProvider.isEmpty
        )
    }

    var orderedProviders: [UsageProvider] { registry.providers }

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
