import XCTest
@testable import OkTally

final class FakeKeyValueStore: KeyValueStore {
    private var strings: [String: String] = [:]
    private var doubles: [String: Double] = [:]

    func string(forKey key: String) -> String? { strings[key] }
    func set(_ value: String?, forKey key: String) { strings[key] = value }
    func double(forKey key: String) -> Double { doubles[key] ?? 0 }
    func set(_ value: Double, forKey key: String) { doubles[key] = value }
}

private struct FakeSecretStoreError: Error {}

final class FakeSecretStore: SecretStoring {
    private var secrets: [String: String] = [:]
    private(set) var saveCallCount = 0

    /// When set, `save` throws instead of writing — simulates a locked/denied Keychain
    /// so migration and setter failure paths can be exercised.
    var failSave = false

    func save(_ secret: String, providerId: String) throws {
        saveCallCount += 1
        if failSave { throw FakeSecretStoreError() }
        secrets[providerId] = secret
    }
    func load(providerId: String) -> String? { secrets[providerId] }
    func delete(providerId: String) throws { secrets[providerId] = nil }
}

final class PreferencesStoreTests: XCTestCase {
    private func makeStore(kv: FakeKeyValueStore = FakeKeyValueStore(), secrets: FakeSecretStore = FakeSecretStore()) -> PreferencesStore {
        PreferencesStore(store: kv, secretStore: secrets)
    }

    func test_openRouterAPIKey_roundTrips() throws {
        let store = makeStore()
        XCTAssertNil(store.openRouterAPIKey)

        try store.setOpenRouterAPIKey("sk-or-123")

        XCTAssertEqual(store.openRouterAPIKey, "sk-or-123")
    }

    func test_refreshInterval_returnsDefaultWhenUnset() {
        let store = makeStore()
        XCTAssertEqual(store.refreshInterval(for: "claude", default: 60), 60)
    }

    func test_refreshInterval_returnsStoredValueAfterSet() {
        let store = makeStore()
        store.setRefreshInterval(120, for: "claude")
        XCTAssertEqual(store.refreshInterval(for: "claude", default: 60), 120)
    }

    func test_refreshInterval_isPerProvider() {
        let store = makeStore()
        store.setRefreshInterval(120, for: "claude")
        XCTAssertEqual(store.refreshInterval(for: "openrouter", default: 600), 600)
    }

    func test_mimoAPIKey_roundTrips() throws {
        let store = makeStore()
        XCTAssertNil(store.mimoAPIKey)

        try store.setMimoAPIKey("tp-abc123")

        XCTAssertEqual(store.mimoAPIKey, "tp-abc123")
    }

    func test_mimoAllowance_roundTrips() {
        let store = makeStore()
        XCTAssertNil(store.mimoMonthlyAllowanceCredits)

        store.mimoMonthlyAllowanceCredits = 500

        XCTAssertEqual(store.mimoMonthlyAllowanceCredits, 500)
    }

    func test_mimoUsedCredits_defaultsToZero() {
        let store = makeStore()
        XCTAssertEqual(store.mimoUsedCredits, 0)

        store.mimoUsedCredits = 123.5

        XCTAssertEqual(store.mimoUsedCredits, 123.5)
    }

    func test_minimaxAPIKey_roundTrips() throws {
        let store = makeStore()
        XCTAssertNil(store.minimaxAPIKey)

        try store.setMinimaxAPIKey("mm-abc123")

        XCTAssertEqual(store.minimaxAPIKey, "mm-abc123")
    }

    func test_minimaxRegion_defaultsToGlobal() {
        let store = makeStore()
        XCTAssertEqual(store.minimaxRegionRaw, "global")

        store.minimaxRegionRaw = "china"

        XCTAssertEqual(store.minimaxRegionRaw, "china")
    }

    func test_openCodeAPIKey_roundTrips() throws {
        let store = makeStore()
        XCTAssertNil(store.openCodeAPIKey)

        try store.setOpenCodeAPIKey("oc-abc123")

        XCTAssertEqual(store.openCodeAPIKey, "oc-abc123")
    }

    // MARK: - Forecast target

    func test_forecastSlot_defaultsToAutomatic() {
        XCTAssertEqual(makeStore().forecastSlot, .automatic)
    }

    func test_forecastSlot_roundTripsExplicitWindow() {
        let store = makeStore()
        let expected = ForecastSlot.window(providerId: "claude", windowLabel: "5h")

        store.forecastSlot = expected

        XCTAssertEqual(store.forecastSlot, expected)
    }

    // MARK: IMPORTANT 8 regression — API keys must live in the Keychain, not UserDefaults.

    func test_apiKeys_areNotWrittenToUserDefaults() throws {
        let kv = FakeKeyValueStore()
        let store = makeStore(kv: kv)

        try store.setOpenRouterAPIKey("sk-or-1")
        try store.setMimoAPIKey("tp-1")
        try store.setMinimaxAPIKey("mm-1")
        try store.setOpenCodeAPIKey("oc-1")

        XCTAssertNil(kv.string(forKey: "openRouterAPIKey"))
        XCTAssertNil(kv.string(forKey: "mimoAPIKey"))
        XCTAssertNil(kv.string(forKey: "minimaxAPIKey"))
        XCTAssertNil(kv.string(forKey: "openCodeAPIKey"))
    }

    func test_apiKeys_persistInSecretStore() throws {
        let secrets = FakeSecretStore()
        let store = makeStore(secrets: secrets)

        try store.setOpenRouterAPIKey("sk-or-1")

        XCTAssertEqual(secrets.load(providerId: "openrouter"), "sk-or-1")
    }

    /// A key entered by an older build (before this fix) landed in UserDefaults under the
    /// legacy key name. On first read after upgrading, it must be transparently moved into
    /// the Keychain and wiped from UserDefaults — not silently lost.
    func test_legacyUserDefaultsAPIKey_migratesToKeychainOnFirstRead() {
        let kv = FakeKeyValueStore()
        kv.set("sk-or-legacy", forKey: "openRouterAPIKey")
        let secrets = FakeSecretStore()
        let store = makeStore(kv: kv, secrets: secrets)

        let migrated = store.openRouterAPIKey

        XCTAssertEqual(migrated, "sk-or-legacy")
        XCTAssertEqual(secrets.load(providerId: "openrouter"), "sk-or-legacy")
        XCTAssertNil(kv.string(forKey: "openRouterAPIKey"), "legacy plaintext must be wiped after migration")
    }

    func test_settingAPIKeyToNil_deletesFromSecretStore() throws {
        let secrets = FakeSecretStore()
        let store = makeStore(secrets: secrets)
        try store.setMimoAPIKey("tp-1")

        try store.setMimoAPIKey(nil)

        XCTAssertNil(store.mimoAPIKey)
        XCTAssertNil(secrets.load(providerId: "mimo"))
    }

    // MARK: N1/N2 regressions — a failed Keychain write must never destroy the only
    // remaining copy of the key.

    /// Migration: if the Keychain save fails, the legacy UserDefaults value must stay
    /// put (not be wiped) so the key isn't lost, even though the value returned to the
    /// caller for this call is still correct (masks the failure for the current session).
    func test_migration_whenSecretStoreSaveFails_keepsLegacyValueInUserDefaults() {
        let kv = FakeKeyValueStore()
        kv.set("sk-or-legacy", forKey: "openRouterAPIKey")
        let secrets = FakeSecretStore()
        secrets.failSave = true
        let store = makeStore(kv: kv, secrets: secrets)

        let migrated = store.openRouterAPIKey

        XCTAssertEqual(migrated, "sk-or-legacy", "value must still be returned even though migration failed")
        XCTAssertEqual(kv.string(forKey: "openRouterAPIKey"), "sk-or-legacy", "legacy value must NOT be wiped when the Keychain write fails")
        XCTAssertNil(secrets.load(providerId: "openrouter"))
    }

    /// setSecret: if the Keychain save fails, the previously-stored legacy value (if
    /// any) must be preserved — the failed write must not scrub UserDefaults.
    func test_setSecret_whenSaveFails_preservesLegacyValueAndThrows() {
        let kv = FakeKeyValueStore()
        kv.set("sk-or-legacy", forKey: "openRouterAPIKey")
        let secrets = FakeSecretStore()
        secrets.failSave = true
        let store = makeStore(kv: kv, secrets: secrets)

        XCTAssertThrowsError(try store.setOpenRouterAPIKey("sk-or-new")) { error in
            XCTAssertTrue(error is FakeSecretStoreError)
        }

        XCTAssertEqual(kv.string(forKey: "openRouterAPIKey"), "sk-or-legacy", "legacy value must survive a failed save")
        XCTAssertNil(secrets.load(providerId: "openrouter"))
    }

    // MARK: - Alert preferences

    func test_alertsEnabled_defaultsTrue_andRoundTrips() {
        let store = makeStore()
        XCTAssertTrue(store.alertsEnabled)

        store.alertsEnabled = false
        XCTAssertFalse(store.alertsEnabled)

        store.alertsEnabled = true
        XCTAssertTrue(store.alertsEnabled)
    }

    func test_alertPercentThresholds_defaultAndRoundTrip() {
        let store = makeStore()
        XCTAssertEqual(store.alertPercentThresholds, [0.7, 0.9, 1.0])

        store.alertPercentThresholds = [0.9]
        XCTAssertEqual(store.alertPercentThresholds, [0.9])

        // Empty selection persists as "no thresholds", not "back to defaults".
        store.alertPercentThresholds = []
        XCTAssertEqual(store.alertPercentThresholds, [])
    }

    func test_alertLowBalanceThreshold_defaultAndRoundTrip() {
        let store = makeStore()
        XCTAssertEqual(store.alertLowBalanceThreshold, 5.0)

        store.alertLowBalanceThreshold = 12.5
        XCTAssertEqual(store.alertLowBalanceThreshold, 12.5)
    }

    // MARK: - Provider order

    func test_providerOrder_emptyWhenUnset() {
        let store = makeStore()
        XCTAssertEqual(store.providerOrder, [])
    }

    func test_providerOrder_roundTrips() {
        let store = makeStore()
        store.providerOrder = ["mimo", "claude"]
        XCTAssertEqual(store.providerOrder, ["mimo", "claude"])
    }

    func test_providerOrder_emptyArrayClearsStorage() {
        let kv = FakeKeyValueStore()
        let store = makeStore(kv: kv)
        store.providerOrder = ["claude"]
        store.providerOrder = []
        XCTAssertNil(kv.string(forKey: "providerOrder"))
    }

    // MARK: - Popover hidden providers

    func test_popoverHiddenProviders_emptyWhenUnset() {
        let store = makeStore()
        XCTAssertEqual(store.popoverHiddenProviders, [])
    }

    func test_popoverHiddenProviders_roundTrips() {
        let store = makeStore()
        store.popoverHiddenProviders = ["mimo", "claude"]
        XCTAssertEqual(store.popoverHiddenProviders, ["mimo", "claude"])
    }

    func test_popoverHiddenProviders_emptySetClearsStorage() {
        let kv = FakeKeyValueStore()
        let store = makeStore(kv: kv)
        store.popoverHiddenProviders = ["claude"]
        store.popoverHiddenProviders = []
        XCTAssertNil(kv.string(forKey: "popoverHiddenProviders"))
    }
    // MARK: - Contas

    func test_accounts_unsetReturnsLegacyDefaults() {
        XCTAssertEqual(makeStore().accounts, AccountsCatalog.defaultAccounts)
    }

    func test_accounts_roundTrip() {
        let store = makeStore()
        var extra = AccountInstance(id: "claude#abc123", kind: .claude); extra.nickname = "Trabalho"
        store.accounts = AccountsCatalog.defaultAccounts + [extra]
        XCTAssertEqual(store.accounts.last, extra)
    }

    func test_accounts_corruptJSONFallsBackToDefaults() {
        let kv = FakeKeyValueStore(); kv.set("{not json", forKey: "accounts.v1")
        XCTAssertEqual(makeStore(kv: kv).accounts, AccountsCatalog.defaultAccounts)
    }

    func test_accounts_emptyListFallsBackToDefaults() {
        let kv = FakeKeyValueStore(); kv.set("[]", forKey: "accounts.v1")
        XCTAssertEqual(makeStore(kv: kv).accounts, AccountsCatalog.defaultAccounts)
    }

    // MARK: - Chaves de API por conta

    func test_apiKey_legacyInstanceUsesLegacyMigrationPath() throws {
        let kv = FakeKeyValueStore(); kv.set("sk-legacy", forKey: "openRouterAPIKey")
        let secrets = FakeSecretStore()
        let store = makeStore(kv: kv, secrets: secrets)
        XCTAssertEqual(store.apiKey(instanceId: "openrouter"), "sk-legacy")
        // Mesma migração de sempre: saiu do UserDefaults e foi para o Keychain legado.
        XCTAssertNil(kv.string(forKey: "openRouterAPIKey"))
        XCTAssertEqual(secrets.load(providerId: "openrouter"), "sk-legacy")
    }

    func test_apiKey_extraInstanceIsIsolated() throws {
        let store = makeStore()
        try store.setAPIKey("sk-1", instanceId: "openrouter")
        try store.setAPIKey("sk-2", instanceId: "openrouter#abc123")
        XCTAssertEqual(store.apiKey(instanceId: "openrouter"), "sk-1")
        XCTAssertEqual(store.apiKey(instanceId: "openrouter#abc123"), "sk-2")
        XCTAssertEqual(store.openRouterAPIKey, "sk-1")
    }

    func test_apiKey_namedAccessorsStillHitTheLegacyInstance() throws {
        let store = makeStore()
        try store.setMinimaxAPIKey("mm-1")
        try store.setOpenCodeAPIKey("oc-1")
        XCTAssertEqual(store.apiKey(instanceId: "minimax"), "mm-1")
        XCTAssertEqual(store.apiKey(instanceId: "opencode"), "oc-1")
    }

    func test_setAPIKey_nilDeletesOnlyThatInstance() throws {
        let store = makeStore()
        try store.setAPIKey("sk-1", instanceId: "minimax")
        try store.setAPIKey("sk-2", instanceId: "minimax#abc123")
        try store.setAPIKey(nil, instanceId: "minimax#abc123")
        XCTAssertNil(store.apiKey(instanceId: "minimax#abc123"))
        XCTAssertEqual(store.apiKey(instanceId: "minimax"), "sk-1")
    }

    func test_minimaxRegion_perInstance_legacyFallsBackToOldKey() {
        let kv = FakeKeyValueStore(); kv.set("china", forKey: "minimaxRegionRaw")
        let store = makeStore(kv: kv)
        XCTAssertEqual(store.minimaxRegionRaw(instanceId: "minimax"), "china")
        XCTAssertEqual(store.minimaxRegionRaw(instanceId: "minimax#abc123"), "global")
        store.setMinimaxRegionRaw("china", instanceId: "minimax#abc123")
        XCTAssertEqual(store.minimaxRegionRaw(instanceId: "minimax#abc123"), "china")
        store.setMinimaxRegionRaw("global", instanceId: "minimax")
        XCTAssertEqual(store.minimaxRegionRaw, "global")
    }

    // MARK: - Revisão: preferências de uma conta removida

    func test_resetAccountPreferences_legacyMiniMaxClearsGlobalRegionAndInterval() {
        let store = makeStore()
        store.setMinimaxRegionRaw("china", instanceId: "minimax")
        store.setRefreshInterval(120, for: "minimax")
        store.resetAccountPreferences(instanceId: "minimax")
        XCTAssertEqual(store.minimaxRegionRaw(instanceId: "minimax"), "global")
        XCTAssertEqual(store.refreshInterval(for: "minimax", default: 300), 300)
    }

    func test_resetAccountPreferences_extraOnlyTouchesItsOwnKeys() {
        let store = makeStore()
        store.setMinimaxRegionRaw("china", instanceId: "minimax")
        store.setMinimaxRegionRaw("china", instanceId: "minimax#abc123")
        store.setRefreshInterval(120, for: "minimax#abc123")
        store.resetAccountPreferences(instanceId: "minimax#abc123")
        XCTAssertEqual(store.minimaxRegionRaw(instanceId: "minimax#abc123"), "global")
        XCTAssertEqual(store.refreshInterval(for: "minimax#abc123", default: 300), 300)
        XCTAssertEqual(store.minimaxRegionRaw(instanceId: "minimax"), "china")
    }

    // MARK: - Revisão: cache das contas (lidas a cada `displayName`)

    func test_accounts_repeatedReadsDecodeOnce() {
        let store = makeStore()
        store.accounts = AccountsCatalog.defaultAccounts
        let before = store.accountsDecodeCount
        for _ in 0..<50 { _ = store.accounts }
        XCTAssertLessThanOrEqual(store.accountsDecodeCount - before, 1)
    }

    func test_accounts_cacheInvalidatedBySetter() {
        let store = makeStore()
        store.accounts = AccountsCatalog.defaultAccounts
        _ = store.accounts
        var extra = AccountInstance(id: "codex#abc123", kind: .codex); extra.nickname = "B"
        store.accounts = AccountsCatalog.defaultAccounts + [extra]
        XCTAssertEqual(store.accounts.last, extra)
    }

    /// Outro `PreferencesStore` sobre o mesmo armazenamento (o app tem mais de um) também
    /// invalida: a chave do cache é o texto gravado, não só o setter local.
    func test_accounts_cacheSeesWritesFromAnotherStoreInstance() {
        let kv = FakeKeyValueStore()
        let a = makeStore(kv: kv), b = makeStore(kv: kv)
        XCTAssertEqual(a.accounts, AccountsCatalog.defaultAccounts)
        var extra = AccountInstance(id: "claude#abc123", kind: .claude); extra.nickname = "Trabalho"
        b.accounts = AccountsCatalog.defaultAccounts + [extra]
        XCTAssertEqual(a.accounts.last, extra)
    }
}
