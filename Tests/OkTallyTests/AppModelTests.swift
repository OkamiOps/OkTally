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
