// Tests/OkTallyTests/CopilotUsageProviderTests.swift
import XCTest
@testable import OkTally

final class CopilotTokenReaderTests: XCTestCase {
    private func makeTempHome() throws -> String {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        return home
    }

    func test_firstToken_readsFromCopilotAppsJSON() throws {
        let home = try makeTempHome()
        let dir = home + "/.config/github-copilot"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let json = #"{"github.com:Iv1.abc123": {"user": "octocat", "oauth_token": "gho_apps_token"}}"#
        try json.write(toFile: dir + "/apps.json", atomically: true, encoding: .utf8)

        let reader = CopilotTokenReader(homeDirectory: home)
        XCTAssertEqual(reader.firstToken(), "gho_apps_token")
    }

    func test_firstToken_readsFromGhHostsYml() throws {
        let home = try makeTempHome()
        let dir = home + "/.config/gh"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let yml = """
        github.com:
            users:
                octocat:
            oauth_token: gho_gh_cli_token
            git_protocol: https
        """
        try yml.write(toFile: dir + "/hosts.yml", atomically: true, encoding: .utf8)

        let reader = CopilotTokenReader(homeDirectory: home)
        XCTAssertEqual(reader.firstToken(), "gho_gh_cli_token")
    }

    func test_firstToken_prefersCopilotFilesOverGhCli() throws {
        let home = try makeTempHome()
        let copilotDir = home + "/.config/github-copilot"
        let ghDir = home + "/.config/gh"
        try FileManager.default.createDirectory(atPath: copilotDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: ghDir, withIntermediateDirectories: true)
        try #"{"github.com": {"oauth_token": "gho_copilot"}}"#
            .write(toFile: copilotDir + "/hosts.json", atomically: true, encoding: .utf8)
        try "github.com:\n    oauth_token: gho_gh\n".write(toFile: ghDir + "/hosts.yml", atomically: true, encoding: .utf8)

        let reader = CopilotTokenReader(homeDirectory: home)
        XCTAssertEqual(reader.firstToken(), "gho_copilot")
    }

    func test_firstToken_nilWhenNothingInstalled() throws {
        let home = try makeTempHome()
        let reader = CopilotTokenReader(homeDirectory: home)
        XCTAssertNil(reader.firstToken())
    }
}

private struct FixedTokenReader: CopilotTokenReading {
    let token: String?
    func firstToken() -> String? { token }
}

final class CopilotUsageProviderTests: XCTestCase {
    private let entitlementURL = URL(string: "https://api.github.com/copilot_internal/user")!

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: config)
    }

    override func tearDown() {
        URLProtocolStub.stubResponses = [:]
        URLProtocolStub.resetRequestCounts()
        super.tearDown()
    }

    func test_isAuthenticated_reflectsTokenPresence() async {
        let with = CopilotUsageProvider(tokenReader: FixedTokenReader(token: "t"), session: makeSession())
        let without = CopilotUsageProvider(tokenReader: FixedTokenReader(token: nil), session: makeSession())
        let a = await with.isAuthenticated()
        let b = await without.isAuthenticated()
        XCTAssertTrue(a)
        XCTAssertFalse(b)
    }

    func test_fetchSnapshot_mapsQuotaSnapshotsToWindows() async throws {
        let json = """
        {
            "access_type_sku": "copilot_pro_monthly",
            "copilot_plan": "pro",
            "quota_reset_date_utc": "2026-09-01T00:00:00Z",
            "quota_snapshots": {
                "chat": {"unlimited": true, "percent_remaining": 100},
                "completions": {"unlimited": true},
                "premium_interactions": {"entitlement": 300, "remaining": 30, "percent_remaining": 10.0, "unlimited": false}
            }
        }
        """
        URLProtocolStub.stubResponses = [entitlementURL: (Data(json.utf8), 200)]
        let provider = CopilotUsageProvider(tokenReader: FixedTokenReader(token: "t"), session: makeSession())

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.providerId, "copilot")
        // Janelas unlimited não geram cota; só a premium aparece.
        XCTAssertEqual(snapshot.quotas.count, 1)
        let window = try XCTUnwrap(snapshot.quotas.first)
        XCTAssertEqual(window.label, "premium")
        guard case .periodicCounter(let used, let limit, let resetAt) = window.shape else {
            return XCTFail("expected periodicCounter, got \(window.shape)")
        }
        XCTAssertEqual(used, 90, accuracy: 0.0001)
        XCTAssertEqual(limit, 100)
        XCTAssertEqual(resetAt, ISO8601DateFormatter().date(from: "2026-09-01T00:00:00Z"))
    }

    func test_fetchSnapshot_freePlan_usesLimitedUserQuotas() async throws {
        let json = """
        {
            "access_type_sku": "free_limited_copilot",
            "copilot_plan": "individual",
            "limited_user_reset_date": "2026-09-05",
            "limited_user_quotas": {"chat": 40, "completions": 1000},
            "monthly_quotas": {"chat": 50, "completions": 2000}
        }
        """
        URLProtocolStub.stubResponses = [entitlementURL: (Data(json.utf8), 200)]
        let provider = CopilotUsageProvider(tokenReader: FixedTokenReader(token: "t"), session: makeSession())

        let snapshot = try await provider.fetchSnapshot()

        let byLabel = Dictionary(uniqueKeysWithValues: snapshot.quotas.map { ($0.label, $0.shape) })
        guard case .periodicCounter(let chatUsed, let chatLimit, _) = byLabel["chat"] else {
            return XCTFail("expected chat window")
        }
        XCTAssertEqual(chatUsed, 10)
        XCTAssertEqual(chatLimit, 50)
        guard case .periodicCounter(let compUsed, let compLimit, _) = byLabel["completions"] else {
            return XCTFail("expected completions window")
        }
        XCTAssertEqual(compUsed, 1000)
        XCTAssertEqual(compLimit, 2000)
    }

    func test_fetchSnapshot_401_throwsTokenRejected() async {
        URLProtocolStub.stubResponses = [entitlementURL: (Data("{}".utf8), 401)]
        let provider = CopilotUsageProvider(tokenReader: FixedTokenReader(token: "t"), session: makeSession())
        do {
            _ = try await provider.fetchSnapshot()
            XCTFail("expected to throw")
        } catch CopilotError.tokenRejected {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func test_fetchSnapshot_noToken_throwsNotDetected() async {
        let provider = CopilotUsageProvider(tokenReader: FixedTokenReader(token: nil), session: makeSession())
        do {
            _ = try await provider.fetchSnapshot()
            XCTFail("expected to throw")
        } catch CopilotError.notDetected {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func test_classification_notDetectedIsNotConfigured_tokenRejectedIsReauth() {
        XCTAssertEqual(ProviderErrorPresentation.classify(CopilotError.notDetected), .notConfigured)
        XCTAssertEqual(ProviderErrorPresentation.classify(CopilotError.tokenRejected), .needsReauth)
        XCTAssertEqual(ProviderErrorPresentation.classify(CopilotError.badResponse(500)), .error)
    }
}
