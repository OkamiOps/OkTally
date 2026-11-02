import XCTest
@testable import OkTally

final class FakeOAuthManaging: OAuthManaging {
    var accessTokenToReturn = "tok"
    var errorToThrow: Error?
    /// Últimos argumentos recebidos — para provar que cada conta usa a própria chave.
    private(set) var lastProviderId: String?
    private(set) var lastConfig: OAuthConfig?
    func validAccessToken(providerId: String, config: OAuthConfig) async throws -> String {
        lastProviderId = providerId
        lastConfig = config
        if let errorToThrow { throw errorToThrow }
        return accessTokenToReturn
    }
    func exchangeCode(_ code: String, verifier: String, config: OAuthConfig) async throws -> OAuthToken {
        OAuthToken(accessToken: accessTokenToReturn, refreshToken: nil, expiresAt: nil, extra: [:])
    }
    func exchangeManualCode(code: String, state: String, verifier: String, config: OAuthConfig) async throws -> OAuthToken {
        OAuthToken(accessToken: accessTokenToReturn, refreshToken: nil, expiresAt: nil, extra: [:])
    }
    func refresh(providerId: String, config: OAuthConfig) async throws -> OAuthToken {
        OAuthToken(accessToken: accessTokenToReturn, refreshToken: nil, expiresAt: nil, extra: [:])
    }
}

/// Stored token first, then one refresh. Proves a 401 is not retried with the same token.
final class RefreshOnceOAuth: OAuthManaging {
    private(set) var refreshCount = 0
    func validAccessToken(providerId: String, config: OAuthConfig) async throws -> String { "tok" }
    func exchangeCode(_ code: String, verifier: String, config: OAuthConfig) async throws -> OAuthToken {
        OAuthToken(accessToken: "tok", refreshToken: nil, expiresAt: nil, extra: [:])
    }
    func exchangeManualCode(code: String, state: String, verifier: String, config: OAuthConfig) async throws -> OAuthToken {
        OAuthToken(accessToken: "tok", refreshToken: nil, expiresAt: nil, extra: [:])
    }
    func refresh(providerId: String, config: OAuthConfig) async throws -> OAuthToken {
        refreshCount += 1
        return OAuthToken(accessToken: "refreshed", refreshToken: "rt", expiresAt: nil, extra: [:])
    }
}

final class FakeCodexUsageFetching: CodexUsageFetching {
    var responseToReturn: CodexUsageResponse!
    /// Consumed before `responseToReturn`. Lets one test fail the stored session and then succeed.
    var scripted: [Result<CodexUsageResponse, Error>] = []
    private(set) var lastAccountId: String?
    private(set) var accessTokens: [String] = []
    func fetchUsage(accessToken: String, accountId: String?) async throws -> CodexUsageResponse {
        lastAccountId = accountId
        accessTokens.append(accessToken)
        if !scripted.isEmpty { return try scripted.removeFirst().get() }
        return responseToReturn
    }
}

final class CodexUsageProviderTests: XCTestCase {
    private func makeProvider(
        fetcher: FakeCodexUsageFetching,
        tokenInStore: Bool = true,
        extra: [String: String] = ["account_id": "acc-9"],
        cliAuthFile: URL? = nil,
        oauth: OAuthManaging? = nil
    ) throws -> CodexUsageProvider {
        let store = InMemoryTokenStore()
        if tokenInStore {
            try store.save(OAuthToken(accessToken: "tok", refreshToken: "rt", expiresAt: nil, extra: extra), providerId: "codex")
        }
        return CodexUsageProvider(
            oauthManager: oauth ?? FakeOAuthManaging(),
            tokenStore: store,
            apiClient: fetcher,
            cliAuthFile: cliAuthFile
        )
    }

    func test_fetchSnapshot_labelsWindowsByDuration_andIncludesAdditionalLimits() async throws {
        let fetcher = FakeCodexUsageFetching()
        fetcher.responseToReturn = CodexUsageResponse(
            planType: "pro",
            rateLimit: CodexRateLimit(
                primaryWindow: CodexRateLimitWindow(usedPercent: 69, limitWindowSeconds: 604800, resetAt: Date(timeIntervalSince1970: 1000)),
                secondaryWindow: nil
            ),
            additionalRateLimits: [
                CodexAdditionalLimit(
                    limitName: "GPT-5.3-Codex-Spark",
                    rateLimit: CodexRateLimit(
                        primaryWindow: CodexRateLimitWindow(usedPercent: 9, limitWindowSeconds: 604800, resetAt: Date(timeIntervalSince1970: 2000)),
                        secondaryWindow: nil
                    )
                )
            ]
        )
        let provider = try makeProvider(fetcher: fetcher)

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.providerId, "codex")
        XCTAssertEqual(snapshot.quotas.count, 2)
        // The 604800s general window is labelled "semanal", never "5h".
        let weekly = try XCTUnwrap(snapshot.quotas.first { $0.label == "semanal" })
        XCTAssertEqual(weekly.shape.usedPercent, 69)
        XCTAssertEqual(weekly.renewalCadence, .weekly)
        // The named additional limit surfaces under its feature name.
        let additionalWeekly = try XCTUnwrap(snapshot.quotas.first { $0.label.contains("GPT-5.3-Codex-Spark") })
        XCTAssertEqual(additionalWeekly.shape.usedPercent, 9)
        XCTAssertEqual(additionalWeekly.renewalCadence, .weekly)
        XCTAssertEqual(fetcher.lastAccountId, "acc-9")
        XCTAssertEqual(snapshot.planLabel, "Pro")
    }

    func test_planDisplayName_capitalizesAndStripsPrefix() {
        XCTAssertEqual(CodexUsageProvider.planDisplayName("pro"), "Pro")
        XCTAssertEqual(CodexUsageProvider.planDisplayName("plus"), "Plus")
        XCTAssertEqual(CodexUsageProvider.planDisplayName("chatgpt_team"), "Team")
    }

    func test_fetchSnapshot_fiveHourWindowLabelled5h() async throws {
        let fetcher = FakeCodexUsageFetching()
        fetcher.responseToReturn = CodexUsageResponse(
            planType: nil,
            rateLimit: CodexRateLimit(
                primaryWindow: CodexRateLimitWindow(usedPercent: 5, limitWindowSeconds: 18000, resetAt: nil),
                secondaryWindow: nil
            )
        )
        let provider = try makeProvider(fetcher: fetcher)

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.quotas.count, 1)
        XCTAssertEqual(snapshot.quotas.first?.label, "5h")
        XCTAssertNil(snapshot.quotas.first?.renewalCadence)
    }

    func test_fetchSnapshot_deadStoredSession_usesMatchingCLILogin() async throws {
        let fetcher = FakeCodexUsageFetching()
        fetcher.responseToReturn = CodexUsageResponse(
            planType: "prolite",
            rateLimit: CodexRateLimit(
                primaryWindow: CodexRateLimitWindow(usedPercent: 44, limitWindowSeconds: 604800, resetAt: Date(timeIntervalSince1970: 1_700_000_000)),
                secondaryWindow: nil
            )
        )
        let oauth = FakeOAuthManaging()
        oauth.errorToThrow = OAuthError.refreshFailed(401)
        let file = try writeCLIAuth(email: "person@example.com", accountId: "acc-cli", accessToken: "cli-token")
        defer { try? FileManager.default.removeItem(at: file) }
        let provider = try makeProvider(
            fetcher: fetcher,
            extra: ["account_id": "other-workspace", "email": "person@example.com"],
            cliAuthFile: file,
            oauth: oauth
        )

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.quotas.first?.shape.usedPercent, 44)
        XCTAssertEqual(snapshot.planLabel, "Prolite")
        XCTAssertEqual(fetcher.accessTokens, ["cli-token"])
        XCTAssertEqual(fetcher.lastAccountId, "acc-cli")
    }

    func test_fetchSnapshot_cliLoginForAnotherAccount_doesNotReplaceTheError() async throws {
        let fetcher = FakeCodexUsageFetching()
        let oauth = FakeOAuthManaging()
        oauth.errorToThrow = OAuthError.refreshFailed(401)
        let file = try writeCLIAuth(email: "someone-else@example.com", accountId: "acc-other", accessToken: "cli-token")
        defer { try? FileManager.default.removeItem(at: file) }
        let provider = try makeProvider(
            fetcher: fetcher,
            extra: ["email": "person@example.com"],
            cliAuthFile: file,
            oauth: oauth
        )

        do {
            _ = try await provider.fetchSnapshot()
            XCTFail("expected the stored-session error")
        } catch let error as OAuthError {
            if case .refreshFailed(401) = error {} else { XCTFail("unexpected \(error)") }
        }
        XCTAssertTrue(fetcher.accessTokens.isEmpty)
    }

    func test_fetchSnapshot_unauthorizedStoredToken_refreshesOnce() async throws {
        let fetcher = FakeCodexUsageFetching()
        let live = CodexUsageResponse(
            planType: "pro",
            rateLimit: CodexRateLimit(
                primaryWindow: CodexRateLimitWindow(usedPercent: 44, limitWindowSeconds: 604800, resetAt: nil),
                secondaryWindow: nil
            )
        )
        fetcher.scripted = [.failure(CodexUsageError.badResponse(401)), .success(live)]
        let oauth = RefreshOnceOAuth()
        let provider = try makeProvider(fetcher: fetcher, oauth: oauth)

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.quotas.first?.shape.usedPercent, 44)
        XCTAssertEqual(fetcher.accessTokens, ["tok", "refreshed"])
        XCTAssertEqual(oauth.refreshCount, 1)
    }

    func test_cliAuth_matchesAccountIdOrEmailOnly() throws {
        let cli = CodexCLICredentials(accessToken: "t", accountId: "acc-1", email: "Person@Example.com")
        XCTAssertTrue(CodexCLIAuth.matches(cli, accountId: "acc-1", email: "nope@example.com"))
        XCTAssertTrue(CodexCLIAuth.matches(cli, accountId: "other", email: "person@example.com"))
        XCTAssertFalse(CodexCLIAuth.matches(cli, accountId: "other", email: "nope@example.com"))
        XCTAssertFalse(CodexCLIAuth.matches(cli, accountId: nil, email: nil))
    }

    func test_cliAuth_loadReadsTokenAccountAndEmail() throws {
        let url = try writeCLIAuth(email: "person@example.com", accountId: "acc-cli", accessToken: "cli-token")
        defer { try? FileManager.default.removeItem(at: url) }
        let loaded = try XCTUnwrap(CodexCLIAuth.load(from: url))
        XCTAssertEqual(loaded.accessToken, "cli-token")
        XCTAssertEqual(loaded.accountId, "acc-cli")
        XCTAssertEqual(loaded.email, "person@example.com")
    }

    private func writeCLIAuth(email: String, accountId: String, accessToken: String) throws -> URL {
        let payload: [String: Any] = ["email": email]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let base64 = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let idToken = "e30.\(base64).sig"
        let body: [String: Any] = [
            "auth_mode": "chatgpt",
            "tokens": [
                "access_token": accessToken,
                "account_id": accountId,
                "id_token": idToken,
                "refresh_token": "do-not-use"
            ]
        ]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("codex-auth-\(UUID().uuidString).json")
        try JSONSerialization.data(withJSONObject: body).write(to: url)
        return url
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
        XCTAssertEqual(response.rateLimit?.primaryWindow?.usedPercent, 37.5)
        XCTAssertNotNil(response.rateLimit?.secondaryWindow)
    }
}
