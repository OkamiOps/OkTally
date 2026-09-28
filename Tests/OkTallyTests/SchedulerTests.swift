// Tests/OkTallyTests/SchedulerTests.swift
import XCTest
@testable import OkTally

final class FakeUsageProvider: UsageProvider {
    let id: String
    let displayName: String
    let authMethod: AuthMethod = .apiKey
    let refreshInterval: TimeInterval = 60
    var snapshotToReturn: ProviderSnapshot?
    var errorToThrow: Error?
    var isAuthenticatedResult = true

    init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }

    func isAuthenticated() async -> Bool { isAuthenticatedResult }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        if let errorToThrow { throw errorToThrow }
        return snapshotToReturn!
    }
}

final class FakeStorage: StorageManaging {
    private var byProvider: [String: [ProviderSnapshot]] = [:]
    private(set) var saveCount = 0

    func save(_ snapshot: ProviderSnapshot) throws {
        saveCount += 1
        byProvider[snapshot.providerId, default: []].append(snapshot)
    }

    func latestSnapshot(providerId: String) throws -> ProviderSnapshot? {
        byProvider[providerId]?.last
    }

    func snapshots(providerId: String, since: Date) throws -> [ProviderSnapshot] {
        (byProvider[providerId] ?? []).filter { $0.fetchedAt >= since }
    }

    func deleteSnapshots(providerId: String) throws {
        byProvider[providerId] = nil
    }

    func prune(olderThan cutoff: Date) throws {
        for (key, value) in byProvider {
            byProvider[key] = value.filter { $0.fetchedAt >= cutoff }
        }
    }
}

enum FakeError: Error { case boom }

/// Provedor que some do registry no meio do próprio fetch — a conta removida enquanto a
/// leitura estava em voo.
final class SelfRemovingProvider: UsageProvider {
    let id: String
    let displayName = "Gone"
    let authMethod: AuthMethod = .apiKey
    let refreshInterval: TimeInterval = 60
    weak var registry: PluginRegistry?

    init(id: String) { self.id = id }

    func isAuthenticated() async -> Bool { true }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        registry?.remove(ids: [id])
        return ProviderSnapshot(providerId: id, fetchedAt: Date(), quotas: [
            QuotaWindow(label: "5h", shape: .rollingWindow(used: 99, limit: 100, windowStart: Date(), resetAt: Date()))
        ], usageDetail: nil)
    }
}

final class SchedulerTests: XCTestCase {
    private func snapshot(providerId: String, percent: Double) -> ProviderSnapshot {
        ProviderSnapshot(
            providerId: providerId,
            fetchedAt: Date(),
            quotas: [QuotaWindow(label: "5h", shape: .rollingWindow(used: percent, limit: 100, windowStart: Date(), resetAt: Date()))],
            usageDetail: nil
        )
    }

    func test_fetchAll_savesSnapshotsAndDispatchesAlerts() async {
        let provider = FakeUsageProvider(id: "claude", displayName: "Claude Code")
        provider.snapshotToReturn = snapshot(providerId: "claude", percent: 75)
        let registry = PluginRegistry()
        registry.register(provider)
        let storage = FakeStorage()
        let sender = FakeNotificationSender()
        let scheduler = Scheduler(
            registry: registry,
            storage: storage,
            alertEngine: AlertEngine(),
            alertDispatcher: AlertDispatcher(sender: sender)
        )

        let results = await scheduler.fetchAll()

        XCTAssertEqual(storage.saveCount, 1)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(sender.sentMessages.count, 1)
    }

    func test_fetchAll_oneProviderFailing_doesNotAffectOthers() async {
        let good = FakeUsageProvider(id: "openrouter", displayName: "OpenRouter")
        good.snapshotToReturn = snapshot(providerId: "openrouter", percent: 10)
        let bad = FakeUsageProvider(id: "claude", displayName: "Claude Code")
        bad.errorToThrow = FakeError.boom
        let registry = PluginRegistry()
        registry.register(bad)
        registry.register(good)
        let storage = FakeStorage()
        let scheduler = Scheduler(
            registry: registry,
            storage: storage,
            alertEngine: AlertEngine(),
            alertDispatcher: AlertDispatcher(sender: FakeNotificationSender())
        )

        let results = await scheduler.fetchAll()

        XCTAssertEqual(storage.saveCount, 1)
        XCTAssertNotNil(scheduler.lastError["claude"])
        XCTAssertNil(scheduler.lastError["openrouter"])
        XCTAssertEqual(results.count, 2)
    }

    func test_fetchAll_invokesOnResultCallback() async {
        let provider = FakeUsageProvider(id: "claude", displayName: "Claude Code")
        provider.snapshotToReturn = snapshot(providerId: "claude", percent: 5)
        let registry = PluginRegistry()
        registry.register(provider)
        let scheduler = Scheduler(
            registry: registry,
            storage: FakeStorage(),
            alertEngine: AlertEngine(),
            alertDispatcher: AlertDispatcher(sender: FakeNotificationSender())
        )
        var received: [SchedulerFetchResult] = []
        scheduler.onResult = { received.append($0) }

        _ = await scheduler.fetchAll()

        XCTAssertEqual(received.count, 1)
    }

    /// Revisão: o `save` depois do fetch não pode ressuscitar o histórico que o
    /// `removeAccount` acabou de apagar, nem disparar alerta de conta que não existe mais.
    func test_fetch_providerRemovedMidFlight_neitherSavesNorAlerts() async {
        let registry = PluginRegistry()
        let gone = SelfRemovingProvider(id: "claude#abc123")
        gone.registry = registry
        registry.register(gone)
        let storage = FakeStorage()
        let sender = FakeNotificationSender()
        let scheduler = Scheduler(registry: registry, storage: storage, alertEngine: AlertEngine(),
                                  alertDispatcher: AlertDispatcher(sender: sender))

        _ = await scheduler.fetchAll()

        XCTAssertEqual(storage.saveCount, 0)
        XCTAssertTrue(sender.sentMessages.isEmpty)
    }

    func test_stopLoop_cancelsOnlyThatInstance() async throws {
        let a = FakeUsageProvider(id: "a", displayName: "A"); a.snapshotToReturn = snapshot(providerId: "a", percent: 1)
        let b = FakeUsageProvider(id: "b", displayName: "B"); b.snapshotToReturn = snapshot(providerId: "b", percent: 1)
        let registry = PluginRegistry(); registry.register(a); registry.register(b)
        let scheduler = Scheduler(registry: registry, storage: FakeStorage(), alertEngine: AlertEngine(),
                                  alertDispatcher: AlertDispatcher(sender: FakeNotificationSender()))
        scheduler.startLoop(for: a, initialDelay: 0)
        scheduler.startLoop(for: b, initialDelay: 0)
        XCTAssertTrue(scheduler.isLooping(id: "a"))
        scheduler.stopLoop(id: "a")
        XCTAssertFalse(scheduler.isLooping(id: "a"))
        XCTAssertTrue(scheduler.isLooping(id: "b"))
        scheduler.stopLoop(id: "b")
    }

    func test_stopLoop_clearsLastErrorOfThatInstance() async {
        let bad = FakeUsageProvider(id: "bad", displayName: "Bad"); bad.errorToThrow = FakeError.boom
        let registry = PluginRegistry(); registry.register(bad)
        let scheduler = Scheduler(registry: registry, storage: FakeStorage(), alertEngine: AlertEngine(),
                                  alertDispatcher: AlertDispatcher(sender: FakeNotificationSender()))
        _ = await scheduler.fetchAll()
        XCTAssertNotNil(scheduler.lastError["bad"])
        scheduler.stopLoop(id: "bad")
        XCTAssertNil(scheduler.lastError["bad"])
    }

    func test_fetchAll_twoSequentialCallsAboveThreshold_doesNotRefireOnSecondCall() async {
        let provider = FakeUsageProvider(id: "claude", displayName: "Claude Code")
        provider.snapshotToReturn = snapshot(providerId: "claude", percent: 75)
        let registry = PluginRegistry()
        registry.register(provider)
        let storage = FakeStorage()
        let sender = FakeNotificationSender()
        let scheduler = Scheduler(
            registry: registry,
            storage: storage,
            alertEngine: AlertEngine(),
            alertDispatcher: AlertDispatcher(sender: sender)
        )

        _ = await scheduler.fetchAll()
        _ = await scheduler.fetchAll()

        XCTAssertEqual(sender.sentMessages.count, 1)
        XCTAssertEqual(storage.saveCount, 2)
    }
}
