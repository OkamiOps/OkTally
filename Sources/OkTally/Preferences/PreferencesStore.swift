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
        static let mimoAPIKey = "mimoAPIKey"
        static let mimoMonthlyAllowanceCredits = "mimoMonthlyAllowanceCredits"
        static let mimoUsedCredits = "mimoUsedCredits"
        static func refreshInterval(_ providerId: String) -> String { "refreshInterval.\(providerId)" }
    }

    init(store: KeyValueStore = UserDefaults.standard) {
        self.store = store
    }

    var openRouterAPIKey: String? {
        get { store.string(forKey: Keys.openRouterAPIKey) }
        set { store.set(newValue, forKey: Keys.openRouterAPIKey) }
    }

    var mimoAPIKey: String? {
        get { store.string(forKey: Keys.mimoAPIKey) }
        set { store.set(newValue, forKey: Keys.mimoAPIKey) }
    }

    /// The user-entered monthly Token Plan allowance (in Credits). `nil` means the
    /// owner hasn't configured it yet — MiMo exposes no API-key-authenticated quota
    /// endpoint (confirmed by source; see docs/superpowers/research/plan2-mimo.md),
    /// so this value only ever comes from manual entry in Preferences.
    var mimoMonthlyAllowanceCredits: Double? {
        get { store.string(forKey: Keys.mimoMonthlyAllowanceCredits).flatMap(Double.init) }
        set { store.set(newValue.map { String($0) }, forKey: Keys.mimoMonthlyAllowanceCredits) }
    }

    /// Credits used so far this month, manually updated by the owner. Defaults to 0.
    var mimoUsedCredits: Double {
        get { store.double(forKey: Keys.mimoUsedCredits) }
        set { store.set(newValue, forKey: Keys.mimoUsedCredits) }
    }

    func refreshInterval(for providerId: String, default defaultValue: TimeInterval) -> TimeInterval {
        let stored = store.double(forKey: Keys.refreshInterval(providerId))
        return stored > 0 ? stored : defaultValue
    }

    func setRefreshInterval(_ interval: TimeInterval, for providerId: String) {
        store.set(interval, forKey: Keys.refreshInterval(providerId))
    }
}
