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

final class FakeSecretStore: SecretStoring {
    private var secrets: [String: String] = [:]
    private(set) var saveCallCount = 0

    func save(_ secret: String, providerId: String) throws {
        saveCallCount += 1
        secrets[providerId] = secret
    }
    func load(providerId: String) -> String? { secrets[providerId] }
    func delete(providerId: String) throws { secrets[providerId] = nil }
}

final class PreferencesStoreTests: XCTestCase {
    private func makeStore(kv: FakeKeyValueStore = FakeKeyValueStore(), secrets: FakeSecretStore = FakeSecretStore()) -> PreferencesStore {
        PreferencesStore(store: kv, secretStore: secrets)
    }

    func test_openRouterAPIKey_roundTrips() {
        let store = makeStore()
        XCTAssertNil(store.openRouterAPIKey)

        store.openRouterAPIKey = "sk-or-123"

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

    func test_mimoAPIKey_roundTrips() {
        let store = makeStore()
        XCTAssertNil(store.mimoAPIKey)

        store.mimoAPIKey = "tp-abc123"

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

    func test_minimaxAPIKey_roundTrips() {
        let store = makeStore()
        XCTAssertNil(store.minimaxAPIKey)

        store.minimaxAPIKey = "mm-abc123"

        XCTAssertEqual(store.minimaxAPIKey, "mm-abc123")
    }

    func test_minimaxRegion_defaultsToGlobal() {
        let store = makeStore()
        XCTAssertEqual(store.minimaxRegionRaw, "global")

        store.minimaxRegionRaw = "china"

        XCTAssertEqual(store.minimaxRegionRaw, "china")
    }

    func test_openCodeAPIKey_roundTrips() {
        let store = makeStore()
        XCTAssertNil(store.openCodeAPIKey)

        store.openCodeAPIKey = "oc-abc123"

        XCTAssertEqual(store.openCodeAPIKey, "oc-abc123")
    }

    // MARK: IMPORTANT 8 regression — API keys must live in the Keychain, not UserDefaults.

    func test_apiKeys_areNotWrittenToUserDefaults() {
        let kv = FakeKeyValueStore()
        let store = makeStore(kv: kv)

        store.openRouterAPIKey = "sk-or-1"
        store.mimoAPIKey = "tp-1"
        store.minimaxAPIKey = "mm-1"
        store.openCodeAPIKey = "oc-1"

        XCTAssertNil(kv.string(forKey: "openRouterAPIKey"))
        XCTAssertNil(kv.string(forKey: "mimoAPIKey"))
        XCTAssertNil(kv.string(forKey: "minimaxAPIKey"))
        XCTAssertNil(kv.string(forKey: "openCodeAPIKey"))
    }

    func test_apiKeys_persistInSecretStore() {
        let secrets = FakeSecretStore()
        let store = makeStore(secrets: secrets)

        store.openRouterAPIKey = "sk-or-1"

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

    func test_settingAPIKeyToNil_deletesFromSecretStore() {
        let secrets = FakeSecretStore()
        let store = makeStore(secrets: secrets)
        store.mimoAPIKey = "tp-1"

        store.mimoAPIKey = nil

        XCTAssertNil(store.mimoAPIKey)
        XCTAssertNil(secrets.load(providerId: "mimo"))
    }
}
