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

    func test_menuBarState_reflectsWorstSnapshot() async {
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

        XCTAssertEqual(model.menuBarState.percent, 88)
    }
}
