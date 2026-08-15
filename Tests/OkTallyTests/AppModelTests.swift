// Tests/OkTallyTests/AppModelTests.swift
import XCTest
@testable import OkTally

@MainActor
final class AppModelTests: XCTestCase {
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
                       MenuBarSegment(glyph: "C", providerId: "claude", text: "12", danger: .warn))
        // E o painel do notch, a mesma cota — a barra é um recorte do painel, não outra
        // fonte de verdade.
        XCTAssertEqual(model.notchEntries.map(\.providerId), ["claude"])
        XCTAssertEqual(model.notchEntries.first?.danger, .warn)
    }
}
