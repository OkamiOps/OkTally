# OkTally Plan 2 Implementation Plan — Six Providers + Own-OAuth

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add app-owned OAuth infrastructure (PKCE, device-code, Keychain token storage, auto-refresh), an `estimated` quota shape, and six provider plugins (Codex, Claude retrofit, MiniMax, Cursor, OpenCode, SuperGrok) to OkTally.

**Architecture:** Extends the Plan 1 codebase (SPM, SwiftUI MenuBarExtra, GRDB, protocol-seamed plugins). New `Sources/OkTally/Auth/` module hosts `TokenStore` + `OAuthManager`; each plugin follows the established client/provider split with fixture-backed tests. Providers whose endpoints are undocumented get an explicit live schema-pin step before their parser is trusted.

**Tech Stack:** Swift 5.9, macOS 13+, SwiftUI/AppKit, GRDB.swift, CryptoKit (MiMo key decryption), Network/NIO-free localhost listener via `NWListener`.

**Design spec:** `docs/superpowers/specs/2026-08-07-oktally-plan2-design.md`. Research: `docs/superpowers/research/plan2-*.md`.

## Global Constraints

- Platform: macOS 13.0+ only. Swift tools version: 5.9. GRDB.swift is the only non-Apple dependency — no new packages.
- No dependency on installed CLIs or their credential files. Sanctioned exceptions (owner-approved): Cursor's `state.vscdb` read and OpenCode's `opencode.db` read, both degrading to a "não detectado" state when absent.
- OAuth tokens live in OkTally's own Keychain entries, service `com.oktally.app.oauth.<providerId>`.
- All new error enums conform to `LocalizedError` with Portuguese messages (Plan 1 convention).
- Every task ends with a commit; `feat:`/`test:`/`fix:` prefixes.
- Tests: no real network/Keychain; fixtures via `Bundle.module.url(..., subdirectory: "Fixtures")`; reuse `URLProtocolStub`, adding stubs under distinct URLs only.
- NEVER print or log secret values (tokens, keys). Schema/key names only in any diagnostic output.

---

### Task 1: OAuthToken model + TokenStore (Keychain)

**Files:**
- Create: `Sources/OkTally/Auth/OAuthToken.swift`
- Create: `Sources/OkTally/Auth/TokenStore.swift`
- Test: `Tests/OkTallyTests/TokenStoreTests.swift`

**Interfaces:**
- Consumes: Foundation, Security.
- Produces: `OAuthToken` (struct, Codable/Equatable: `accessToken: String`, `refreshToken: String?`, `expiresAt: Date?`, `extra: [String: String]` for provider-specific fields like Codex's `account_id`; `var isExpired: Bool` — true when `expiresAt` is non-nil and within 60s of now), `TokenStoring` protocol (`func save(_ token: OAuthToken, providerId: String) throws`, `func load(providerId: String) -> OAuthToken?`, `func delete(providerId: String) throws`), `KeychainTokenStore: TokenStoring` (real impl, service `com.oktally.app.oauth.<providerId>`), `InMemoryTokenStore: TokenStoring` (in `Tests/`, shared test double). Tasks 2, 4, 6, 11 depend on `TokenStoring`.

- [ ] **Step 1: Write the failing tests (using `InMemoryTokenStore` for logic, plus pure `OAuthToken` tests)**

```swift
// Tests/OkTallyTests/TokenStoreTests.swift
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
```

- [ ] **Step 2: Run to confirm compile failure**

Run: `swift test --filter TokenStoreTests`
Expected: FAIL — `cannot find type 'TokenStoring' in scope`.

- [ ] **Step 3: Implement `OAuthToken`**

```swift
// Sources/OkTally/Auth/OAuthToken.swift
import Foundation

struct OAuthToken: Codable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
    let extra: [String: String]

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date().addingTimeInterval(60) >= expiresAt
    }
}
```

- [ ] **Step 4: Implement `TokenStoring` + `KeychainTokenStore`**

```swift
// Sources/OkTally/Auth/TokenStore.swift
import Foundation
import Security

protocol TokenStoring {
    func save(_ token: OAuthToken, providerId: String) throws
    func load(providerId: String) -> OAuthToken?
    func delete(providerId: String) throws
}

enum TokenStoreError: Error, LocalizedError {
    case keychainWriteFailed(OSStatus)
    case keychainDeleteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychainWriteFailed(let status):
            return "Falha ao gravar token no Keychain (status \(status))."
        case .keychainDeleteFailed(let status):
            return "Falha ao remover token do Keychain (status \(status))."
        }
    }
}

final class KeychainTokenStore: TokenStoring {
    private func service(_ providerId: String) -> String { "com.oktally.app.oauth.\(providerId)" }

    func save(_ token: OAuthToken, providerId: String) throws {
        let data = try JSONEncoder().encode(token)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service(providerId),
            kSecAttrAccount as String: "oktally"
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw TokenStoreError.keychainWriteFailed(status) }
    }

    func load(providerId: String) -> OAuthToken? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service(providerId),
            kSecAttrAccount as String: "oktally",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(OAuthToken.self, from: data)
    }

    func delete(providerId: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service(providerId),
            kSecAttrAccount as String: "oktally"
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TokenStoreError.keychainDeleteFailed(status)
        }
    }
}
```

- [ ] **Step 5: Run tests, then full suite**

Run: `swift test --filter TokenStoreTests` — expect PASS (6 tests).
Run: `swift test` — expect all pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/OkTally/Auth Tests/OkTallyTests/TokenStoreTests.swift
git commit -m "feat: add OAuthToken model and Keychain-backed TokenStore"
```

---

### Task 2: OAuthManager — token exchange + refresh (network logic, browser flow stubbed)

**Files:**
- Create: `Sources/OkTally/Auth/OAuthConfig.swift`
- Create: `Sources/OkTally/Auth/OAuthManager.swift`
- Test: `Tests/OkTallyTests/OAuthManagerTests.swift`
- Test fixture: `Tests/OkTallyTests/Fixtures/oauth_token_response.json`

**Interfaces:**
- Consumes: `OAuthToken`, `TokenStoring` (Task 1), `URLProtocolStub` (Plan 1).
- Produces: `OAuthConfig` (struct: `providerId: String`, `authorizeURL: URL`, `tokenURL: URL`, `clientId: String`, `scopes: [String]`, `redirectURI: String`), `TokenEndpointResponse` (Codable, decodes `access_token`, `refresh_token?`, `expires_in?` seconds), `OAuthError` (enum: `.tokenExchangeFailed(Int?)`, `.noRefreshToken`, `.refreshFailed(Int?)`, all `LocalizedError`), `OAuthManaging` protocol (`func validAccessToken(providerId: String, config: OAuthConfig) async throws -> String`, `func exchangeCode(_ code: String, verifier: String, config: OAuthConfig) async throws -> OAuthToken`, `func refresh(providerId: String, config: OAuthConfig) async throws -> OAuthToken`), `OAuthManager: OAuthManaging` (`init(store: TokenStoring, session: URLSession = .shared, now: @escaping () -> Date = Date.init)`). `validAccessToken` returns the stored token's access token when not expired, otherwise refreshes. Task 4/6/11 call `validAccessToken` before each fetch.

Note: the interactive browser/PKCE-authorize half (opening the browser, running the localhost listener, generating the code verifier/challenge) is Task 3's `PKCEFlow`; this task is the pure, testable token-endpoint half. `exchangeCode` is what the loopback callback calls once it has the `code`.

- [ ] **Step 1: Create the fixture**

```json
// Tests/OkTallyTests/Fixtures/oauth_token_response.json
{ "access_token": "new-access", "refresh_token": "new-refresh", "expires_in": 3600 }
```

- [ ] **Step 2: Write the failing tests**

```swift
// Tests/OkTallyTests/OAuthManagerTests.swift
import XCTest
@testable import OkTally

final class OAuthManagerTests: XCTestCase {
    private let config = OAuthConfig(
        providerId: "codex",
        authorizeURL: URL(string: "https://auth.example.com/authorize")!,
        tokenURL: URL(string: "https://auth.example.com/oauth/token")!,
        clientId: "client123",
        scopes: ["openid"],
        redirectURI: "http://127.0.0.1:0/callback"
    )

    private func makeSession() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: cfg)
    }

    func test_validAccessToken_returnsStoredTokenWhenNotExpired() async throws {
        let store = InMemoryTokenStore()
        try store.save(OAuthToken(accessToken: "still-good", refreshToken: "rt", expiresAt: Date().addingTimeInterval(3600), extra: [:]), providerId: "codex")
        let manager = OAuthManager(store: store, session: makeSession())

        let token = try await manager.validAccessToken(providerId: "codex", config: config)

        XCTAssertEqual(token, "still-good")
    }

    func test_validAccessToken_refreshesWhenExpired() async throws {
        let data = try Data(contentsOf: Bundle.module.url(forResource: "oauth_token_response", withExtension: "json", subdirectory: "Fixtures")!)
        URLProtocolStub.stubResponses[config.tokenURL] = (data, 200)
        let store = InMemoryTokenStore()
        try store.save(OAuthToken(accessToken: "expired", refreshToken: "rt", expiresAt: Date().addingTimeInterval(-10), extra: [:]), providerId: "codex")
        let manager = OAuthManager(store: store, session: makeSession())

        let token = try await manager.validAccessToken(providerId: "codex", config: config)

        XCTAssertEqual(token, "new-access")
        XCTAssertEqual(store.load(providerId: "codex")?.refreshToken, "new-refresh")
    }

    func test_refresh_withoutRefreshToken_throws() async {
        let store = InMemoryTokenStore()
        try? store.save(OAuthToken(accessToken: "at", refreshToken: nil, expiresAt: Date().addingTimeInterval(-10), extra: [:]), providerId: "codex")
        let manager = OAuthManager(store: store, session: makeSession())

        do {
            _ = try await manager.refresh(providerId: "codex", config: config)
            XCTFail("expected throw")
        } catch OAuthError.noRefreshToken {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func test_exchangeCode_storesTokenWithExpiry() async throws {
        let data = try Data(contentsOf: Bundle.module.url(forResource: "oauth_token_response", withExtension: "json", subdirectory: "Fixtures")!)
        URLProtocolStub.stubResponses[config.tokenURL] = (data, 200)
        let store = InMemoryTokenStore()
        let fixedNow = Date(timeIntervalSince1970: 1_000_000)
        let manager = OAuthManager(store: store, session: makeSession(), now: { fixedNow })

        let token = try await manager.exchangeCode("authcode", verifier: "verifier", config: config)

        XCTAssertEqual(token.accessToken, "new-access")
        XCTAssertEqual(token.expiresAt, fixedNow.addingTimeInterval(3600))
        XCTAssertEqual(store.load(providerId: "codex")?.accessToken, "new-access")
    }
}
```

- [ ] **Step 3: Run to confirm compile failure**

Run: `swift test --filter OAuthManagerTests`
Expected: FAIL — `cannot find type 'OAuthConfig' in scope`.

- [ ] **Step 4: Implement `OAuthConfig`**

```swift
// Sources/OkTally/Auth/OAuthConfig.swift
import Foundation

struct OAuthConfig {
    let providerId: String
    let authorizeURL: URL
    let tokenURL: URL
    let clientId: String
    let scopes: [String]
    let redirectURI: String
}
```

- [ ] **Step 5: Implement `OAuthManager`**

```swift
// Sources/OkTally/Auth/OAuthManager.swift
import Foundation

struct TokenEndpointResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

enum OAuthError: Error, LocalizedError {
    case tokenExchangeFailed(Int?)
    case noRefreshToken
    case refreshFailed(Int?)

    var errorDescription: String? {
        switch self {
        case .tokenExchangeFailed(let code):
            return "Falha na troca do código OAuth (código \(code.map(String.init) ?? "desconhecido"))."
        case .noRefreshToken:
            return "Sessão expirada e sem refresh token — entre novamente."
        case .refreshFailed(let code):
            return "Falha ao renovar a sessão (código \(code.map(String.init) ?? "desconhecido")) — entre novamente."
        }
    }
}

protocol OAuthManaging {
    func validAccessToken(providerId: String, config: OAuthConfig) async throws -> String
    func exchangeCode(_ code: String, verifier: String, config: OAuthConfig) async throws -> OAuthToken
    func refresh(providerId: String, config: OAuthConfig) async throws -> OAuthToken
}

final class OAuthManager: OAuthManaging {
    private let store: TokenStoring
    private let session: URLSession
    private let now: () -> Date

    init(store: TokenStoring, session: URLSession = .shared, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.session = session
        self.now = now
    }

    func validAccessToken(providerId: String, config: OAuthConfig) async throws -> String {
        guard let token = store.load(providerId: providerId) else {
            throw OAuthError.noRefreshToken
        }
        if !token.isExpired { return token.accessToken }
        return try await refresh(providerId: providerId, config: config).accessToken
    }

    func exchangeCode(_ code: String, verifier: String, config: OAuthConfig) async throws -> OAuthToken {
        let form = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": config.redirectURI,
            "client_id": config.clientId,
            "code_verifier": verifier
        ]
        let response = try await postForm(form, to: config.tokenURL, failure: OAuthError.tokenExchangeFailed)
        let token = makeToken(from: response, previousRefresh: nil)
        try store.save(token, providerId: config.providerId)
        return token
    }

    func refresh(providerId: String, config: OAuthConfig) async throws -> OAuthToken {
        guard let existing = store.load(providerId: providerId), let refreshToken = existing.refreshToken else {
            throw OAuthError.noRefreshToken
        }
        let form = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": config.clientId
        ]
        let response = try await postForm(form, to: config.tokenURL, failure: OAuthError.refreshFailed)
        let token = makeToken(from: response, previousRefresh: refreshToken, previousExtra: existing.extra)
        try store.save(token, providerId: providerId)
        return token
    }

    private func makeToken(from response: TokenEndpointResponse, previousRefresh: String?, previousExtra: [String: String] = [:]) -> OAuthToken {
        let expiresAt = response.expiresIn.map { now().addingTimeInterval(TimeInterval($0)) }
        return OAuthToken(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? previousRefresh,
            expiresAt: expiresAt,
            extra: previousExtra
        )
    }

    private func postForm(_ form: [String: String], to url: URL, failure: (Int?) -> OAuthError) async throws -> TokenEndpointResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? $0.value)" }
            .joined(separator: "&").data(using: .utf8)
        let (data, urlResponse) = try await session.data(for: request)
        guard let http = urlResponse as? HTTPURLResponse, http.statusCode == 200 else {
            throw failure((urlResponse as? HTTPURLResponse)?.statusCode)
        }
        return try JSONDecoder().decode(TokenEndpointResponse.self, from: data)
    }
}

private extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=+")
        return set
    }()
}
```

- [ ] **Step 6: Run tests, then full suite**

Run: `swift test --filter OAuthManagerTests` — expect PASS (4 tests).
Run: `swift test` — expect all pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/OkTally/Auth/OAuthConfig.swift Sources/OkTally/Auth/OAuthManager.swift Tests/OkTallyTests/OAuthManagerTests.swift Tests/OkTallyTests/Fixtures/oauth_token_response.json
git commit -m "feat: add OAuthManager token exchange and refresh"
```

---

### Task 3: `QuotaShape.estimated` case + formatter + alert wiring

**Files:**
- Modify: `Sources/OkTally/Core/QuotaShape.swift` (add case + handle in `usedPercent`/`resetAt`/Codable)
- Modify: `Sources/OkTally/UI/QuotaDisplayFormatter.swift` (render estimated)
- Modify: `Sources/OkTally/Notifications/AlertNotificationFormatter.swift` (prefix "Estimado: ")
- Test: `Tests/OkTallyTests/EstimatedQuotaShapeTests.swift`

**Interfaces:**
- Consumes: existing `QuotaShape`, `AlertEvent`, `QuotaDisplayFormatter` (Plan 1).
- Produces: `EstimationBasis` (enum: `.localTokenCount`, `.reactiveRateLimit`; `Codable`), new `QuotaShape` case `.estimated(used: Double, limit: Double?, basis: EstimationBasis, resetAt: Date?)`, `QuotaShape.isEstimated: Bool`, and `AlertNotificationFormatter` prefixes estimated events. `usedPercent` returns a value only when `limit != nil`. Consumed by Tasks 9 (OpenCode) and 10 (MiMo).

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/OkTallyTests/EstimatedQuotaShapeTests.swift
import XCTest
@testable import OkTally

final class EstimatedQuotaShapeTests: XCTestCase {
    func test_estimated_usedPercent_withLimit() {
        let shape = QuotaShape.estimated(used: 30, limit: 60, basis: .localTokenCount, resetAt: nil)
        XCTAssertEqual(shape.usedPercent, 50)
    }

    func test_estimated_usedPercent_nilWithoutLimit() {
        let shape = QuotaShape.estimated(used: 30, limit: nil, basis: .reactiveRateLimit, resetAt: nil)
        XCTAssertNil(shape.usedPercent)
    }

    func test_estimated_resetAt_propagates() {
        let reset = Date(timeIntervalSince1970: 5000)
        let shape = QuotaShape.estimated(used: 1, limit: 2, basis: .localTokenCount, resetAt: reset)
        XCTAssertEqual(shape.resetAt, reset)
    }

    func test_estimated_isEstimatedTrue_othersFalse() {
        XCTAssertTrue(QuotaShape.estimated(used: 1, limit: 2, basis: .localTokenCount, resetAt: nil).isEstimated)
        XCTAssertFalse(QuotaShape.rollingWindow(used: 1, limit: 2, windowStart: Date(), resetAt: Date()).isEstimated)
    }

    func test_estimated_codableRoundTrip() throws {
        let shape = QuotaShape.estimated(used: 12, limit: 40, basis: .reactiveRateLimit, resetAt: Date(timeIntervalSince1970: 111))
        let decoded = try JSONDecoder().decode(QuotaShape.self, from: JSONEncoder().encode(shape))
        XCTAssertEqual(decoded, shape)
    }

    func test_formatter_estimated_prefixesTilde() {
        let shape = QuotaShape.estimated(used: 42, limit: 100, basis: .localTokenCount, resetAt: nil)
        XCTAssertEqual(QuotaDisplayFormatter.valueText(for: shape), "~42%")
    }

    func test_formatter_estimated_noLimit_showsUsedWithBasis() {
        let shape = QuotaShape.estimated(used: 3, limit: nil, basis: .reactiveRateLimit, resetAt: nil)
        XCTAssertEqual(QuotaDisplayFormatter.valueText(for: shape), "~ (limite atingido)")
    }

    func test_alertFormatter_estimatedEvent_prefixesBody() {
        let event = AlertEvent(providerId: "mimo", providerDisplayName: "MiMo", windowLabel: "mensal", threshold: .percentage(0.9), currentPercent: 91, currentRemaining: nil, resetAt: nil, isEstimated: true)
        let (_, body) = AlertNotificationFormatter.format(event)
        XCTAssertTrue(body.hasPrefix("Estimado: "))
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `swift test --filter EstimatedQuotaShapeTests`
Expected: FAIL — `type 'QuotaShape' has no case 'estimated'` / `AlertEvent has no member 'isEstimated'`.

- [ ] **Step 3: Add `EstimationBasis` and the `.estimated` case to `QuotaShape`**

In `Sources/OkTally/Core/QuotaShape.swift`, add above the enum:

```swift
enum EstimationBasis: String, Codable, Equatable {
    case localTokenCount
    case reactiveRateLimit
}
```

Add the case to the enum declaration:

```swift
    case estimated(used: Double, limit: Double?, basis: EstimationBasis, resetAt: Date?)
```

In `usedPercent`, add before the `creditBalance, meteredOnly` catch-all:

```swift
        case .estimated(let used, let limit, _, _):
            guard let limit, limit > 0 else { return nil }
            return min(used / limit, 1.0) * 100
```

In `resetAt`, add:

```swift
        case .estimated(_, _, _, let resetAt): return resetAt
```

Add a computed property:

```swift
    var isEstimated: Bool {
        if case .estimated = self { return true }
        return false
    }
```

In the `Codable` `Kind` enum add `case estimated`, in `CodingKeys` add `case basis`, and add encode/decode branches:

```swift
        // decode:
        case .estimated:
            self = .estimated(
                used: try container.decode(Double.self, forKey: .used),
                limit: try container.decodeIfPresent(Double.self, forKey: .limit),
                basis: try container.decode(EstimationBasis.self, forKey: .basis),
                resetAt: try container.decodeIfPresent(Date.self, forKey: .resetAt)
            )
```

```swift
        // encode:
        case .estimated(let used, let limit, let basis, let resetAt):
            try container.encode(Kind.estimated, forKey: .kind)
            try container.encode(used, forKey: .used)
            try container.encodeIfPresent(limit, forKey: .limit)
            try container.encode(basis, forKey: .basis)
            try container.encodeIfPresent(resetAt, forKey: .resetAt)
```

(Verify the existing `resetAt` `catch`/`creditBalance` handling still compiles — `.estimated` must be handled in every `switch self` over `QuotaShape`, including the ones added in Plan 1.)

- [ ] **Step 4: Render estimated in `QuotaDisplayFormatter`**

In `Sources/OkTally/UI/QuotaDisplayFormatter.swift`, replace `valueText(for:)` body so estimated is handled before the generic percent path:

```swift
    static func valueText(for shape: QuotaShape) -> String {
        if case .estimated(_, let limit, _, _) = shape {
            if let percent = shape.usedPercent {
                return "~\(Int(percent.rounded()))%"
            }
            _ = limit
            return "~ (limite atingido)"
        }
        if let percent = shape.usedPercent {
            return "\(Int(percent.rounded()))%"
        }
        switch shape {
        case .creditBalance(let remaining, let currency):
            return "\(remaining) \(currency)"
        case .meteredOnly(let cost):
            return "$\(cost)"
        default:
            return ""
        }
    }
```

- [ ] **Step 5: Add `isEstimated` to `AlertEvent` and prefix in the formatter**

In `Sources/OkTally/Core/AlertEvent.swift`, add `let isEstimated: Bool` as the last field. Update `AlertEngine.evaluate`'s two `AlertEvent(...)` constructions to pass `isEstimated: window.shape.isEstimated`. In `Sources/OkTally/Notifications/AlertNotificationFormatter.swift`, at the end of `format`, wrap the body:

```swift
        if event.isEstimated {
            body = "Estimado: " + body
        }
        return (title, body)
```

(This adds a required field to `AlertEvent` — update every existing `AlertEvent(...)` initializer in tests too. Search `AlertEvent(` across `Tests/` and add `isEstimated: false` to each; the Plan 1 tests all describe measured events.)

- [ ] **Step 6: Run the targeted tests, fix any Plan 1 test constructors, then full suite**

Run: `swift test --filter EstimatedQuotaShapeTests` — expect PASS (8 tests).
Run: `swift test` — expect all pass (fix any `AlertEvent(` call sites the compiler flags in the existing suite).

- [ ] **Step 7: Commit**

```bash
git add Sources/OkTally/Core/QuotaShape.swift Sources/OkTally/UI/QuotaDisplayFormatter.swift Sources/OkTally/Core/AlertEvent.swift Sources/OkTally/Core/AlertEngine.swift Sources/OkTally/Notifications/AlertNotificationFormatter.swift Tests/OkTallyTests
git commit -m "feat: add estimated QuotaShape with distinct display and alert prefix"
```

---

### Task 4: PKCE helpers + loopback callback listener

**Files:**
- Create: `Sources/OkTally/Auth/PKCE.swift`
- Create: `Sources/OkTally/Auth/LoopbackCallbackServer.swift`
- Create: `Sources/OkTally/Auth/BrowserOAuthFlow.swift`
- Test: `Tests/OkTallyTests/PKCETests.swift`

**Interfaces:**
- Consumes: `OAuthConfig`, `OAuthManaging` (Task 2), CryptoKit, Network (`NWListener`), AppKit (`NSWorkspace`).
- Produces: `PKCE` (enum: `static func makeVerifier() -> String` (43–128 char base64url random), `static func challenge(for verifier: String) -> String` (base64url SHA256), `static func parseCode(fromCallbackPath path: String, expectedState: String) -> String?`), `LoopbackCallbackServer` (class: `func start() throws -> Int` returns the bound port, `var onCallback: ((_ path: String) -> Void)?`, `func stop()`), `BrowserOAuthFlow` (class: `init(manager: OAuthManaging)`, `func login(config: OAuthConfig) async throws -> OAuthToken` — builds the authorize URL with `code_challenge`, opens the browser, runs the loopback server, awaits the code, calls `manager.exchangeCode`). Tasks 5/6/11 call `BrowserOAuthFlow.login`.

Only `PKCE` is unit-tested (pure). `LoopbackCallbackServer`/`BrowserOAuthFlow` involve the real browser/network and are manual-verification only — keep them thin and delegate all testable logic to `PKCE` and `OAuthManager`.

- [ ] **Step 1: Write the failing tests (PKCE only)**

```swift
// Tests/OkTallyTests/PKCETests.swift
import XCTest
import CryptoKit
@testable import OkTally

final class PKCETests: XCTestCase {
    func test_makeVerifier_lengthInRange_urlSafe() {
        let v = PKCE.makeVerifier()
        XCTAssertTrue((43...128).contains(v.count))
        XCTAssertNil(v.rangeOfCharacter(from: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~").inverted))
    }

    func test_challenge_matchesManualSha256Base64url() {
        let verifier = "test-verifier-string-1234567890abcdef"
        let expected = Data(SHA256.hash(data: Data(verifier.utf8)))
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(PKCE.challenge(for: verifier), expected)
    }

    func test_parseCode_extractsCodeWhenStateMatches() {
        let path = "/callback?code=abc123&state=xyz"
        XCTAssertEqual(PKCE.parseCode(fromCallbackPath: path, expectedState: "xyz"), "abc123")
    }

    func test_parseCode_nilWhenStateMismatch() {
        let path = "/callback?code=abc123&state=wrong"
        XCTAssertNil(PKCE.parseCode(fromCallbackPath: path, expectedState: "xyz"))
    }

    func test_parseCode_nilWhenNoCode() {
        XCTAssertNil(PKCE.parseCode(fromCallbackPath: "/callback?state=xyz", expectedState: "xyz"))
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `swift test --filter PKCETests`
Expected: FAIL — `cannot find 'PKCE' in scope`.

- [ ] **Step 3: Implement `PKCE`**

```swift
// Sources/OkTally/Auth/PKCE.swift
import Foundation
import CryptoKit

enum PKCE {
    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func makeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64url(Data(bytes))
    }

    static func challenge(for verifier: String) -> String {
        base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func parseCode(fromCallbackPath path: String, expectedState: String) -> String? {
        guard let components = URLComponents(string: "http://127.0.0.1\(path)") else { return nil }
        let items = components.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == expectedState else { return nil }
        return items.first(where: { $0.name == "code" })?.value
    }
}
```

- [ ] **Step 4: Run PKCE tests — expect PASS (5).**

Run: `swift test --filter PKCETests`

- [ ] **Step 5: Implement `LoopbackCallbackServer` (NWListener)**

```swift
// Sources/OkTally/Auth/LoopbackCallbackServer.swift
import Foundation
import Network

final class LoopbackCallbackServer {
    private var listener: NWListener?
    var onCallback: ((_ path: String) -> Void)?

    func start() throws -> Int {
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .main)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                if let data, let request = String(data: data, encoding: .utf8),
                   let firstLine = request.split(separator: "\r\n").first {
                    let parts = firstLine.split(separator: " ")
                    if parts.count >= 2 { self?.onCallback?(String(parts[1])) }
                }
                let body = "OkTally: pode fechar esta aba e voltar ao app."
                let response = "HTTP/1.1 200 OK\r\nContent-Length: \(body.utf8.count)\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n\(body)"
                connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        listener.start(queue: .main)
        // Busy-wait briefly for the OS to assign a port.
        for _ in 0..<100 {
            if let port = listener.port?.rawValue, port != 0 { return Int(port) }
            Thread.sleep(forTimeInterval: 0.01)
        }
        throw OAuthError.tokenExchangeFailed(nil)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }
}
```

- [ ] **Step 6: Implement `BrowserOAuthFlow`**

```swift
// Sources/OkTally/Auth/BrowserOAuthFlow.swift
import Foundation
import AppKit

final class BrowserOAuthFlow {
    private let manager: OAuthManaging
    init(manager: OAuthManaging) { self.manager = manager }

    func login(config: OAuthConfig) async throws -> OAuthToken {
        let verifier = PKCE.makeVerifier()
        let challenge = PKCE.challenge(for: verifier)
        let state = PKCE.makeVerifier()
        let server = LoopbackCallbackServer()
        let port = try server.start()
        defer { server.stop() }

        let redirect = "http://127.0.0.1:\(port)/callback"
        var comps = URLComponents(url: config.authorizeURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: config.clientId),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "scope", value: config.scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state)
        ]

        let code: String = try await withCheckedThrowingContinuation { continuation in
            server.onCallback = { path in
                if let code = PKCE.parseCode(fromCallbackPath: path, expectedState: state) {
                    continuation.resume(returning: code)
                } else {
                    continuation.resume(throwing: OAuthError.tokenExchangeFailed(nil))
                }
            }
            NSWorkspace.shared.open(comps.url!)
        }

        let redirectConfig = OAuthConfig(
            providerId: config.providerId, authorizeURL: config.authorizeURL,
            tokenURL: config.tokenURL, clientId: config.clientId,
            scopes: config.scopes, redirectURI: redirect
        )
        return try await manager.exchangeCode(code, verifier: verifier, config: redirectConfig)
    }
}
```

- [ ] **Step 7: Build (no new automated tests for the network/browser pieces), then full suite**

Run: `swift build` — expect success.
Run: `swift test` — expect all pass.

- [ ] **Step 8: Commit**

```bash
git add Sources/OkTally/Auth/PKCE.swift Sources/OkTally/Auth/LoopbackCallbackServer.swift Sources/OkTally/Auth/BrowserOAuthFlow.swift Tests/OkTallyTests/PKCETests.swift
git commit -m "feat: add PKCE helpers, loopback callback server, browser OAuth flow"
```

---

### Task 5: Codex plugin (API client + provider)

Research: `docs/superpowers/research/plan2-codex.md` — endpoint confirmed from CLI source.

**Files:**
- Create: `Sources/OkTally/Plugins/Codex/CodexOAuth.swift`
- Create: `Sources/OkTally/Plugins/Codex/CodexUsageAPIClient.swift`
- Create: `Sources/OkTally/Plugins/Codex/CodexUsageProvider.swift`
- Test: `Tests/OkTallyTests/CodexUsageProviderTests.swift`
- Test fixture: `Tests/OkTallyTests/Fixtures/codex_usage_response.json`

**Interfaces:**
- Consumes: `OAuthConfig`, `OAuthManaging` (Task 2), `TokenStoring` (Task 1), `UsageProvider`/`ProviderSnapshot`/`QuotaShape` (Plan 1), `URLProtocolStub`.
- Produces: `CodexOAuth` (enum: `static let config: OAuthConfig` — authorize `https://auth.openai.com/oauth/authorize`, token `https://auth.openai.com/oauth/token`, clientId `app_EMoamEEZ73f0CkXaXp7hrann`, scopes `["openid", "profile", "email", "offline_access"]`), `CodexRateLimitWindow` (Codable: `usedPercent: Double`, `resetAt: Date?` — decodes `used_percent`, `reset_at`), `CodexUsageResponse` (Codable: `planType: String?`, `primaryWindow: CodexRateLimitWindow?`, `secondaryWindow: CodexRateLimitWindow?` — decodes nested `rate_limit.primary_window`/`secondary_window`), `CodexUsageFetching` protocol (`func fetchUsage(accessToken: String, accountId: String?) async throws -> CodexUsageResponse`), `CodexUsageAPIClient: CodexUsageFetching` (GET `https://chatgpt.com/backend-api/wham/usage`, headers `Authorization: Bearer` + `ChatGPT-Account-Id` when present), `CodexUsageError` (`.badResponse(Int?)`, LocalizedError), `CodexUsageProvider: UsageProvider` (`id = "codex"`, `refreshInterval = 300`, `init(oauthManager: OAuthManaging, tokenStore: TokenStoring, apiClient: CodexUsageFetching = CodexUsageAPIClient())`). `isAuthenticated()` = token exists in store. `fetchSnapshot()` gets a valid token via `oauthManager.validAccessToken`, reads `account_id` from the stored token's `extra`, maps primary→`rollingWindow("5h")`, secondary→`rollingWindow("weekly")` (skip windows the response omits). Registered in Task 11.

Field-name caveat: the exact JSON key spelling (`used_percent` vs `used_percent`-style variants, window nesting) was read from CLI source but MUST be re-pinned against a live response in Step 1 before the fixture is trusted.

- [ ] **Step 1: Live schema pin (manual/gated)**

After the owner has logged in via OkTally once (or supplies a fresh Codex access token interactively), make ONE live call to `GET https://chatgpt.com/backend-api/wham/usage` with the bearer + `ChatGPT-Account-Id` headers and compare the real field names/nesting against the fixture below; correct fixture + `CodingKeys` before proceeding. If no live token is available in this session, record that this step is deferred to the owner's manual verification, implement against the research schema, and flag the risk in the task report. NEVER print the token value while doing this.

- [ ] **Step 2: Create the fixture**

```json
// Tests/OkTallyTests/Fixtures/codex_usage_response.json
{
  "plan_type": "pro",
  "rate_limit": {
    "primary_window": { "used_percent": 37.5, "reset_at": "2026-08-07T20:00:00Z" },
    "secondary_window": { "used_percent": 12.0, "reset_at": "2026-08-11T00:00:00Z" }
  }
}
```

- [ ] **Step 3: Write the failing tests**

```swift
// Tests/OkTallyTests/CodexUsageProviderTests.swift
import XCTest
@testable import OkTally

final class FakeOAuthManaging: OAuthManaging {
    var accessTokenToReturn = "tok"
    var errorToThrow: Error?
    func validAccessToken(providerId: String, config: OAuthConfig) async throws -> String {
        if let errorToThrow { throw errorToThrow }
        return accessTokenToReturn
    }
    func exchangeCode(_ code: String, verifier: String, config: OAuthConfig) async throws -> OAuthToken {
        OAuthToken(accessToken: accessTokenToReturn, refreshToken: nil, expiresAt: nil, extra: [:])
    }
    func refresh(providerId: String, config: OAuthConfig) async throws -> OAuthToken {
        OAuthToken(accessToken: accessTokenToReturn, refreshToken: nil, expiresAt: nil, extra: [:])
    }
}

final class FakeCodexUsageFetching: CodexUsageFetching {
    var responseToReturn: CodexUsageResponse!
    private(set) var lastAccountId: String?
    func fetchUsage(accessToken: String, accountId: String?) async throws -> CodexUsageResponse {
        lastAccountId = accountId
        return responseToReturn
    }
}

final class CodexUsageProviderTests: XCTestCase {
    private func makeProvider(fetcher: FakeCodexUsageFetching, tokenInStore: Bool = true) throws -> CodexUsageProvider {
        let store = InMemoryTokenStore()
        if tokenInStore {
            try store.save(OAuthToken(accessToken: "tok", refreshToken: "rt", expiresAt: nil, extra: ["account_id": "acc-9"]), providerId: "codex")
        }
        return CodexUsageProvider(oauthManager: FakeOAuthManaging(), tokenStore: store, apiClient: fetcher)
    }

    func test_fetchSnapshot_mapsBothWindows_andPassesAccountId() async throws {
        let fetcher = FakeCodexUsageFetching()
        fetcher.responseToReturn = CodexUsageResponse(
            planType: "pro",
            primaryWindow: CodexRateLimitWindow(usedPercent: 37.5, resetAt: Date(timeIntervalSince1970: 1000)),
            secondaryWindow: CodexRateLimitWindow(usedPercent: 12, resetAt: Date(timeIntervalSince1970: 2000))
        )
        let provider = try makeProvider(fetcher: fetcher)

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.providerId, "codex")
        XCTAssertEqual(snapshot.quotas.count, 2)
        XCTAssertEqual(snapshot.quotas.first { $0.label == "5h" }?.shape.usedPercent, 37.5)
        XCTAssertEqual(snapshot.quotas.first { $0.label == "weekly" }?.shape.usedPercent, 12)
        XCTAssertEqual(fetcher.lastAccountId, "acc-9")
    }

    func test_fetchSnapshot_missingSecondaryWindow_yieldsOne() async throws {
        let fetcher = FakeCodexUsageFetching()
        fetcher.responseToReturn = CodexUsageResponse(
            planType: nil,
            primaryWindow: CodexRateLimitWindow(usedPercent: 5, resetAt: nil),
            secondaryWindow: nil
        )
        let provider = try makeProvider(fetcher: fetcher)

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.quotas.count, 1)
    }

    func test_isAuthenticated_reflectsStoredToken() async throws {
        let withToken = try makeProvider(fetcher: FakeCodexUsageFetching(), tokenInStore: true)
        let withoutToken = try makeProvider(fetcher: FakeCodexUsageFetching(), tokenInStore: false)
        let a = await withToken.isAuthenticated()
        let b = await withoutToken.isAuthenticated()
        XCTAssertTrue(a)
        XCTAssertFalse(b)
    }

    func test_apiClient_decodesFixture() async throws {
        let data = try Data(contentsOf: Bundle.module.url(forResource: "codex_usage_response", withExtension: "json", subdirectory: "Fixtures")!)
        URLProtocolStub.stubResponses[URL(string: "https://chatgpt.com/backend-api/wham/usage")!] = (data, 200)
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [URLProtocolStub.self]

        let client = CodexUsageAPIClient(session: URLSession(configuration: cfg))
        let response = try await client.fetchUsage(accessToken: "tok", accountId: "acc-9")

        XCTAssertEqual(response.planType, "pro")
        XCTAssertEqual(response.primaryWindow?.usedPercent, 37.5)
        XCTAssertNotNil(response.secondaryWindow)
    }
}
```

- [ ] **Step 4: Run to confirm compile failure**

Run: `swift test --filter CodexUsageProviderTests`
Expected: FAIL — `cannot find type 'CodexUsageResponse' in scope`.

- [ ] **Step 5: Implement `CodexOAuth` config**

```swift
// Sources/OkTally/Plugins/Codex/CodexOAuth.swift
import Foundation

enum CodexOAuth {
    static let config = OAuthConfig(
        providerId: "codex",
        authorizeURL: URL(string: "https://auth.openai.com/oauth/authorize")!,
        tokenURL: URL(string: "https://auth.openai.com/oauth/token")!,
        clientId: "app_EMoamEEZ73f0CkXaXp7hrann",
        scopes: ["openid", "profile", "email", "offline_access"],
        redirectURI: "http://127.0.0.1:0/callback"
    )
}
```

- [ ] **Step 6: Implement `CodexUsageAPIClient`**

```swift
// Sources/OkTally/Plugins/Codex/CodexUsageAPIClient.swift
import Foundation

struct CodexRateLimitWindow: Codable, Equatable {
    let usedPercent: Double
    let resetAt: Date?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case resetAt = "reset_at"
    }
}

struct CodexUsageResponse: Equatable {
    let planType: String?
    let primaryWindow: CodexRateLimitWindow?
    let secondaryWindow: CodexRateLimitWindow?
}

extension CodexUsageResponse: Codable {
    private enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
    }
    private enum RateLimitKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        planType = try container.decodeIfPresent(String.self, forKey: .planType)
        if let rateLimit = try? container.nestedContainer(keyedBy: RateLimitKeys.self, forKey: .rateLimit) {
            primaryWindow = try rateLimit.decodeIfPresent(CodexRateLimitWindow.self, forKey: .primaryWindow)
            secondaryWindow = try rateLimit.decodeIfPresent(CodexRateLimitWindow.self, forKey: .secondaryWindow)
        } else {
            primaryWindow = nil
            secondaryWindow = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(planType, forKey: .planType)
        var rateLimit = container.nestedContainer(keyedBy: RateLimitKeys.self, forKey: .rateLimit)
        try rateLimit.encodeIfPresent(primaryWindow, forKey: .primaryWindow)
        try rateLimit.encodeIfPresent(secondaryWindow, forKey: .secondaryWindow)
    }
}

enum CodexUsageError: Error, LocalizedError {
    case badResponse(Int?)
    var errorDescription: String? {
        switch self {
        case .badResponse(let code):
            return "Codex respondeu com erro (código \(code.map(String.init) ?? "desconhecido"))."
        }
    }
}

protocol CodexUsageFetching {
    func fetchUsage(accessToken: String, accountId: String?) async throws -> CodexUsageResponse
}

final class CodexUsageAPIClient: CodexUsageFetching {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func fetchUsage(accessToken: String, accountId: String?) async throws -> CodexUsageResponse {
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let accountId {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CodexUsageError.badResponse((response as? HTTPURLResponse)?.statusCode)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CodexUsageResponse.self, from: data)
    }
}
```

- [ ] **Step 7: Implement `CodexUsageProvider`**

```swift
// Sources/OkTally/Plugins/Codex/CodexUsageProvider.swift
import Foundation

final class CodexUsageProvider: UsageProvider {
    let id = "codex"
    let displayName = "Codex"
    let authMethod: AuthMethod = .oauthSession
    let refreshInterval: TimeInterval = 300

    private let oauthManager: OAuthManaging
    private let tokenStore: TokenStoring
    private let apiClient: CodexUsageFetching

    init(oauthManager: OAuthManaging, tokenStore: TokenStoring, apiClient: CodexUsageFetching = CodexUsageAPIClient()) {
        self.oauthManager = oauthManager
        self.tokenStore = tokenStore
        self.apiClient = apiClient
    }

    func isAuthenticated() async -> Bool {
        tokenStore.load(providerId: id) != nil
    }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        let accessToken = try await oauthManager.validAccessToken(providerId: id, config: CodexOAuth.config)
        let accountId = tokenStore.load(providerId: id)?.extra["account_id"]
        let usage = try await apiClient.fetchUsage(accessToken: accessToken, accountId: accountId)

        var quotas: [QuotaWindow] = []
        if let primary = usage.primaryWindow {
            quotas.append(QuotaWindow(label: "5h", shape: .rollingWindow(
                used: primary.usedPercent, limit: 100,
                windowStart: (primary.resetAt ?? Date()).addingTimeInterval(-5 * 3600),
                resetAt: primary.resetAt ?? Date()
            )))
        }
        if let secondary = usage.secondaryWindow {
            quotas.append(QuotaWindow(label: "weekly", shape: .rollingWindow(
                used: secondary.usedPercent, limit: 100,
                windowStart: (secondary.resetAt ?? Date()).addingTimeInterval(-7 * 24 * 3600),
                resetAt: secondary.resetAt ?? Date()
            )))
        }
        return ProviderSnapshot(providerId: id, fetchedAt: Date(), quotas: quotas, usageDetail: nil)
    }
}
```

- [ ] **Step 8: Run tests, then full suite**

Run: `swift test --filter CodexUsageProviderTests` — expect PASS (4 tests).
Run: `swift test` — expect all pass.

- [ ] **Step 9: Commit**

```bash
git add Sources/OkTally/Plugins/Codex Tests/OkTallyTests/CodexUsageProviderTests.swift Tests/OkTallyTests/Fixtures/codex_usage_response.json
git commit -m "feat: add Codex usage plugin with own-OAuth"
```

---

### Task 6: Claude retrofit — own OAuth + optional bootstrap import

Research: Plan 1's `plan2` pendency + community-documented Anthropic OAuth client (cedws gist). The Claude Code CLI's public OAuth client id is community-documented as `9d1c250a-e61b-44d9-88ed-5944d1962f5e` with authorize at `https://claude.ai/oauth/authorize` and token at `https://console.anthropic.com/v1/oauth/token`, scopes `org:create_api_key user:profile user:inference` — CONFIRM these three values against a current community source or traffic capture at implementation before hardcoding; they are the only best-guess values in this task.

**Files:**
- Create: `Sources/OkTally/Plugins/Claude/ClaudeOAuth.swift`
- Modify: `Sources/OkTally/Plugins/Claude/ClaudeUsageProvider.swift` (auth swap)
- Test: Modify `Tests/OkTallyTests/ClaudeUsageProviderTests.swift`

**Interfaces:**
- Consumes: `OAuthConfig`, `OAuthManaging`, `TokenStoring`, existing `ClaudeUsageFetching`/`ClaudeUsageAPIClient`, existing `ClaudeCredentialProvider` (kept ONLY for the one-time import bootstrap).
- Produces: `ClaudeOAuth.config: OAuthConfig` (providerId `"claude"`), reworked `ClaudeUsageProvider` (`init(oauthManager: OAuthManaging, tokenStore: TokenStoring, apiClient: ClaudeUsageFetching = ClaudeUsageAPIClient(), legacyCredentialProvider: ClaudeCredentialProvider? = ClaudeCredentialProvider())`): `isAuthenticated()` = OkTally token exists in store; `fetchSnapshot()` uses `oauthManager.validAccessToken(providerId: "claude", config: ClaudeOAuth.config)`; plus `func importLegacyCredentialsIfAvailable() -> Bool` — when no OkTally token exists but the legacy provider can load Claude Code credentials, converts them into an `OAuthToken` (accessToken/refreshToken/expiresAt) and saves to the OkTally store, returning true. Preferences (Task 11) shows an "Importar login do Claude Code" button that calls it.

- [ ] **Step 1: Update the existing tests to the new init, add import-bootstrap tests**

Rewrite `Tests/OkTallyTests/ClaudeUsageProviderTests.swift`'s provider-construction sites: replace `ClaudeUsageProvider(credentialProvider:apiClient:)` with the new signature using `FakeOAuthManaging` (from Task 5's test file — shared, do not redefine) + `InMemoryTokenStore`. Keep the three existing behavior tests (three windows / two windows / isAuthenticated-false-when-no-token). Add:

```swift
    func test_importLegacyCredentials_savesTokenWhenLegacyExists() throws {
        let keychain = FakeCredentialStoreReading()
        keychain.dataToReturn = """
        {"claudeAiOauth":{"accessToken":"legacy-at","refreshToken":"legacy-rt","expiresAt":1900000000000}}
        """.data(using: .utf8)
        let legacy = ClaudeCredentialProvider(keychainReader: keychain, fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let store = InMemoryTokenStore()
        let provider = ClaudeUsageProvider(oauthManager: FakeOAuthManaging(), tokenStore: store, apiClient: FakeClaudeUsageFetching(), legacyCredentialProvider: legacy)

        XCTAssertTrue(provider.importLegacyCredentialsIfAvailable())
        XCTAssertEqual(store.load(providerId: "claude")?.accessToken, "legacy-at")
    }

    func test_importLegacyCredentials_falseWhenNoLegacy() {
        let keychain = FakeCredentialStoreReading()
        let legacy = ClaudeCredentialProvider(keychainReader: keychain, fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let provider = ClaudeUsageProvider(oauthManager: FakeOAuthManaging(), tokenStore: InMemoryTokenStore(), apiClient: FakeClaudeUsageFetching(), legacyCredentialProvider: legacy)

        XCTAssertFalse(provider.importLegacyCredentialsIfAvailable())
    }

    func test_importLegacyCredentials_skipsWhenTokenAlreadyPresent() throws {
        let store = InMemoryTokenStore()
        try store.save(OAuthToken(accessToken: "already", refreshToken: nil, expiresAt: nil, extra: [:]), providerId: "claude")
        let keychain = FakeCredentialStoreReading()
        keychain.dataToReturn = "{\"accessToken\":\"legacy\"}".data(using: .utf8)
        let legacy = ClaudeCredentialProvider(keychainReader: keychain, fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let provider = ClaudeUsageProvider(oauthManager: FakeOAuthManaging(), tokenStore: store, apiClient: FakeClaudeUsageFetching(), legacyCredentialProvider: legacy)

        XCTAssertFalse(provider.importLegacyCredentialsIfAvailable())
        XCTAssertEqual(store.load(providerId: "claude")?.accessToken, "already")
    }
```

- [ ] **Step 2: Run to confirm compile failure** (`swift test --filter ClaudeUsageProviderTests` — init signature mismatch).

- [ ] **Step 3: Implement `ClaudeOAuth` (values flagged for confirmation)**

```swift
// Sources/OkTally/Plugins/Claude/ClaudeOAuth.swift
import Foundation

enum ClaudeOAuth {
    // NOTE: community-documented values (cedws gist et al.) — confirm against a current
    // source or traffic capture before first release; wrong values fail loudly at login.
    static let config = OAuthConfig(
        providerId: "claude",
        authorizeURL: URL(string: "https://claude.ai/oauth/authorize")!,
        tokenURL: URL(string: "https://console.anthropic.com/v1/oauth/token")!,
        clientId: "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
        scopes: ["org:create_api_key", "user:profile", "user:inference"],
        redirectURI: "http://127.0.0.1:0/callback"
    )
}
```

- [ ] **Step 4: Rework `ClaudeUsageProvider`**

Replace the class's auth plumbing, keeping the window-mapping logic from Plan 1 verbatim:

```swift
// Sources/OkTally/Plugins/Claude/ClaudeUsageProvider.swift
import Foundation

final class ClaudeUsageProvider: UsageProvider {
    let id = "claude"
    let displayName = "Claude Code"
    let authMethod: AuthMethod = .oauthSession
    let refreshInterval: TimeInterval = 60

    private let oauthManager: OAuthManaging
    private let tokenStore: TokenStoring
    private let apiClient: ClaudeUsageFetching
    private let legacyCredentialProvider: ClaudeCredentialProvider?

    init(
        oauthManager: OAuthManaging,
        tokenStore: TokenStoring,
        apiClient: ClaudeUsageFetching = ClaudeUsageAPIClient(),
        legacyCredentialProvider: ClaudeCredentialProvider? = ClaudeCredentialProvider()
    ) {
        self.oauthManager = oauthManager
        self.tokenStore = tokenStore
        self.apiClient = apiClient
        self.legacyCredentialProvider = legacyCredentialProvider
    }

    func isAuthenticated() async -> Bool {
        tokenStore.load(providerId: id) != nil
    }

    @discardableResult
    func importLegacyCredentialsIfAvailable() -> Bool {
        guard tokenStore.load(providerId: id) == nil,
              let credentials = try? legacyCredentialProvider?.loadCredentials() else { return false }
        let token = OAuthToken(
            accessToken: credentials.accessToken,
            refreshToken: credentials.refreshToken,
            expiresAt: credentials.expiresAt,
            extra: [:]
        )
        return (try? tokenStore.save(token, providerId: id)) != nil
    }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        let accessToken = try await oauthManager.validAccessToken(providerId: id, config: ClaudeOAuth.config)
        let usage = try await apiClient.fetchUsage(accessToken: accessToken)
        // window mapping identical to Plan 1 (5h / weekly / weekly-opus) — keep as-is
        var quotas = [
            QuotaWindow(label: "5h", shape: .rollingWindow(
                used: usage.fiveHour.utilization, limit: 100,
                windowStart: usage.fiveHour.resetsAt.addingTimeInterval(-5 * 3600),
                resetAt: usage.fiveHour.resetsAt
            )),
            QuotaWindow(label: "weekly", shape: .rollingWindow(
                used: usage.sevenDay.utilization, limit: 100,
                windowStart: usage.sevenDay.resetsAt.addingTimeInterval(-7 * 24 * 3600),
                resetAt: usage.sevenDay.resetsAt
            ))
        ]
        if let opus = usage.sevenDayOpus {
            quotas.append(QuotaWindow(label: "weekly-opus", shape: .rollingWindow(
                used: opus.utilization, limit: 100,
                windowStart: opus.resetsAt.addingTimeInterval(-7 * 24 * 3600),
                resetAt: opus.resetsAt
            )))
        }
        return ProviderSnapshot(providerId: id, fetchedAt: Date(), quotas: quotas, usageDetail: nil)
    }
}
```

- [ ] **Step 5: Fix the Task 14 (Plan 1) wiring call site** — `OkTallyApp.init` constructs `ClaudeUsageProvider()`; it now needs `oauthManager`/`tokenStore` arguments. Update it minimally here (full wiring lands in Task 11): create `let tokenStore = KeychainTokenStore()` and `let oauthManager = OAuthManager(store: tokenStore)` in `OkTallyApp.init` and pass them to `ClaudeUsageProvider(oauthManager:tokenStore:)`, and call `claudeProvider.importLegacyCredentialsIfAvailable()` once at startup (preserves current behavior for the owner's existing login so the retrofit isn't a regression).

- [ ] **Step 6: Run tests + full suite** (`swift test` — all pass), **build** (`swift build`).

- [ ] **Step 7: Commit**

```bash
git add Sources/OkTally/Plugins/Claude Sources/OkTally/App/OkTallyApp.swift Tests/OkTallyTests/ClaudeUsageProviderTests.swift
git commit -m "feat: retrofit Claude plugin to app-owned OAuth with legacy import"
```

---

### Task 7: MiniMax plugin

Research: `docs/superpowers/research/plan2-minimax.md` — community-documented with captured live responses.

**Files:**
- Create: `Sources/OkTally/Plugins/MiniMax/MiniMaxAPIClient.swift`
- Create: `Sources/OkTally/Plugins/MiniMax/MiniMaxUsageProvider.swift`
- Test: `Tests/OkTallyTests/MiniMaxUsageProviderTests.swift`
- Test fixture: `Tests/OkTallyTests/Fixtures/minimax_remains_response.json`

**Interfaces:**
- Consumes: `UsageProvider`/`ProviderSnapshot`/`QuotaShape` (Plan 1), `URLProtocolStub`.
- Produces: `MiniMaxRegion` (enum: `.global` → `https://api.minimax.io`, `.china` → `https://api.minimaxi.com`), `MiniMaxModelRemains` (Codable per-model entry — field names below are the research report's; re-pin in Step 1), `MiniMaxRemainsResponse` (Codable: `models: [MiniMaxModelRemains]`), `MiniMaxRemainsFetching` protocol, `MiniMaxAPIClient: MiniMaxRemainsFetching` (`GET {base}/v1/token_plan/remains`, `Authorization: Bearer <key>`), `MiniMaxError` (`.missingAPIKey`, `.badResponse(Int?)`, LocalizedError), `MiniMaxUsageProvider: UsageProvider` (`id = "minimax"`, `refreshInterval = 300`, `init(apiKeyProvider: @escaping () -> String?, region: @escaping () -> MiniMaxRegion, client: MiniMaxRemainsFetching = MiniMaxAPIClient())`). Maps the worst (highest-used) model's 5h window → `rollingWindow("5h")` and weekly → `periodicCounter("weekly")`.

- [ ] **Step 1: Schema pin.** The research report reproduces captured responses with fields like `current_interval_total_count`/`current_interval_usage_count`/`current_interval_remaining_percent`, `current_weekly_*` equivalents, `remains_time`, keyed per model. Before writing the fixture, re-read `docs/superpowers/research/plan2-minimax.md` §response-schema and copy the exact captured field names into the fixture and `CodingKeys` — do not invent variants. If the report's capture is ambiguous on any field, mark it in the fixture with the report's literal spelling and flag in the task report.

- [ ] **Step 2: Create the fixture** (using the report's exact field names; illustrative values)

```json
// Tests/OkTallyTests/Fixtures/minimax_remains_response.json
{
  "model_remains": [
    {
      "model_name": "MiniMax-M3",
      "current_interval_total_count": 1000,
      "current_interval_usage_count": 400,
      "current_interval_remaining_percent": 60,
      "current_weekly_total_count": 5000,
      "current_weekly_usage_count": 1500,
      "current_weekly_remaining_percent": 70,
      "remains_time": "2026-08-07T20:00:00Z"
    }
  ]
}
```

- [ ] **Step 3: Write the failing tests** — mirror the established provider-test pattern exactly (fake fetcher struct; tests: `test_fetchSnapshot_mapsFiveHourAndWeekly` asserting `usedPercent` 40 and 30 for labels "5h"/"weekly", `test_fetchSnapshot_missingAPIKey_throws`, `test_isAuthenticated_reflectsKey`, `test_apiClient_decodesFixture` via `URLProtocolStub` on `https://api.minimax.io/v1/token_plan/remains`). Follow `Tests/OkTallyTests/OpenRouterUsageProviderTests.swift` as the structural template, adjusting names/types.

- [ ] **Step 4: Run to confirm compile failure.**

- [ ] **Step 5: Implement client + provider** — same structure as `OpenRouterAPIClient`/`OpenRouterUsageProvider` with: region-based base URL selection, decode into the pinned schema, and mapping: for each model take `current_interval_usage_count/current_interval_total_count` → `rollingWindow(used:limit:windowStart: resetAt-5h, resetAt: remains_time)` and weekly counts → `periodicCounter(used:limit:resetAt:)`; across models keep the window with the highest `usedPercent` per label (worst-wins), and store all models' entries as extra display detail later if needed (out of scope now).

- [ ] **Step 6: Run tests + full suite.**

- [ ] **Step 7: Commit**

```bash
git add Sources/OkTally/Plugins/MiniMax Tests/OkTallyTests/MiniMaxUsageProviderTests.swift Tests/OkTallyTests/Fixtures/minimax_remains_response.json
git commit -m "feat: add MiniMax token-plan usage plugin"
```

---

### Task 8: Cursor plugin (state.vscdb reader + usage client)

Research: `docs/superpowers/research/plan2-cursor.md`. Sanctioned exception: reads the Cursor app's own SQLite store.

**Files:**
- Create: `Sources/OkTally/Plugins/Cursor/CursorTokenReader.swift`
- Create: `Sources/OkTally/Plugins/Cursor/CursorUsageAPIClient.swift`
- Create: `Sources/OkTally/Plugins/Cursor/CursorUsageProvider.swift`
- Test: `Tests/OkTallyTests/CursorUsageProviderTests.swift`

**Interfaces:**
- Consumes: GRDB (read-only SQLite), `UsageProvider`/`QuotaShape`, `URLProtocolStub`.
- Produces: `CursorTokenReading` protocol (`func readAccessToken() -> String?`), `CursorTokenReader: CursorTokenReading` (`init(dbPath: String = NSHomeDirectory() + "/Library/Application Support/Cursor/User/globalStorage/state.vscdb")` — opens the SQLite read-only, reads table `ItemTable` (key/value) row `cursorAuth/accessToken`; returns nil if file/table/row absent), `CursorUsageError` (`.notDetected`, `.badResponse(Int?)`, LocalizedError — `.notDetected` message: "Cursor não detectado — instale/entre no Cursor para acompanhar o uso."), `CursorUsageFetching` protocol (`func fetchUsage(accessToken: String) async throws -> CursorUsageResponse`), `CursorUsageAPIClient` (POST `https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage`, `Authorization: Bearer`, `Content-Type: application/json`, body `{}`), `CursorUsageResponse` (schema PINNED IN STEP 1 — the struct below is a placeholder shape to be corrected), `CursorUsageProvider: UsageProvider` (`id = "cursor"`, `refreshInterval = 600`, `init(tokenReader: CursorTokenReading = CursorTokenReader(), client: CursorUsageFetching = CursorUsageAPIClient())`). `isAuthenticated()` = `tokenReader.readAccessToken() != nil`; `fetchSnapshot()` throws `.notDetected` when nil. Shape: `creditBalance` (credit pool) or whatever Step 1's pin reveals.

- [ ] **Step 1: Live schema pin (REQUIRED before parser).** With the owner's machine (Cursor installed and logged in), read the token via the reader (never printing it) and make ONE live `GetCurrentPeriodUsage` call, capturing the response JSON structure (redact any ids/emails). Write the real field names into `CursorUsageResponse` and a fixture `Tests/OkTallyTests/Fixtures/cursor_usage_response.json`. If this session cannot perform the live call (no interactive access / owner absent), STOP this task and report BLOCKED — unlike Codex, there is no source-code-derived schema to fall back on; community documentation is too low-confidence to ship a parser against.

- [ ] **Step 2: Token reader test with a fixture SQLite DB built in-test**

```swift
// Tests/OkTallyTests/CursorUsageProviderTests.swift  (reader portion)
import XCTest
import GRDB
@testable import OkTally

final class CursorTokenReaderTests: XCTestCase {
    private func makeFixtureDB(withToken token: String?) throws -> String {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".vscdb").path
        let db = try DatabaseQueue(path: path)
        try db.write { db in
            try db.execute(sql: "CREATE TABLE ItemTable (key TEXT PRIMARY KEY, value BLOB)")
            if let token {
                try db.execute(sql: "INSERT INTO ItemTable (key, value) VALUES (?, ?)", arguments: ["cursorAuth/accessToken", token])
            }
        }
        return path
    }

    func test_readAccessToken_returnsStoredValue() throws {
        let path = try makeFixtureDB(withToken: "cursor-token-123")
        XCTAssertEqual(CursorTokenReader(dbPath: path).readAccessToken(), "cursor-token-123")
    }

    func test_readAccessToken_nilWhenRowMissing() throws {
        let path = try makeFixtureDB(withToken: nil)
        XCTAssertNil(CursorTokenReader(dbPath: path).readAccessToken())
    }

    func test_readAccessToken_nilWhenFileMissing() {
        XCTAssertNil(CursorTokenReader(dbPath: "/nonexistent/state.vscdb").readAccessToken())
    }
}
```

- [ ] **Step 3: Provider tests** — same structural template as prior providers: fake reader + fake fetcher; `test_fetchSnapshot_notDetected_whenNoToken` (asserts `CursorUsageError.notDetected`), `test_isAuthenticated_reflectsTokenPresence`, plus mapping/decode tests written against the Step 1-pinned schema.

- [ ] **Step 4: Implement reader** (GRDB read-only config: `var config = Configuration(); config.readonly = true; DatabaseQueue(path:configuration:)`, `try? … SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken'`, value may be BLOB or TEXT — handle both by trying `String` then `Data`→UTF-8), **client + provider** against the pinned schema, following the established plugin structure.

- [ ] **Step 5: Run tests + full suite.**

- [ ] **Step 6: Commit**

```bash
git add Sources/OkTally/Plugins/Cursor Tests/OkTallyTests/CursorUsageProviderTests.swift Tests/OkTallyTests/Fixtures/cursor_usage_response.json
git commit -m "feat: add Cursor usage plugin reading the app session token"
```

---

### Task 9: OpenCode plugin (local estimate + reactive 429)

Research: `docs/superpowers/research/plan2-opencode.md` — no usage API exists (verified live); estimate from `opencode.db` + reactive 429 parsing.

**Files:**
- Create: `Sources/OkTally/Plugins/OpenCode/OpenCodeLocalEstimator.swift`
- Create: `Sources/OkTally/Plugins/OpenCode/OpenCodeRateLimitParser.swift`
- Create: `Sources/OkTally/Plugins/OpenCode/OpenCodeUsageProvider.swift`
- Test: `Tests/OkTallyTests/OpenCodeUsageProviderTests.swift`

**Interfaces:**
- Consumes: GRDB, `QuotaShape.estimated` (Task 3), `UsageProvider`.
- Produces: `OpenCodeLocalEstimator` (`init(dbPath: String = NSHomeDirectory() + "/.local/share/opencode/opencode.db")`, `func spentInCurrentWindow(windowHours: Int, now: Date) throws -> Decimal?` — nil when DB absent; sums per-message cost from the messages table within the window; exact table/column names PINNED in Step 1 from the local DB's actual schema), `OpenCodeRateLimitParser` (`static func parse(statusCode: Int, body: Data, retryAfterHeader: String?) -> (limitName: String, resetAt: Date?)?` — recognizes `GoUsageLimitError`/`FreeUsageLimitError` JSON with `metadata.limitName`), `OpenCodeUsageProvider: UsageProvider` (`id = "opencode"`, `refreshInterval = 600`, `init(apiKeyProvider: @escaping () -> String?, estimator: OpenCodeLocalEstimator = OpenCodeLocalEstimator(), goWindowBudgets: [(label: String, hours: Int, budget: Decimal)] = [("5h", 5, 12), ("weekly", 168, 30), ("monthly", 720, 60)])`). `fetchSnapshot()` builds one `estimated` window per budget: `used = spent`, `limit = budget`, `basis: .localTokenCount`; when a stored recent 429 result exists (set externally via `func recordRateLimit(limitName: String, resetAt: Date?)`) and its reset is in the future, that window becomes `estimated(used: budget, limit: budget, basis: .reactiveRateLimit, resetAt:)`. DB absent → throws `OpenCodeError.notDetected` ("OpenCode não detectado…"). Go budget dollar values ($12/5h, $30/weekly, $60/monthly per docs at research time) are DEFAULTS the owner can edit later — do not treat as authoritative.

- [ ] **Step 1: Schema pin (local).** `sqlite3 ~/.local/share/opencode/opencode.db ".schema"` (structure only — never SELECT message content) to pin the messages table/column names for cost + timestamp. Write them into the estimator's SQL and mirror them in the fixture-DB builder in tests. If the DB is absent on this machine, use the research report's schema description and flag lower confidence in the task report.

- [ ] **Step 2: Tests** — fixture SQLite DB built in-test (same pattern as Task 8's reader tests): insert messages with known costs/timestamps, assert `spentInCurrentWindow` sums only in-window rows and returns nil for a missing file; parser tests: 429 + `GoUsageLimitError` body + `retry-after: 120` → limitName extracted, resetAt ≈ now+120s; non-429 → nil; provider tests: snapshot has 3 estimated windows with correct `usedPercent`, DB-absent throws `.notDetected`, recorded rate-limit overrides its window to `.reactiveRateLimit`.

- [ ] **Step 3: Implement** estimator (GRDB read-only, `SELECT SUM(cost)…WHERE timestamp >= ?`), parser (JSONDecoder into a permissive struct, `metadata.limitName`), provider (assemble windows per interface description).

- [ ] **Step 4: Run tests + full suite.**

- [ ] **Step 5: Commit**

```bash
git add Sources/OkTally/Plugins/OpenCode Tests/OkTallyTests/OpenCodeUsageProviderTests.swift
git commit -m "feat: add OpenCode estimated-usage plugin with reactive 429 handling"
```

---

### Task 10: MiMo plugin (key-issuance onboarding + local estimate)

Research: `docs/superpowers/research/plan2-mimo.md` — quota is SSO-gated; key issuance flow exists (MiMoCode source); plugin ships `estimated`.

**Files:**
- Create: `Sources/OkTally/Plugins/MiMo/MiMoUsageProvider.swift`
- Test: `Tests/OkTallyTests/MiMoUsageProviderTests.swift`

**Interfaces:**
- Consumes: `QuotaShape.estimated` (Task 3), `PreferencesStore` (extended here with `mimoAPIKey: String?`, `mimoMonthlyAllowanceCredits: Double?`, `mimoUsedCredits: Double` accessors — same `KeyValueStore` pattern as existing keys), `UsageProvider`.
- Produces: `MiMoUsageProvider: UsageProvider` (`id = "mimo"`, `refreshInterval = 3600`, `init(allowanceProvider: @escaping () -> Double?, usedCreditsProvider: @escaping () -> Double)`). `fetchSnapshot()` returns one `estimated` window labeled "mensal": `used = usedCreditsProvider()`, `limit = allowanceProvider()`, `basis: .localTokenCount`, `resetAt: nil`. `isAuthenticated()` = allowance configured. Usage accumulation is MANUAL in this plan (owner updates the used-credits field in Preferences); automatic traffic-observation is explicitly out of scope until a proxy/observer design exists. The MiMoCode browser key-issuance flow (X25519+AES-GCM localhost callback) is DEFERRED to a follow-up — it only automates key entry, delivers no quota data, and its crypto detail deserves its own verified task; the spec's §3.5 promotion path notes this.

- [ ] **Step 1: Extend `PreferencesStore`** with the three accessors + tests mirroring `PreferencesStoreTests` (`test_mimoAllowance_roundTrips`, defaulting `mimoUsedCredits` to 0).

- [ ] **Step 2: Provider tests** — snapshot has one "mensal" estimated window with correct percent; `isAuthenticated` false when allowance nil; one assertion that `usedPercent` is non-nil when allowance set.

- [ ] **Step 3: Implement provider** (trivial assembly per interface description).

- [ ] **Step 4: Run tests + full suite.**

- [ ] **Step 5: Commit**

```bash
git add Sources/OkTally/Plugins/MiMo Sources/OkTally/Preferences/PreferencesStore.swift Tests/OkTallyTests
git commit -m "feat: add MiMo estimated-usage plugin with manual allowance"
```

---

### Task 11: SuperGrok investigation gate + plugin

Research: `docs/superpowers/research/plan2-supergrok.md` — OAuth flow real (device-code, accounts.x.ai) but no public client id; quota endpoint reverse-engineered (gRPC-web `GetGrokCreditsConfig`, `credit_usage_percent` + reset, weekly pool).

**Files (outcome-dependent):**
- Create: `Sources/OkTally/Plugins/SuperGrok/SuperGrokUsageProvider.swift` (+ client/OAuth files per outcome)
- Test: `Tests/OkTallyTests/SuperGrokUsageProviderTests.swift`

**Interfaces:**
- Consumes: `OAuthManaging`/`TokenStoring`, device-code flow (new `DeviceCodeFlow` helper if Path A), `QuotaShape`.
- Produces: `SuperGrokUsageProvider: UsageProvider` (`id = "supergrok"`), shape per outcome below.

- [ ] **Step 1: Investigation gate (time-boxed).** Determine a usable OAuth client id + flow by reading the two working open-source implementations end-to-end: `stnly/pi-grok` and `NousResearch/hermes-agent` (their device-code requests necessarily contain the client id they use — it IS extractable from working open source, the research pass just didn't drill into request-construction code). Also pin the exact `accounts.x.ai` device/token endpoint paths and the `GetGrokCreditsConfig` request/response encoding (gRPC-web framing vs JSON). Record findings in `docs/superpowers/research/plan2-supergrok.md` (append a "Implementation pin" section).
- [ ] **Step 2: Decision fork.**
  - **Path A (client id + endpoint pinned):** implement `DeviceCodeFlow` (RFC 8628: start → poll token endpoint; reuses `OAuthManager.postForm` patterns), `SuperGrokAPIClient` (the credits-config call), provider mapping `credit_usage_percent` → `rollingWindow("weekly", used: percent, limit: 100, resetAt:)`. Fixture + tests per the established plugin template.
  - **Path B (blocked):** implement the provider as `estimated` with a manually-entered weekly percent (same minimal pattern as Task 10), so the card exists and the owner still gets threshold alerts on self-reported usage; append the blocker specifics to the research doc for a future retry.
- [ ] **Step 3: Tests, full suite, commit.**

```bash
git add Sources/OkTally/Plugins/SuperGrok Tests/OkTallyTests/SuperGrokUsageProviderTests.swift docs/superpowers/research/plan2-supergrok.md
git commit -m "feat: add SuperGrok usage plugin"
```

---

### Task 12: Preferences auth UI + final wiring + E2E

**Files:**
- Modify: `Sources/OkTally/UI/PreferencesView.swift` (per-provider sections)
- Modify: `Sources/OkTally/App/OkTallyApp.swift` (register all providers)
- Modify: `Sources/OkTally/UI/QuotaBarView.swift` (dashed estimated bar)

**Interfaces:**
- Consumes: everything from Tasks 1–11 plus Plan 1's `PreferencesStore`/`AppModel`/`PluginRegistry`.
- Produces: the fully wired v2 app — terminal deliverable of this plan.

- [ ] **Step 1: Extend `PreferencesStore` with the remaining provider settings**

Add accessors following the existing `openRouterAPIKey` pattern exactly (same `KeyValueStore` backing, same `Keys` enum style): `minimaxAPIKey: String?`, `minimaxRegionRaw: String?` (stores `"global"`/`"china"`, defaulting to `"global"` when unset), `openCodeAPIKey: String?`. Add round-trip tests to `Tests/OkTallyTests/PreferencesStoreTests.swift` mirroring `test_openRouterAPIKey_roundTrips`, plus `test_minimaxRegion_defaultsToGlobal`.

Run: `swift test --filter PreferencesStoreTests` — expect PASS.

- [ ] **Step 2: Render estimated windows distinctly in `QuotaBarView`**

Replace the `ProgressView` line in `Sources/OkTally/UI/QuotaBarView.swift` so estimated windows are visually distinct from measured ones:

```swift
// Sources/OkTally/UI/QuotaBarView.swift
import SwiftUI

struct QuotaBarView: View {
    let window: QuotaWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(window.label)
                    .font(.caption)
                Spacer()
                Text(QuotaDisplayFormatter.valueText(for: window.shape))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let percent = window.shape.usedPercent {
                ProgressView(value: min(percent, 100), total: 100)
                    .opacity(window.shape.isEstimated ? 0.55 : 1.0)
            }
        }
        .help(window.shape.isEstimated ? "Estimativa local, não confirmada pelo provedor" : "")
    }
}
```

Run: `swift build` — expect success.

- [ ] **Step 3: Add per-provider auth sections to `PreferencesView`**

Rewrite `Sources/OkTally/UI/PreferencesView.swift` so each provider has its own section: OAuth providers get a login/logout button driven by `TokenStoring`, key providers get a `SecureField`, MiMo gets allowance/used fields. The view takes the auth objects it needs:

```swift
// Sources/OkTally/UI/PreferencesView.swift
import SwiftUI

struct PreferencesView: View {
    let preferencesStore: PreferencesStore
    let tokenStore: TokenStoring
    let browserFlow: BrowserOAuthFlow
    let onImportClaudeLegacy: () -> Bool

    @State private var openRouterAPIKey: String = ""
    @State private var minimaxAPIKey: String = ""
    @State private var openCodeAPIKey: String = ""
    @State private var mimoAllowance: String = ""
    @State private var mimoUsed: String = ""
    @State private var claudeLoggedIn = false
    @State private var codexLoggedIn = false
    @State private var statusMessage: String = ""

    var body: some View {
        Form {
            Section("Claude Code") {
                HStack {
                    Text(claudeLoggedIn ? "Conectado" : "Não conectado")
                        .foregroundStyle(claudeLoggedIn ? .green : .secondary)
                    Spacer()
                    if claudeLoggedIn {
                        Button("Sair") { logout(providerId: "claude", flag: $claudeLoggedIn) }
                    } else {
                        Button("Entrar…") { login(config: ClaudeOAuth.config, flag: $claudeLoggedIn) }
                        Button("Importar login do Claude Code") {
                            if onImportClaudeLegacy() {
                                claudeLoggedIn = true
                                statusMessage = "Login importado."
                            } else {
                                statusMessage = "Nenhum login do Claude Code encontrado."
                            }
                        }
                    }
                }
            }

            Section("Codex") {
                HStack {
                    Text(codexLoggedIn ? "Conectado" : "Não conectado")
                        .foregroundStyle(codexLoggedIn ? .green : .secondary)
                    Spacer()
                    if codexLoggedIn {
                        Button("Sair") { logout(providerId: "codex", flag: $codexLoggedIn) }
                    } else {
                        Button("Entrar…") { login(config: CodexOAuth.config, flag: $codexLoggedIn) }
                    }
                }
            }

            Section("OpenRouter") {
                SecureField("API Key", text: $openRouterAPIKey)
                Button("Salvar") { preferencesStore.openRouterAPIKey = openRouterAPIKey }
            }

            Section("MiniMax") {
                SecureField("API Key", text: $minimaxAPIKey)
                Button("Salvar") { preferencesStore.minimaxAPIKey = minimaxAPIKey }
            }

            Section("OpenCode") {
                SecureField("API Key", text: $openCodeAPIKey)
                Button("Salvar") { preferencesStore.openCodeAPIKey = openCodeAPIKey }
            }

            Section("MiMo (estimativa manual)") {
                TextField("Franquia mensal (Credits)", text: $mimoAllowance)
                TextField("Credits usados", text: $mimoUsed)
                Button("Salvar") {
                    preferencesStore.mimoMonthlyAllowanceCredits = Double(mimoAllowance)
                    preferencesStore.mimoUsedCredits = Double(mimoUsed) ?? 0
                }
            }

            if !statusMessage.isEmpty {
                Text(statusMessage).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            openRouterAPIKey = preferencesStore.openRouterAPIKey ?? ""
            minimaxAPIKey = preferencesStore.minimaxAPIKey ?? ""
            openCodeAPIKey = preferencesStore.openCodeAPIKey ?? ""
            mimoAllowance = preferencesStore.mimoMonthlyAllowanceCredits.map(String.init) ?? ""
            mimoUsed = String(preferencesStore.mimoUsedCredits)
            claudeLoggedIn = tokenStore.load(providerId: "claude") != nil
            codexLoggedIn = tokenStore.load(providerId: "codex") != nil
        }
    }

    private func login(config: OAuthConfig, flag: Binding<Bool>) {
        statusMessage = "Abrindo o navegador…"
        Task {
            do {
                _ = try await browserFlow.login(config: config)
                await MainActor.run {
                    flag.wrappedValue = true
                    statusMessage = "Conectado."
                }
            } catch {
                await MainActor.run { statusMessage = error.localizedDescription }
            }
        }
    }

    private func logout(providerId: String, flag: Binding<Bool>) {
        try? tokenStore.delete(providerId: providerId)
        flag.wrappedValue = false
        statusMessage = "Desconectado."
    }
}
```

Run: `swift build` — expect success.

- [ ] **Step 4: Register every provider in `OkTallyApp.init`**

In `Sources/OkTally/App/OkTallyApp.swift`, build the auth objects once and register all eight providers. Keep the existing storage/scheduler/notification wiring from Plan 1 untouched; only the registry block and the `Settings` scene change:

```swift
        let tokenStore = KeychainTokenStore()
        let oauthManager = OAuthManager(store: tokenStore)
        let browserFlow = BrowserOAuthFlow(manager: oauthManager)

        let claudeProvider = ClaudeUsageProvider(oauthManager: oauthManager, tokenStore: tokenStore)
        claudeProvider.importLegacyCredentialsIfAvailable()

        registry.register(claudeProvider)
        registry.register(CodexUsageProvider(oauthManager: oauthManager, tokenStore: tokenStore))
        registry.register(OpenRouterUsageProvider(apiKeyProvider: { preferencesStore.openRouterAPIKey }))
        registry.register(MiniMaxUsageProvider(
            apiKeyProvider: { preferencesStore.minimaxAPIKey },
            region: { preferencesStore.minimaxRegionRaw == "china" ? .china : .global }
        ))
        registry.register(CursorUsageProvider())
        registry.register(OpenCodeUsageProvider(apiKeyProvider: { preferencesStore.openCodeAPIKey }))
        registry.register(MiMoUsageProvider(
            allowanceProvider: { preferencesStore.mimoMonthlyAllowanceCredits },
            usedCreditsProvider: { preferencesStore.mimoUsedCredits }
        ))
        registry.register(SuperGrokUsageProvider(oauthManager: oauthManager, tokenStore: tokenStore))
```

and the `Settings` scene:

```swift
        Settings {
            PreferencesView(
                preferencesStore: preferencesStore,
                tokenStore: tokenStore,
                browserFlow: browserFlow,
                onImportClaudeLegacy: { claudeProvider.importLegacyCredentialsIfAvailable() }
            )
        }
```

Note: `claudeProvider` is created in `init` but referenced by the `Settings` closure — store it as a `private let claudeProvider` property on `OkTallyApp` (assigned in `init`) so the closure can capture it, mirroring how `preferencesStore` is already held.

If Task 11 took Path B, adjust the `SuperGrokUsageProvider(...)` call to that path's initializer.

- [ ] **Step 5: Run the full suite and build the app bundle**

Run: `swift test` — expect all tests from Tasks 1–11 plus Plan 1 passing.
Run: `./Scripts/build_app.sh` — expect `Built .build/OkTally.app`.

- [ ] **Step 6: Manual end-to-end verification (human required)**

These need a real interactive session with real accounts; a non-interactive agent must report them as deferred rather than attempt workarounds. Never print token values during any of these.

1. `open .build/OkTally.app`, click the menu bar item, open "Preferências…".
2. Claude: click "Importar login do Claude Code" (if the CLI login exists) → card shows real 5h/weekly/weekly-opus bars. Then test "Sair" + "Entrar…" to verify the app's own PKCE flow completes in the browser and the bars come back.
3. Codex: "Entrar…" → browser flow → card shows 5h + weekly bars whose numbers match `codex` CLI's `/status`.
4. OpenRouter / MiniMax / OpenCode: paste keys, "Salvar", "Atualizar agora" → OpenRouter shows balance, MiniMax shows 5h + weekly, OpenCode shows dashed estimated bars.
5. MiMo: enter allowance + used credits → dashed "mensal" bar with `~NN%`.
6. Cursor: with Cursor installed and logged in, card shows credit usage; quit/rename the Cursor support directory → card shows "Cursor não detectado" (not a raw error).
7. Confirm estimated bars are visually distinguishable (dimmed + `~` prefix) from measured ones, and that an alert notification for an estimated window is prefixed "Estimado: ".

- [ ] **Step 7: Commit**

```bash
git add Sources/OkTally Tests/OkTallyTests
git commit -m "feat: wire all Plan 2 providers with per-provider auth preferences"
```

---

## Known Limitations (deferred, disclosed rather than hidden)

- **MiMo and OpenCode are estimates, not measurements.** Verified from source that no live quota API is reachable with a provider key (MiMo's is SSO-cookie-gated with response headers structurally whitelisted; OpenCode has two open upstream feature requests for one). MiMo's usage number is entered by the owner; OpenCode's comes from the local `opencode.db` and therefore misses usage from other devices.
- **MiMo key-issuance browser flow deferred.** The X25519+AES-GCM localhost-callback flow from MiMoCode automates key entry only (no quota data), so it was cut from this plan; the owner pastes the `tp-` key instead.
- **Schema risk on undocumented endpoints.** Codex (`wham/usage`), Cursor (`GetCurrentPeriodUsage`), MiniMax (`token_plan/remains`) and SuperGrok (`GetGrokCreditsConfig`) are all undocumented. Each task has a schema-pin step; Cursor's is a hard gate (BLOCK rather than guess). A silent-wrong-units failure mode exists for percentage fields (a 0–1 fraction read as 0–100 shows a permanently green bar) — assert plausibility when pinning.
- **Anthropic OAuth client values are community-sourced** (Task 6) and must be confirmed before release; a wrong client id fails loudly at login, which is the acceptable failure mode.
- **SuperGrok may ship degraded** (Task 11 Path B) if no usable OAuth client id is extractable.
- **No automatic traffic observation.** OkTally never proxies inference calls, so providers without a usage API can't be measured passively. A local proxy/observer design would change that and is out of scope here.
- **Cursor and OpenCode read app-owned local files** (`state.vscdb`, `opencode.db`) — the two owner-approved exceptions to the no-CLI-dependency rule. Both degrade to a "não detectado" card instead of erroring.
