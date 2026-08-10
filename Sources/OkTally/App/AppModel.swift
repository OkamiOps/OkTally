// Sources/OkTally/App/AppModel.swift
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshotsByProvider: [String: ProviderSnapshot] = [:]
    @Published private(set) var errorsByProvider: [String: String] = [:]
    /// Kept alongside `errorsByProvider`'s `String` messages (unchanged, still what the
    /// menu bar/cards display as text) so callers can also classify the failure — e.g.
    /// `ProviderCardView` uses this to avoid painting "not configured yet" the same red
    /// as a real fetch failure.
    @Published private(set) var errorKindByProvider: [String: ProviderErrorPresentation] = [:]

    /// The specific quota window driving the always-visible menu bar percentage. `nil` =
    /// automatic (worst window across all providers). Persisted across relaunches.
    @Published var menuBarPin: MenuBarPin? {
        didSet { UserDefaults.standard.set(menuBarPin?.stored, forKey: Self.menuBarKey) }
    }
    private static let menuBarKey = "menuBarPin"

    struct MenuBarPin: Equatable {
        let providerId: String
        let windowLabel: String
        var stored: String { "\(providerId)\u{1}\(windowLabel)" }
        init(providerId: String, windowLabel: String) {
            self.providerId = providerId
            self.windowLabel = windowLabel
        }
        init?(stored: String?) {
            guard let parts = stored?.split(separator: "\u{1}", maxSplits: 1), parts.count == 2 else { return nil }
            self.providerId = String(parts[0])
            self.windowLabel = String(parts[1])
        }
    }

    private let registry: PluginRegistry
    private let scheduler: Scheduler

    init(registry: PluginRegistry, scheduler: Scheduler) {
        self.registry = registry
        self.scheduler = scheduler
        self.menuBarPin = MenuBarPin(stored: UserDefaults.standard.string(forKey: Self.menuBarKey))
        scheduler.onResult = { [weak self] result in
            Task { @MainActor in self?.apply(result) }
        }
    }

    func togglePin(providerId: String, windowLabel: String) {
        let candidate = MenuBarPin(providerId: providerId, windowLabel: windowLabel)
        menuBarPin = (menuBarPin == candidate) ? nil : candidate
    }

    func start() {
        scheduler.startPeriodicLoop()
    }

    func refreshNow() async {
        _ = await scheduler.fetchAll()
    }

    var menuBarState: MenuBarState {
        // A pinned window drives the menu bar when chosen and present; otherwise the worst
        // window across all providers.
        if let pin = menuBarPin,
           let snapshot = snapshotsByProvider[pin.providerId],
           let window = snapshot.quotas.first(where: { $0.label == pin.windowLabel }) {
            let single = ProviderSnapshot(providerId: pin.providerId, fetchedAt: snapshot.fetchedAt, quotas: [window], usageDetail: nil)
            return MenuBarStateCalculator.worstState(snapshots: [single], hasAnyError: false)
        }
        return MenuBarStateCalculator.worstState(
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
            errorKindByProvider[result.providerId] = nil
        case .failure(let error):
            errorsByProvider[result.providerId] = error.localizedDescription
            errorKindByProvider[result.providerId] = ProviderErrorPresentation.classify(error)
        }
    }
}
