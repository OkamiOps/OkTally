// Sources/OkTally/Core/Scheduler.swift
import Foundation

struct SchedulerFetchResult {
    enum Outcome {
        case success(ProviderSnapshot)
        case failure(Error)
    }
    let providerId: String
    let outcome: Outcome
}

final class Scheduler {
    private let registry: PluginRegistry
    private let storage: StorageManaging
    private let alertEngine: AlertEngine
    private let alertDispatcher: AlertDispatcher
    private let thresholdsProvider: (String) -> [String: [AlertThreshold]]

    var onResult: ((SchedulerFetchResult) -> Void)?
    private(set) var lastError: [String: Error] = [:]

    init(
        registry: PluginRegistry,
        storage: StorageManaging,
        alertEngine: AlertEngine,
        alertDispatcher: AlertDispatcher,
        thresholdsProvider: @escaping (String) -> [String: [AlertThreshold]] = { _ in [:] }
    ) {
        self.registry = registry
        self.storage = storage
        self.alertEngine = alertEngine
        self.alertDispatcher = alertDispatcher
        self.thresholdsProvider = thresholdsProvider
    }

    @discardableResult
    func fetchAll() async -> [SchedulerFetchResult] {
        var results: [SchedulerFetchResult] = []
        for provider in registry.providers {
            results.append(await fetchOne(provider))
        }
        return results
    }

    func startPeriodicLoop() {
        for provider in registry.providers {
            Task {
                while !Task.isCancelled {
                    _ = await fetchOne(provider)
                    try? await Task.sleep(nanoseconds: UInt64(provider.refreshInterval * 1_000_000_000))
                }
            }
        }
    }

    private func fetchOne(_ provider: UsageProvider) async -> SchedulerFetchResult {
        do {
            let previous = try? storage.latestSnapshot(providerId: provider.id)
            let snapshot = try await provider.fetchSnapshot()
            try storage.save(snapshot)
            let thresholds = thresholdsProvider(provider.id)
            let events = alertEngine.evaluate(
                providerId: provider.id,
                providerDisplayName: provider.displayName,
                previous: previous,
                current: snapshot,
                thresholds: thresholds
            )
            await alertDispatcher.dispatch(events)
            lastError[provider.id] = nil
            let result = SchedulerFetchResult(providerId: provider.id, outcome: .success(snapshot))
            onResult?(result)
            return result
        } catch {
            lastError[provider.id] = error
            let result = SchedulerFetchResult(providerId: provider.id, outcome: .failure(error))
            onResult?(result)
            return result
        }
    }
}
