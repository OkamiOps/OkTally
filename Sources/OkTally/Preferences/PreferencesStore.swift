import Foundation

protocol KeyValueStore {
    func string(forKey key: String) -> String?
    func set(_ value: String?, forKey key: String)
    func double(forKey key: String) -> Double
    func set(_ value: Double, forKey key: String)
}

extension UserDefaults: KeyValueStore {
    func set(_ value: String?, forKey key: String) {
        set(value as Any?, forKey: key)
    }
}

final class PreferencesStore {
    private let store: KeyValueStore

    private enum Keys {
        static let openRouterAPIKey = "openRouterAPIKey"
        static func refreshInterval(_ providerId: String) -> String { "refreshInterval.\(providerId)" }
    }

    init(store: KeyValueStore = UserDefaults.standard) {
        self.store = store
    }

    var openRouterAPIKey: String? {
        get { store.string(forKey: Keys.openRouterAPIKey) }
        set { store.set(newValue, forKey: Keys.openRouterAPIKey) }
    }

    func refreshInterval(for providerId: String, default defaultValue: TimeInterval) -> TimeInterval {
        let stored = store.double(forKey: Keys.refreshInterval(providerId))
        return stored > 0 ? stored : defaultValue
    }

    func setRefreshInterval(_ interval: TimeInterval, for providerId: String) {
        store.set(interval, forKey: Keys.refreshInterval(providerId))
    }
}
