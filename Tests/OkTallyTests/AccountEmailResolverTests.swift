import XCTest
import GRDB
@testable import OkTally

final class FakeClaudeIdentityFetching: ClaudeIdentityFetching {
    var identity: ClaudeIdentity?
    private(set) var receivedToken: String?
    func fetchIdentity(accessToken: String) async -> ClaudeIdentity? {
        receivedToken = accessToken
        return identity
    }
}

final class AccountEmailResolverTests: XCTestCase {
    static func makeJWT(_ payload: [String: Any]) -> String {
        let header = try! JSONSerialization.data(withJSONObject: ["alg": "none"])
        let body = try! JSONSerialization.data(withJSONObject: payload)
        func b64(_ d: Data) -> String {
            d.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        return "\(b64(header)).\(b64(body)).unsigned"
    }

    private func makeSession() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: cfg)
    }

    private func makeResolver(tokens: InMemoryTokenStore = InMemoryTokenStore(),
                              claude: FakeClaudeIdentityFetching = FakeClaudeIdentityFetching(),
                              cursorEmail: String? = nil,
                              antigravityEmail: String? = nil) -> AccountEmailResolver {
        AccountEmailResolver(tokenStore: tokens, oauthManager: FakeOAuthManaging(), claudeProfile: claude,
                             cursorEmail: { cursorEmail }, antigravityEmail: { antigravityEmail })
    }

    // MARK: - Fontes

    func test_claudeIdentity_readsAccountEmailAndOrg() {
        let json: [String: Any] = ["account": ["email": "Me@Work.com"], "organization": ["uuid": "org-1", "organization_type": "claude_max"]]
        let identity = ClaudeProfileClient.identity(fromProfile: json)
        XCTAssertEqual(identity.email, "Me@Work.com"); XCTAssertEqual(identity.orgUUID, "org-1")
    }

    func test_codexEmail_fromAccessTokenProfileClaim() {
        let jwt = Self.makeJWT(["https://api.openai.com/profile": ["email": "c@x.com"]])
        XCTAssertEqual(AccountEmailResolver.codexEmail(accessToken: jwt, extra: [:]), "c@x.com")
    }

    func test_codexEmail_prefersIdTokenEmailInExtra() {
        XCTAssertEqual(AccountEmailResolver.codexEmail(accessToken: "opaque", extra: ["email": "id@x.com"]), "id@x.com")
        XCTAssertNil(AccountEmailResolver.codexEmail(accessToken: "opaque", extra: [:]))
    }

    func test_oauthManager_storesEmailClaimFromIdToken() async throws {
        let config = OAuthConfig(providerId: "codex#abc123", authorizeURL: URL(string: "https://e.example/a")!,
                                 tokenURL: URL(string: "https://e.example/email-token")!, clientId: "c",
                                 scopes: [], redirectURI: "http://127.0.0.1/cb")
        let body: [String: Any] = ["access_token": "a", "expires_in": 3600, "id_token": Self.makeJWT(["email": "g@x.com"])]
        URLProtocolStub.stubResponses[config.tokenURL] = (try JSONSerialization.data(withJSONObject: body), 200)
        let store = InMemoryTokenStore()
        let token = try await OAuthManager(store: store, session: makeSession()).exchangeCode("code", verifier: "v", config: config)
        XCTAssertEqual(token.extra["email"], "g@x.com")
        XCTAssertEqual(store.load(providerId: "codex#abc123")?.extra["email"], "g@x.com")
    }

    func test_deviceCodeFlow_storesEmailClaimFromIdToken() async throws {
        let config = DeviceCodeOAuthConfig(providerId: "supergrok#abc123",
                                           deviceAuthorizationURL: URL(string: "https://e.example/device")!,
                                           tokenURL: URL(string: "https://e.example/device-email-token")!,
                                           clientId: "c", scopes: [])
        let body: [String: Any] = ["access_token": "a", "id_token": Self.makeJWT(["email": "x@x.ai"])]
        URLProtocolStub.stubResponses[config.tokenURL] = (try JSONSerialization.data(withJSONObject: body), 200)
        let store = InMemoryTokenStore()
        let flow = DeviceCodeFlow(tokenStore: store, session: makeSession(), sleep: { _ in })
        let request = DeviceCodeRequest(info: DeviceCodeInfo(userCode: "U", verificationURL: URL(string: "https://e.example")!, expiresInSeconds: 60),
                                        deviceCode: "d", intervalSeconds: 1)
        let token = try await flow.poll(request, config: config)
        XCTAssertEqual(token.extra["email"], "x@x.ai")
    }

    func test_cursorReader_readsCachedEmail() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".vscdb").path
        let db = try DatabaseQueue(path: path)
        try db.write { db in
            try db.execute(sql: "CREATE TABLE ItemTable (key TEXT PRIMARY KEY, value BLOB)")
            try db.execute(sql: "INSERT INTO ItemTable (key, value) VALUES (?, ?)", arguments: ["cursorAuth/cachedEmail", "dev@cursor.test"])
        }
        XCTAssertEqual(CursorTokenReader(dbPath: path).readEmail(), "dev@cursor.test")
    }

    func test_antigravityReader_readsAuthStatusEmail() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".vscdb").path
        let db = try DatabaseQueue(path: path)
        try db.write { db in
            try db.execute(sql: "CREATE TABLE ItemTable (key TEXT PRIMARY KEY, value BLOB)")
            try db.execute(sql: "INSERT INTO ItemTable (key, value) VALUES (?, ?)",
                           arguments: ["antigravityAuthStatus", #"{"name":"N","email":"ag@g.test","apiKey":"fake"}"#])
        }
        XCTAssertEqual(AntigravityTokenReader(dbPath: path).readEmail(), "ag@g.test")
        XCTAssertNil(AntigravityTokenReader(dbPath: "/nonexistent/state.vscdb").readEmail())
    }

    // MARK: - Resolver por tipo

    /// Decisão do dono: a identidade do Claude é só o e-mail (minúsculo), sem a org.
    func test_resolve_claude_identityKeyIsLowercasedEmailOnly() async throws {
        let tokens = InMemoryTokenStore()
        try tokens.save(OAuthToken(accessToken: "t", refreshToken: nil, expiresAt: nil, extra: [:]), providerId: "claude#abc123")
        let claude = FakeClaudeIdentityFetching()
        claude.identity = ClaudeIdentity(email: "Me@Work.com", orgUUID: "org-1")
        let result = await makeResolver(tokens: tokens, claude: claude).resolve(AccountInstance(id: "claude#abc123", kind: .claude))
        XCTAssertEqual(result.email, "Me@Work.com")
        XCTAssertEqual(result.identityKey, "me@work.com")
    }

    func test_resolve_codex_readsStoredToken() async throws {
        let tokens = InMemoryTokenStore()
        let jwt = Self.makeJWT(["https://api.openai.com/profile": ["email": "C@x.com"]])
        try tokens.save(OAuthToken(accessToken: jwt, refreshToken: nil, expiresAt: nil, extra: [:]), providerId: "codex")
        let result = await makeResolver(tokens: tokens).resolve(AccountInstance(id: "codex", kind: .codex))
        XCTAssertEqual(result.email, "C@x.com")
        XCTAssertEqual(result.identityKey, "c@x.com")
    }

    func test_resolve_superGrok_readsExtraEmail() async throws {
        let tokens = InMemoryTokenStore()
        try tokens.save(OAuthToken(accessToken: "t", refreshToken: nil, expiresAt: nil, extra: ["email": "g@x.ai"]), providerId: "supergrok")
        let result = await makeResolver(tokens: tokens).resolve(AccountInstance(id: "supergrok", kind: .supergrok))
        XCTAssertEqual(result.email, "g@x.ai")
    }

    func test_resolve_legacyIDEs_readTheirLocalEmail() async {
        let resolver = makeResolver(cursorEmail: "c@c.test", antigravityEmail: "a@a.test")
        let cursor = await resolver.resolve(AccountInstance(id: "cursor", kind: .cursor))
        let antigravity = await resolver.resolve(AccountInstance(id: "antigravity", kind: .antigravity))
        XCTAssertEqual(cursor.email, "c@c.test")
        XCTAssertEqual(antigravity.email, "a@a.test")
    }

    func test_resolve_unknownSource_isNil() async {
        let result = await makeResolver().resolve(AccountInstance(id: "mimo", kind: .mimo))
        XCTAssertNil(result.email); XCTAssertNil(result.identityKey)
    }
}
