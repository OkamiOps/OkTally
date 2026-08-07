import XCTest
@testable import OkTally

final class InMemoryTokenStore: TokenStoring {
    private var storage: [String: OAuthToken] = [:]
    func save(_ token: OAuthToken, providerId: String) throws { storage[providerId] = token }
    func load(providerId: String) -> OAuthToken? { storage[providerId] }
    func delete(providerId: String) throws { storage[providerId] = nil }
}

final class TokenStoreTests: XCTestCase {
    func test_saveLoadDelete_roundTrips() throws {
        let store = InMemoryTokenStore()
        let token = OAuthToken(accessToken: "at", refreshToken: "rt", expiresAt: Date(timeIntervalSince1970: 2_000_000_000), extra: ["account_id": "acc1"])

        try store.save(token, providerId: "codex")

        XCTAssertEqual(store.load(providerId: "codex"), token)
        try store.delete(providerId: "codex")
        XCTAssertNil(store.load(providerId: "codex"))
    }

    func test_load_unknownProvider_returnsNil() {
        XCTAssertNil(InMemoryTokenStore().load(providerId: "nope"))
    }

    func test_isExpired_falseWhenNoExpiry() {
        let token = OAuthToken(accessToken: "at", refreshToken: nil, expiresAt: nil, extra: [:])
        XCTAssertFalse(token.isExpired)
    }

    func test_isExpired_trueWithinSixtySecondSkew() {
        let token = OAuthToken(accessToken: "at", refreshToken: nil, expiresAt: Date().addingTimeInterval(30), extra: [:])
        XCTAssertTrue(token.isExpired)
    }

    func test_isExpired_falseWhenComfortablyValid() {
        let token = OAuthToken(accessToken: "at", refreshToken: nil, expiresAt: Date().addingTimeInterval(3600), extra: [:])
        XCTAssertFalse(token.isExpired)
    }

    func test_oauthToken_codableRoundTrip() throws {
        let token = OAuthToken(accessToken: "at", refreshToken: "rt", expiresAt: Date(timeIntervalSince1970: 1_000_000), extra: ["k": "v"])
        let decoded = try JSONDecoder().decode(OAuthToken.self, from: JSONEncoder().encode(token))
        XCTAssertEqual(decoded, token)
    }
}
