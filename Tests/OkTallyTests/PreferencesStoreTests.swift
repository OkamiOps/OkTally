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

final class PreferencesStoreTests: XCTestCase {
    func test_openRouterAPIKey_roundTrips() {
        let store = PreferencesStore(store: FakeKeyValueStore())
        XCTAssertNil(store.openRouterAPIKey)

        store.openRouterAPIKey = "sk-or-123"

        XCTAssertEqual(store.openRouterAPIKey, "sk-or-123")
    }

    func test_refreshInterval_returnsDefaultWhenUnset() {
        let store = PreferencesStore(store: FakeKeyValueStore())
        XCTAssertEqual(store.refreshInterval(for: "claude", default: 60), 60)
    }

    func test_refreshInterval_returnsStoredValueAfterSet() {
        let store = PreferencesStore(store: FakeKeyValueStore())
        store.setRefreshInterval(120, for: "claude")
        XCTAssertEqual(store.refreshInterval(for: "claude", default: 60), 120)
    }

    func test_refreshInterval_isPerProvider() {
        let store = PreferencesStore(store: FakeKeyValueStore())
        store.setRefreshInterval(120, for: "claude")
        XCTAssertEqual(store.refreshInterval(for: "openrouter", default: 600), 600)
    }

    func test_mimoAPIKey_roundTrips() {
        let store = PreferencesStore(store: FakeKeyValueStore())
        XCTAssertNil(store.mimoAPIKey)

        store.mimoAPIKey = "tp-abc123"

        XCTAssertEqual(store.mimoAPIKey, "tp-abc123")
    }

    func test_mimoAllowance_roundTrips() {
        let store = PreferencesStore(store: FakeKeyValueStore())
        XCTAssertNil(store.mimoMonthlyAllowanceCredits)

        store.mimoMonthlyAllowanceCredits = 500

        XCTAssertEqual(store.mimoMonthlyAllowanceCredits, 500)
    }

    func test_mimoUsedCredits_defaultsToZero() {
        let store = PreferencesStore(store: FakeKeyValueStore())
        XCTAssertEqual(store.mimoUsedCredits, 0)

        store.mimoUsedCredits = 123.5

        XCTAssertEqual(store.mimoUsedCredits, 123.5)
    }

    func test_minimaxAPIKey_roundTrips() {
        let store = PreferencesStore(store: FakeKeyValueStore())
        XCTAssertNil(store.minimaxAPIKey)

        store.minimaxAPIKey = "mm-abc123"

        XCTAssertEqual(store.minimaxAPIKey, "mm-abc123")
    }

    func test_minimaxRegion_defaultsToGlobal() {
        let store = PreferencesStore(store: FakeKeyValueStore())
        XCTAssertEqual(store.minimaxRegionRaw, "global")

        store.minimaxRegionRaw = "china"

        XCTAssertEqual(store.minimaxRegionRaw, "china")
    }

    func test_openCodeAPIKey_roundTrips() {
        let store = PreferencesStore(store: FakeKeyValueStore())
        XCTAssertNil(store.openCodeAPIKey)

        store.openCodeAPIKey = "oc-abc123"

        XCTAssertEqual(store.openCodeAPIKey, "oc-abc123")
    }
}
