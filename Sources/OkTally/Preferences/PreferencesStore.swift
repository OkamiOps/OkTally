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
    private let secretStore: SecretStoring

    private enum Keys {
        // Legacy UserDefaults locations for the 4 API keys below. No longer written to —
        // kept only as migration sources (see `migratedSecret`) so an owner upgrading
        // from an older build doesn't lose a key they already entered.
        static let openRouterAPIKey = "openRouterAPIKey"
        static let mimoAPIKey = "mimoAPIKey"
        static let minimaxAPIKey = "minimaxAPIKey"
        static let openCodeAPIKey = "openCodeAPIKey"

        static let mimoMonthlyAllowanceCredits = "mimoMonthlyAllowanceCredits"
        static let mimoUsedCredits = "mimoUsedCredits"
        static let minimaxRegionRaw = "minimaxRegionRaw"
        static let alertsEnabled = "alertsEnabled"
        static let alertPercentThresholds = "alertPercentThresholds"
        static let alertLowBalanceThreshold = "alertLowBalanceThreshold"
        static func refreshInterval(_ providerId: String) -> String { "refreshInterval.\(providerId)" }
    }

    /// Keychain namespace per provider (`com.oktally.app.apikey.<id>` via
    /// `KeychainSecretStore`) — distinct from `UsageProvider.id` only coincidentally
    /// matching it; kept as its own table in case they ever diverge.
    private enum SecretProviderId {
        static let openRouter = "openrouter"
        static let mimo = "mimo"
        static let minimax = "minimax"
        static let openCode = "opencode"
    }

    init(store: KeyValueStore = UserDefaults.standard, secretStore: SecretStoring = KeychainSecretStore()) {
        self.store = store
        self.secretStore = secretStore
    }

    /// API keys are secrets and belong in the Keychain, not `UserDefaults` (see
    /// `SecretStoring`'s doc comment). This reads from the Keychain first; if nothing is
    /// there yet but an older build left a plaintext value in `UserDefaults`, it's moved
    /// into the Keychain and wiped from `UserDefaults` on the spot — a silent one-time
    /// migration, invisible to the caller.
    private func migratedSecret(providerId: String, legacyKey: String) -> String? {
        if let current = secretStore.load(providerId: providerId) { return current }
        guard let legacy = store.string(forKey: legacyKey), !legacy.isEmpty else { return nil }
        // Only scrub the legacy UserDefaults copy once the Keychain write actually
        // succeeds. If `save` throws (Keychain locked, denied ACL, unsigned-build
        // access-group mismatch, etc.), keep `legacy` in UserDefaults so the value
        // isn't lost — the caller still gets it back this call, and migration will be
        // retried on the next read.
        do {
            try secretStore.save(legacy, providerId: providerId)
            store.set(nil, forKey: legacyKey)
        } catch {
            return legacy
        }
        return legacy
    }

    private func setSecret(_ value: String?, providerId: String, legacyKey: String) throws {
        if let value, !value.isEmpty {
            // Write to the Keychain first; only scrub the legacy plaintext location once
            // the write has actually succeeded, so a failed save never destroys the only
            // remaining copy of the key.
            try secretStore.save(value, providerId: providerId)
        } else {
            try secretStore.delete(providerId: providerId)
        }
        store.set(nil, forKey: legacyKey)
    }

    var openRouterAPIKey: String? {
        migratedSecret(providerId: SecretProviderId.openRouter, legacyKey: Keys.openRouterAPIKey)
    }

    /// Throwing setter (rather than a computed-property `set`) so a failed Keychain
    /// write can be surfaced to the caller instead of being silently swallowed — see
    /// `setSecret`.
    func setOpenRouterAPIKey(_ value: String?) throws {
        try setSecret(value, providerId: SecretProviderId.openRouter, legacyKey: Keys.openRouterAPIKey)
    }

    var mimoAPIKey: String? {
        migratedSecret(providerId: SecretProviderId.mimo, legacyKey: Keys.mimoAPIKey)
    }

    func setMimoAPIKey(_ value: String?) throws {
        try setSecret(value, providerId: SecretProviderId.mimo, legacyKey: Keys.mimoAPIKey)
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

    var minimaxAPIKey: String? {
        migratedSecret(providerId: SecretProviderId.minimax, legacyKey: Keys.minimaxAPIKey)
    }

    func setMinimaxAPIKey(_ value: String?) throws {
        try setSecret(value, providerId: SecretProviderId.minimax, legacyKey: Keys.minimaxAPIKey)
    }

    /// Stores `"global"`/`"china"`; defaults to `"global"` when unset. Not a secret, stays
    /// in UserDefaults.
    var minimaxRegionRaw: String? {
        get { store.string(forKey: Keys.minimaxRegionRaw) ?? "global" }
        set { store.set(newValue, forKey: Keys.minimaxRegionRaw) }
    }

    var openCodeAPIKey: String? {
        migratedSecret(providerId: SecretProviderId.openCode, legacyKey: Keys.openCodeAPIKey)
    }

    func setOpenCodeAPIKey(_ value: String?) throws {
        try setSecret(value, providerId: SecretProviderId.openCode, legacyKey: Keys.openCodeAPIKey)
    }

    // MARK: - Alert preferences

    /// Master switch for quota notifications. Defaults to enabled.
    var alertsEnabled: Bool {
        get { store.string(forKey: Keys.alertsEnabled) != "false" }
        set { store.set(newValue ? "true" : "false", forKey: Keys.alertsEnabled) }
    }

    /// Percentage crossings that trigger a notification, as fractions (0.7 = 70% usado).
    /// Persisted as a comma-joined string; unset means the historical defaults. An empty
    /// string is a deliberate "no percentage alerts" choice and round-trips as [].
    var alertPercentThresholds: [Double] {
        get {
            guard let raw = store.string(forKey: Keys.alertPercentThresholds) else {
                return [0.7, 0.9, 1.0]
            }
            return raw.split(separator: ",").compactMap { Double($0) }
        }
        set { store.set(newValue.map { String($0) }.joined(separator: ","), forKey: Keys.alertPercentThresholds) }
    }

    /// Balance (em USD) abaixo do qual providers de saldo disparam alerta.
    var alertLowBalanceThreshold: Double {
        get {
            let stored = store.double(forKey: Keys.alertLowBalanceThreshold)
            return stored > 0 ? stored : 5.0
        }
        set { store.set(newValue, forKey: Keys.alertLowBalanceThreshold) }
    }

    func refreshInterval(for providerId: String, default defaultValue: TimeInterval) -> TimeInterval {
        let stored = store.double(forKey: Keys.refreshInterval(providerId))
        return stored > 0 ? stored : defaultValue
    }

    func setRefreshInterval(_ interval: TimeInterval, for providerId: String) {
        store.set(interval, forKey: Keys.refreshInterval(providerId))
    }
}
