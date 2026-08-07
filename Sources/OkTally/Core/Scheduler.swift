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

enum SchedulerError: LocalizedError {
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Não configurado — adicione suas credenciais nas Preferências."
        }
    }
}

final class Scheduler {
    private let registry: PluginRegistry
    private let storage: StorageManaging
    private let alertEngine: AlertEngine
    private let alertDispatcher: AlertDispatcher
    private let thresholdsProvider: (String) -> [String: [AlertThreshold]]

    var onResult: ((SchedulerFetchResult) -> Void)?

    private let lastErrorLock = NSLock()
    private var _lastError: [String: Error] = [:]

    var lastError: [String: Error] {
        lastErrorLock.lock()
        defer { lastErrorLock.unlock() }
        return _lastError
    }

    private func setLastError(_ error: Error?, for providerId: String) {
        lastErrorLock.lock()
        defer { lastErrorLock.unlock() }
        _lastError[providerId] = error
    }

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
        guard await provider.isAuthenticated() else {
            let error = SchedulerError.notConfigured
            setLastError(error, for: provider.id)
            let result = SchedulerFetchResult(providerId: provider.id, outcome: .failure(error))
            onResult?(result)
            return result
        }
        do {
            let previous = try? storage.latestSnapshot(providerId: provider.id)
            let snapshot = try await provider.fetchSnapshot()
            setLastError(nil, for: provider.id)
            let result = SchedulerFetchResult(providerId: provider.id, outcome: .success(snapshot))
            onResult?(result)
            do {
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
            } catch {
                // Storage/alert-evaluation failure must not revert the successful fetch already reported to the UI.
            }
            return result
        } catch {
            setLastError(error, for: provider.id)
            let result = SchedulerFetchResult(providerId: provider.id, outcome: .failure(error))
            onResult?(result)
            return result
        }
    }
}
