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

    func prune(olderThan cutoff: Date) throws {
        for (key, value) in byProvider {
            byProvider[key] = value.filter { $0.fetchedAt >= cutoff }
        }
    }
}

enum FakeError: Error { case boom }

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
