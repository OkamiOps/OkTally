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

    /// The quota windows shown in the menu bar, in the order they were pinned. Empty =
    /// automatic (worst window across all providers). Persisted across relaunches.
    @Published var menuBarPins: [MenuBarPin] {
        didSet {
            let joined = menuBarPins.map(\.stored).joined(separator: "\u{2}")
            if joined.isEmpty {
                defaults.removeObject(forKey: Self.menuBarPinsKey)
            } else {
                defaults.set(joined, forKey: Self.menuBarPinsKey)
            }
        }
    }
    private static let menuBarPinsKey = "menuBarPins"
    private static let legacyMenuBarPinKey = "menuBarPin"
    private let defaults: UserDefaults

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

    init(registry: PluginRegistry, scheduler: Scheduler, defaults: UserDefaults = .standard) {
        self.registry = registry
        self.scheduler = scheduler
        self.defaults = defaults
        if let joined = defaults.string(forKey: Self.menuBarPinsKey) {
            self.menuBarPins = joined.split(separator: "\u{2}").compactMap { MenuBarPin(stored: String($0)) }
        } else if let legacy = MenuBarPin(stored: defaults.string(forKey: Self.legacyMenuBarPinKey)) {
            self.menuBarPins = [legacy]
            defaults.removeObject(forKey: Self.legacyMenuBarPinKey)
        } else {
            self.menuBarPins = []
        }
        scheduler.onResult = { [weak self] result in
            Task { @MainActor in self?.apply(result) }
        }
    }

    func togglePin(providerId: String, windowLabel: String) {
        let pin = MenuBarPin(providerId: providerId, windowLabel: windowLabel)
        if let index = menuBarPins.firstIndex(of: pin) {
            menuBarPins.remove(at: index)
        } else {
            menuBarPins.append(pin)
        }
    }

    func isPinned(providerId: String, windowLabel: String) -> Bool {
        menuBarPins.contains(MenuBarPin(providerId: providerId, windowLabel: windowLabel))
    }

    func start() {
        scheduler.startPeriodicLoop()
    }

    func refreshNow() async {
        _ = await scheduler.fetchAll()
    }

    var menuBarState: MenuBarState {
        // Replaced by `menuBarSegments` in the label-model task; kept minimally alive so
        // intermediate commits compile. Uses only the automatic (worst-window) path.
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
            errorKindByProvider[result.providerId] = nil
        case .failure(let error):
            errorsByProvider[result.providerId] = error.localizedDescription
            errorKindByProvider[result.providerId] = ProviderErrorPresentation.classify(error)
        }
    }
}
