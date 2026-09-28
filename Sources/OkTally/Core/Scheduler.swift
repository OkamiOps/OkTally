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
            return L("Não configurado — adicione suas credenciais nas Preferências.")
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

    private let loopsLock = NSLock()
    private var loops: [String: Task<Void, Never>] = [:]

    /// Um loop por conta, cada um com o próprio intervalo. Irmãos do mesmo tipo entram
    /// defasados (`RefreshStagger`); sem contas extras todos os atrasos são zero e o
    /// comportamento é o de sempre.
    func startPeriodicLoop() {
        let providers = registry.providers
        let offsets = RefreshStagger.offsets(for: providers.map { ($0.id, $0.refreshInterval) })
        for provider in providers {
            startLoop(for: provider, initialDelay: offsets[provider.id] ?? 0)
        }
    }

    /// Liga (ou religa) o loop de UMA conta — usado também quando o dono adiciona uma
    /// conta com o app aberto.
    func startLoop(for provider: UsageProvider, initialDelay: TimeInterval) {
        let task = Task { [weak self] in
            if initialDelay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(initialDelay * 1_000_000_000))
            }
            while !Task.isCancelled {
                guard let self else { return }
                _ = await self.fetchOne(provider)
                try? await Task.sleep(nanoseconds: UInt64(provider.refreshInterval * 1_000_000_000))
            }
        }
        loopsLock.lock()
        let previous = loops.updateValue(task, forKey: provider.id)
        loopsLock.unlock()
        previous?.cancel()
    }

    /// Para o loop de uma conta removida e esquece o último erro dela, para que o card
    /// de uma conta que não existe mais não fique acusando falha.
    func stopLoop(id: String) {
        loopsLock.lock()
        let task = loops.removeValue(forKey: id)
        loopsLock.unlock()
        task?.cancel()
        setLastError(nil, for: id)
    }

    func isLooping(id: String) -> Bool {
        loopsLock.lock()
        defer { loopsLock.unlock() }
        return loops[id] != nil
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
