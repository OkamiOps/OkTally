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
}
