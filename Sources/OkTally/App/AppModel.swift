// Sources/OkTally/App/AppModel.swift
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshotsByProvider: [String: ProviderSnapshot] = [:]
    @Published private(set) var errorsByProvider: [String: String] = [:]

    private let registry: PluginRegistry
    private let scheduler: Scheduler

    init(registry: PluginRegistry, scheduler: Scheduler) {
        self.registry = registry
        self.scheduler = scheduler
        scheduler.onResult = { [weak self] result in
            Task { @MainActor in self?.apply(result) }
        }
    }

    func start() {
        scheduler.startPeriodicLoop()
    }

    func refreshNow() async {
        _ = await scheduler.fetchAll()
    }

    var menuBarState: MenuBarState {
        MenuBarStateCalculator.worstState(
            snapshots: Array(snapshotsByProvider.values),
            hasAnyError: !errorsByProvider.isEmpty
        )
    }

    var orderedProviders: [UsageProvider] { registry.providers }

    private func apply(_ result: SchedulerFetchResult) {
        switch result.outcome {
        case .success(let snapshot):
            snapshotsByProvider[result.providerId] = snapshot
            errorsByProvider[result.providerId] = nil
        case .failure(let error):
            errorsByProvider[result.providerId] = error.localizedDescription
        }
    }
}
