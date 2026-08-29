// Tests/OkTallyTests/AppModelTests.swift
import XCTest
@testable import OkTally

@MainActor
final class AppModelTests: XCTestCase {
    /// Simula a janela entre `Scheduler.onResult(.success)` e `storage.save(snapshot)`:
    /// o modelo já tem a leitura atual, mas a consulta de histórico ainda não a enxerga.
    private final class ForecastHistoryLagStorage: StorageManaging {
        private let latest: ProviderSnapshot
        private let historicalSnapshots: [ProviderSnapshot]

        init(latest: ProviderSnapshot, historicalSnapshots: [ProviderSnapshot]) {
            self.latest = latest
            self.historicalSnapshots = historicalSnapshots
        }

        func save(_ snapshot: ProviderSnapshot) throws {}

        func latestSnapshot(providerId: String) throws -> ProviderSnapshot? {
            latest.providerId == providerId ? latest : nil
        }

        func snapshots(providerId: String, since: Date) throws -> [ProviderSnapshot] {
            historicalSnapshots.filter {
                $0.providerId == providerId && $0.fetchedAt >= since
            }
        }

        func prune(olderThan cutoff: Date) throws {}
    }

    private final class ForecastReadFailingStorage: StorageManaging {
        var snapshotsByProvider: [String: [ProviderSnapshot]] = [:]
        var shouldFailSnapshotsRead = false

        func save(_ snapshot: ProviderSnapshot) throws {
            snapshotsByProvider[snapshot.providerId, default: []].append(snapshot)
        }

        func latestSnapshot(providerId: String) throws -> ProviderSnapshot? {
            snapshotsByProvider[providerId]?.last
        }

        func snapshots(providerId: String, since: Date) throws -> [ProviderSnapshot] {
            if shouldFailSnapshotsRead { throw FakeError.boom }
            return (snapshotsByProvider[providerId] ?? []).filter { $0.fetchedAt >= since }
        }

        func prune(olderThan cutoff: Date) throws {}
    }

    private let forecastHour: TimeInterval = 3_600

    private func renewableForecastSnapshots(
        providerId: String = "claude",
        now: Date
    ) -> [ProviderSnapshot] {
        let resetAt = now.addingTimeInterval(24 * forecastHour)
        return [(-6.0, 10.0), (-5, 15), (-4, 20), (-3, 25), (-2, 30), (0, 40)].map { hoursAgo, used in
            ProviderSnapshot(
                providerId: providerId,
                fetchedAt: now.addingTimeInterval(hoursAgo * forecastHour),
                quotas: [
                    QuotaWindow(
                        label: "weekly",
                        shape: .periodicCounter(used: used, limit: 100, resetAt: resetAt),
                        renewalCadence: .weekly
                    )
                ],
                usageDetail: nil
            )
        }
    }

    private func forecastScheduler(registry: PluginRegistry, storage: StorageManaging) -> Scheduler {
        Scheduler(
            registry: registry,
            storage: storage,
            alertEngine: AlertEngine(),
            alertDispatcher: AlertDispatcher(sender: FakeNotificationSender())
        )
    }

    private func waitForForecast(
        _ id: ForecastWindowID,
        in model: AppModel,
        matching predicate: @escaping (UsageForecast) -> Bool = { _ in true }
    ) async -> UsageForecast? {
        for _ in 0..<100 {
            if let forecast = model.forecastsByWindow[id], predicate(forecast) {
                return forecast
            }
            await Task.yield()
        }
        return nil
    }

    func test_refreshNow_populatesSnapshotsAndErrors() async {
        let good = FakeUsageProvider(id: "openrouter", displayName: "OpenRouter")
        good.snapshotToReturn = ProviderSnapshot(providerId: "openrouter", fetchedAt: Date(), quotas: [], usageDetail: nil)
        let bad = FakeUsageProvider(id: "claude", displayName: "Claude Code")
        bad.errorToThrow = FakeError.boom
        let registry = PluginRegistry()
        registry.register(good)
        registry.register(bad)
        let scheduler = Scheduler(
            registry: registry,
            storage: FakeStorage(),
            alertEngine: AlertEngine(),
            alertDispatcher: AlertDispatcher(sender: FakeNotificationSender())
        )
        let model = AppModel(registry: registry, scheduler: scheduler)

        await model.refreshNow()

        XCTAssertNotNil(model.snapshotsByProvider["openrouter"])
        XCTAssertNotNil(model.errorsByProvider["claude"])
    }

    /// IMPORTANT 5 regression: a provider that simply hasn't been configured yet (the
    /// common first-launch state for all 8 providers) must classify as `.notConfigured`,
    /// not the generic `.error` bucket the card renders in red.
    func test_refreshNow_unconfiguredProvider_classifiesAsNotConfigured() async {
        let unconfigured = FakeUsageProvider(id: "openrouter", displayName: "OpenRouter")
        unconfigured.isAuthenticatedResult = false
        let registry = PluginRegistry()
        registry.register(unconfigured)
        let scheduler = Scheduler(
            registry: registry,
            storage: FakeStorage(),
            alertEngine: AlertEngine(),
            alertDispatcher: AlertDispatcher(sender: FakeNotificationSender())
        )
        let model = AppModel(registry: registry, scheduler: scheduler)

        await model.refreshNow()

        XCTAssertEqual(model.errorKindByProvider["openrouter"], .notConfigured)
    }

    func test_history_readsWorstSeriesFromStorageWindow() throws {
        let provider = FakeUsageProvider(id: "claude", displayName: "Claude Code")
        let registry = PluginRegistry()
        registry.register(provider)
        let storage = FakeStorage()
        let now = Date()
        let window = { (used: Double) in
            [QuotaWindow(label: "5h", shape: .rollingWindow(used: used, limit: 100, windowStart: now, resetAt: now.addingTimeInterval(3600)))]
        }
        try storage.save(ProviderSnapshot(providerId: "claude", fetchedAt: now.addingTimeInterval(-8 * 24 * 3600), quotas: window(99), usageDetail: nil))
        try storage.save(ProviderSnapshot(providerId: "claude", fetchedAt: now.addingTimeInterval(-3600), quotas: window(20), usageDetail: nil))
        try storage.save(ProviderSnapshot(providerId: "claude", fetchedAt: now, quotas: window(35), usageDetail: nil))
        let scheduler = Scheduler(
            registry: registry,
            storage: storage,
            alertEngine: AlertEngine(),
            alertDispatcher: AlertDispatcher(sender: FakeNotificationSender())
        )
        let model = AppModel(registry: registry, scheduler: scheduler, storage: storage)

        let series = model.history(providerId: "claude", hours: 7 * 24, now: now)

        // O ponto de 8 dias atrás fica fora da janela de 7 dias.
        XCTAssertEqual(series.count, 2)
        XCTAssertEqual(series[0].usedPercent, 20, accuracy: 0.0001)
        XCTAssertEqual(series[1].usedPercent, 35, accuracy: 0.0001)
    }

    private func makeModel(defaults: UserDefaults) -> AppModel {
        let registry = PluginRegistry()
        let scheduler = Scheduler(
            registry: registry,
            storage: FakeStorage(),
            alertEngine: AlertEngine(),
            alertDispatcher: AlertDispatcher(sender: FakeNotificationSender())
        )
        return AppModel(registry: registry, scheduler: scheduler, defaults: defaults)
    }

    private func freshDefaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "AppModelTests.\(name)")!
        defaults.removePersistentDomain(forName: "AppModelTests.\(name)")
        return defaults
    }

    func test_togglePin_appendsAndRemoves_keepingOrder() {
        let model = makeModel(defaults: freshDefaults(#function))
        model.togglePin(providerId: "claude", windowLabel: "5h")
        model.togglePin(providerId: "codex", windowLabel: "semanal")
        model.togglePin(providerId: "claude", windowLabel: "5h")
        XCTAssertEqual(model.menuBarPins, [.init(providerId: "codex", windowLabel: "semanal")])
        XCTAssertTrue(model.isPinned(providerId: "codex", windowLabel: "semanal"))
        XCTAssertFalse(model.isPinned(providerId: "claude", windowLabel: "5h"))
    }

    func test_pins_persist_roundTrip() {
        let defaults = freshDefaults(#function)
        let model = makeModel(defaults: defaults)
        model.togglePin(providerId: "claude", windowLabel: "5h")
        model.togglePin(providerId: "cursor", windowLabel: "percent")

        let reloaded = makeModel(defaults: defaults)
        XCTAssertEqual(reloaded.menuBarPins, [
            .init(providerId: "claude", windowLabel: "5h"),
            .init(providerId: "cursor", windowLabel: "percent")
        ])
    }

    func test_legacySinglePin_migratesToList() {
        let defaults = freshDefaults(#function)
        defaults.set(AppModel.MenuBarPin(providerId: "codex", windowLabel: "semanal").stored, forKey: "menuBarPin")

        let model = makeModel(defaults: defaults)
        XCTAssertEqual(model.menuBarPins, [.init(providerId: "codex", windowLabel: "semanal")])
        XCTAssertNil(defaults.string(forKey: "menuBarPin"), "legacy key must be cleared after migration")
    }

    /// Persistence regression: a relaunch must come up showing the last usage each
    /// provider reported, not "Carregando…" (or an error) with no numbers.
    func test_init_seedsSnapshotsFromPersistedStorage() throws {
        let provider = FakeUsageProvider(id: "claude", displayName: "Claude Code")
        let registry = PluginRegistry()
        registry.register(provider)
        let storage = FakeStorage()
        let persisted = ProviderSnapshot(
            providerId: "claude",
            fetchedAt: Date(timeIntervalSince1970: 1_000_000),
            quotas: [QuotaWindow(label: "5h", shape: .rollingWindow(used: 40, limit: 100, windowStart: Date(), resetAt: Date()))],
            usageDetail: nil
        )
        try storage.save(persisted)
        let scheduler = Scheduler(
            registry: registry,
            storage: storage,
            alertEngine: AlertEngine(),
            alertDispatcher: AlertDispatcher(sender: FakeNotificationSender())
        )

        let model = AppModel(registry: registry, scheduler: scheduler, storage: storage)

        XCTAssertEqual(model.snapshotsByProvider["claude"], persisted)
    }

    /// A failed refresh records the error but must NOT clear the snapshot already on
    /// screen — the popover keeps showing the last good usage alongside the error.
    func test_failedRefresh_keepsPreviousSnapshot() async throws {
        let provider = FakeUsageProvider(id: "claude", displayName: "Claude Code")
        provider.errorToThrow = FakeError.boom
        let registry = PluginRegistry()
        registry.register(provider)
        let storage = FakeStorage()
        let persisted = ProviderSnapshot(
            providerId: "claude",
            fetchedAt: Date(timeIntervalSince1970: 1_000_000),
            quotas: [QuotaWindow(label: "5h", shape: .rollingWindow(used: 40, limit: 100, windowStart: Date(), resetAt: Date()))],
            usageDetail: nil
        )
        try storage.save(persisted)
        let scheduler = Scheduler(
            registry: registry,
            storage: storage,
            alertEngine: AlertEngine(),
            alertDispatcher: AlertDispatcher(sender: FakeNotificationSender())
        )
        let model = AppModel(registry: registry, scheduler: scheduler, storage: storage)

        await model.refreshNow()

        XCTAssertNotNil(model.errorsByProvider["claude"])
        XCTAssertEqual(model.snapshotsByProvider["claude"], persisted)
    }

    func test_menuBarSegment_reflectsWorstSnapshot() async {
        let provider = FakeUsageProvider(id: "claude", displayName: "Claude Code")
        provider.snapshotToReturn = ProviderSnapshot(
            providerId: "claude",
            fetchedAt: Date(),
            quotas: [QuotaWindow(label: "5h", shape: .rollingWindow(used: 88, limit: 100, windowStart: Date(), resetAt: Date()))],
            usageDetail: nil
        )
        let registry = PluginRegistry()
        registry.register(provider)
        let scheduler = Scheduler(
            registry: registry,
            storage: FakeStorage(),
            alertEngine: AlertEngine(),
            alertDispatcher: AlertDispatcher(sender: FakeNotificationSender())
        )
        let model = AppModel(registry: registry, scheduler: scheduler)

        await model.refreshNow()

        // 88% usado → 12% restante, faixa de alerta. A barra carrega UM segmento só.
        XCTAssertEqual(model.menuBarSegment,
                       MenuBarSegment(glyph: "C", providerId: "claude", text: "12", danger: .warn, remaining: 0.12))
        // E o painel do notch, a mesma cota — a barra é um recorte do painel, não outra
        // fonte de verdade.
        XCTAssertEqual(model.notchEntries.map(\.providerId), ["claude"])
        XCTAssertEqual(model.notchEntries.first?.danger, .warn)
    }

    func test_forecastSlotPersistsAndAvailableSlotsOnlyIncludeCurrentEligibleWindows() throws {
        let now = Date()
        let provider = FakeUsageProvider(id: "claude", displayName: "Claude Code")
        let registry = PluginRegistry()
        registry.register(provider)
        let storage = FakeStorage()
        let snapshot = ProviderSnapshot(
            providerId: "claude",
            fetchedAt: now,
            quotas: [
                QuotaWindow(
                    label: "weekly",
                    shape: .periodicCounter(used: 40, limit: 100, resetAt: now.addingTimeInterval(24 * forecastHour)),
                    renewalCadence: .weekly
                ),
                QuotaWindow(
                    label: "5h",
                    shape: .rollingWindow(used: 40, limit: 100, windowStart: now, resetAt: now.addingTimeInterval(forecastHour))
                ),
                QuotaWindow(
                    label: "estimated",
                    shape: .estimated(used: 40, limit: 100, basis: .localTokenCount, resetAt: now.addingTimeInterval(24 * forecastHour)),
                    renewalCadence: .monthly
                )
            ],
            usageDetail: nil
        )
        try storage.save(snapshot)
        let defaults = freshDefaults(#function)
        let model = AppModel(
            registry: registry,
            scheduler: forecastScheduler(registry: registry, storage: storage),
            storage: storage,
            defaults: defaults
        )

        XCTAssertEqual(model.availableForecastSlots, [.window(providerId: "claude", windowLabel: "weekly")])

        let preferred = ForecastSlot.window(providerId: "claude", windowLabel: "weekly")
        model.forecastSlot = preferred
        let reloaded = AppModel(
            registry: registry,
            scheduler: forecastScheduler(registry: registry, storage: storage),
            storage: storage,
            defaults: defaults
        )

        XCTAssertEqual(reloaded.forecastSlot, preferred)
    }

    func test_recomputeForecastsPublishesForecastFromPersisted24HourHistory() async throws {
        let now = Date()
        let provider = FakeUsageProvider(id: "claude", displayName: "Claude Code")
        let registry = PluginRegistry()
        registry.register(provider)
        let storage = FakeStorage()
        for snapshot in renewableForecastSnapshots(now: now) {
            try storage.save(snapshot)
        }
        let model = AppModel(
            registry: registry,
            scheduler: forecastScheduler(registry: registry, storage: storage),
            storage: storage,
            defaults: freshDefaults(#function)
        )
        let id = ForecastWindowID(providerId: "claude", windowLabel: "weekly")

        await model.recomputeForecasts(providerId: "claude", now: now)

        let forecast = try XCTUnwrap(model.forecastsByWindow[id])
        XCTAssertEqual(forecast.state, .slowDown)
        XCTAssertEqual(forecast.samples.count, 6)
        XCTAssertEqual(forecast.currentUsedPercent, 40, accuracy: 0.0001)
        XCTAssertEqual(model.forecasts(providerId: "claude").map(\.id), [id])
        XCTAssertEqual(model.selectedForecast?.id, id)
    }

    func test_recomputeForecastsIncludesCapturedSnapshotOnceWhenHistoryLagsWrite() async throws {
        let now = Date()
        let snapshots = renewableForecastSnapshots(now: now)
        let current = try XCTUnwrap(snapshots.last)
        let provider = FakeUsageProvider(id: "claude", displayName: "Claude Code")
        let registry = PluginRegistry()
        registry.register(provider)
        let storage = ForecastHistoryLagStorage(
            latest: current,
            historicalSnapshots: Array(snapshots.dropLast())
        )
        let model = AppModel(
            registry: registry,
            scheduler: forecastScheduler(registry: registry, storage: storage),
            storage: storage,
            defaults: freshDefaults(#function)
        )
        let id = ForecastWindowID(providerId: "claude", windowLabel: "weekly")

        let result = await waitForForecast(id, in: model)
        let forecast = try XCTUnwrap(result)

        XCTAssertEqual(forecast.state, .slowDown)
        XCTAssertEqual(forecast.samples.map(\.usedPercent), [10, 15, 20, 25, 30, 40])
        XCTAssertEqual(forecast.samples.filter { $0.date == current.fetchedAt }.count, 1)
    }

    func test_initRecomputesForecastsFromPersistedSeedInBackground() async throws {
        let now = Date()
        let provider = FakeUsageProvider(id: "claude", displayName: "Claude Code")
        let registry = PluginRegistry()
        registry.register(provider)
        let storage = FakeStorage()
        for snapshot in renewableForecastSnapshots(now: now) {
            try storage.save(snapshot)
        }
        let model = AppModel(
            registry: registry,
            scheduler: forecastScheduler(registry: registry, storage: storage),
            storage: storage,
            defaults: freshDefaults(#function)
        )
        let id = ForecastWindowID(providerId: "claude", windowLabel: "weekly")

        let forecast = await waitForForecast(id, in: model)

        XCTAssertEqual(forecast?.state, .slowDown)
    }

    func test_successfulFetchRecomputesForecastsFromPersistedHistory() async throws {
        let now = Date()
        let snapshots = renewableForecastSnapshots(now: now)
        let provider = FakeUsageProvider(id: "claude", displayName: "Claude Code")
        provider.snapshotToReturn = snapshots.last
        let registry = PluginRegistry()
        registry.register(provider)
        let storage = FakeStorage()
        for snapshot in snapshots.dropLast() {
            try storage.save(snapshot)
        }
        let model = AppModel(
            registry: registry,
            scheduler: forecastScheduler(registry: registry, storage: storage),
            storage: storage,
            defaults: freshDefaults(#function)
        )
        let id = ForecastWindowID(providerId: "claude", windowLabel: "weekly")

        await model.refreshNow()
        let forecast = await waitForForecast(id, in: model) {
            $0.currentUsedPercent == 40 && $0.samples.count == 6
        }

        XCTAssertEqual(forecast?.state, .slowDown)
    }

    func test_recomputeForecastsStorageFailurePreservesPublishedForecastAndProviderState() async throws {
        let now = Date()
        let provider = FakeUsageProvider(id: "claude", displayName: "Claude Code")
        let registry = PluginRegistry()
        registry.register(provider)
        let storage = ForecastReadFailingStorage()
        for snapshot in renewableForecastSnapshots(now: now) {
            try storage.save(snapshot)
        }
        let model = AppModel(
            registry: registry,
            scheduler: forecastScheduler(registry: registry, storage: storage),
            storage: storage,
            defaults: freshDefaults(#function)
        )

        let id = ForecastWindowID(providerId: "claude", windowLabel: "weekly")
        _ = await waitForForecast(id, in: model)
        let published = model.forecastsByWindow
        XCTAssertFalse(published.isEmpty)

        storage.shouldFailSnapshotsRead = true
        await model.recomputeForecasts(providerId: "claude", now: now)

        XCTAssertEqual(model.forecastsByWindow, published)
        XCTAssertNil(model.errorsByProvider["claude"])
        XCTAssertNil(model.errorKindByProvider["claude"])
    }

    // MARK: - Provider order

    private func isolatedProviderOrderDefaults() -> UserDefaults {
        let suite = "oktally.tests.provider-order.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func providerOrderScheduler(registry: PluginRegistry) -> Scheduler {
        Scheduler(
            registry: registry,
            storage: FakeStorage(),
            alertEngine: AlertEngine(),
            alertDispatcher: AlertDispatcher(sender: FakeNotificationSender())
        )
    }

    func test_orderedProviders_withoutSavedOrder_followsPreferencesDefaultNotRegistry() {
        let registry = PluginRegistry()
        for id in ["openrouter", "claude", "mimo"] {
            registry.register(FakeUsageProvider(id: id, displayName: id))
        }
        let defaults = isolatedProviderOrderDefaults()
        let model = AppModel(
            registry: registry,
            scheduler: providerOrderScheduler(registry: registry),
            defaults: defaults
        )
        XCTAssertEqual(model.orderedProviders.map(\.id), ["claude", "openrouter", "mimo"])
    }

    func test_moveProvider_persistsFullResolvedOrder() {
        let registry = PluginRegistry()
        for id in ["claude", "codex", "mimo"] {
            registry.register(FakeUsageProvider(id: id, displayName: id))
        }
        let defaults = isolatedProviderOrderDefaults()
        let scheduler = providerOrderScheduler(registry: registry)
        let model = AppModel(registry: registry, scheduler: scheduler, defaults: defaults)
        XCTAssertTrue(model.moveProvider(dragging: "mimo", onto: "claude"))
        XCTAssertEqual(model.orderedProviders.map(\.id), ["mimo", "claude", "codex"])
        XCTAssertEqual(model.providerOrder, ["mimo", "claude", "codex"])

        let reloaded = AppModel(registry: registry, scheduler: scheduler, defaults: defaults)
        XCTAssertEqual(reloaded.orderedProviders.map(\.id), ["mimo", "claude", "codex"])
    }

    func test_moveProvider_droppingOnSelf_returnsFalseAndDoesNotWrite() {
        let registry = PluginRegistry()
        registry.register(FakeUsageProvider(id: "claude", displayName: "Claude"))
        registry.register(FakeUsageProvider(id: "mimo", displayName: "MiMo"))
        let defaults = isolatedProviderOrderDefaults()
        let model = AppModel(
            registry: registry,
            scheduler: providerOrderScheduler(registry: registry),
            defaults: defaults
        )
        XCTAssertFalse(model.moveProvider(dragging: "claude", onto: "claude"))
        XCTAssertEqual(model.providerOrder, [])
    }
}
