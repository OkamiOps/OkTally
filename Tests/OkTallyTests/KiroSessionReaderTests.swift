import XCTest
import GRDB
@testable import OkTally

final class KiroSessionReaderTests: XCTestCase {
    private let profileArn = "arn:aws:codewhisperer:us-east-1:123456789012:profile/work-profile"

    private func temporaryDB() -> String {
        NSTemporaryDirectory() + "oktally-kiro-\(UUID().uuidString).sqlite3"
    }

    private func makeDatabase(expired: Bool = false, includeRegistration: Bool = true, expiry: Any? = nil) throws -> String {
        let path = temporaryDB()
        let db = try DatabaseQueue(path: path)
        try db.write { db in
            try db.execute(sql: "CREATE TABLE auth_kv (key TEXT PRIMARY KEY, value TEXT)")
            try db.execute(sql: "CREATE TABLE state (key TEXT PRIMARY KEY, value BLOB)")
            let token: [String: Any] = [
                "access_token": expired ? "expired-access" : "copied-access",
                "refresh_token": "copied-refresh",
                "expires_at": expiry ?? (expired ? 1 : 2_000_000_000),
                "region": "us-east-1",
                "start_url": "https://d-123.awsapps.com/start"
            ]
            try db.execute(sql: "INSERT INTO auth_kv (key, value) VALUES (?, ?)", arguments: [
                "kirocli:odic:token",
                String(decoding: try JSONSerialization.data(withJSONObject: token), as: UTF8.self)
            ])
            if includeRegistration {
                let registration: [String: Any] = [
                    "client_id": "test-client",
                    "client_secret": "redacted-test-secret",
                    "client_secret_expires_at": 2_000_000_000,
                    "region": "us-east-1"
                ]
                try db.execute(sql: "INSERT INTO auth_kv (key, value) VALUES (?, ?)", arguments: [
                    "kirocli:odic:device-registration",
                    String(decoding: try JSONSerialization.data(withJSONObject: registration), as: UTF8.self)
                ])
            }
            let profile: [String: Any] = ["arn": profileArn, "profile_name": "Work"]
            try db.execute(sql: "INSERT INTO state (key, value) VALUES (?, ?)", arguments: [
                "api.codewhisperer.profile",
                try JSONSerialization.data(withJSONObject: profile)
            ])
        }
        return path
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    override func tearDown() {
        URLProtocolStub.stubResponses = [:]
        URLProtocolStub.stubQueues = [:]
        URLProtocolStub.resetRequestCounts()
        super.tearDown()
    }

    func test_readsCompleteCLIBundleReadOnly() throws {
        let path = try makeDatabase()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let session = try KiroSessionReader(dbPath: path).readCLISession()

        XCTAssertEqual(session.accessToken, "copied-access")
        XCTAssertEqual(session.refreshToken, "copied-refresh")
        XCTAssertEqual(session.oidcRegion, "us-east-1")
        XCTAssertEqual(session.profileArn, profileArn)
        XCTAssertEqual(session.profileName, "Work")
        XCTAssertEqual(session.clientId, "test-client")
    }

    func test_readsActualCLIFractionalTimestampAsExpired() throws {
        let path = try makeDatabase(expired: true, expiry: "2026-10-09T01:27:47.304255Z")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let copied = try KiroSessionReader(dbPath: path).readCLISession()
        let expiry = try XCTUnwrap(copied.expiresAt)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let base = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 1, minute: 27, second: 47)))
        // Foundation's ISO8601 formatter preserves millisecond precision.
        XCTAssertEqual(expiry.timeIntervalSince1970, base.timeIntervalSince1970 + 0.304255, accuracy: 0.001)
        XCTAssertLessThan(expiry, Date())
    }

    func test_importerRetriesInvalidToken403ExactlyOnce() async throws {
        let path = try makeDatabase()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let oidcURL = URL(string: "https://oidc.us-east-1.amazonaws.com/token")!
        let usageURL = URL(string: "https://management.us-east-1.kiro.dev/Get-Usage-Limits?profileArn=arn:aws:codewhisperer:us-east-1:123456789012:profile/work-profile&origin=KIRO_CLI&isEmailRequired=true")!
        URLProtocolStub.stubResponses[oidcURL] = (Data(#"{"accessToken":"fresh-access","expiresIn":3600}"#.utf8), 200)
        URLProtocolStub.stubQueues[usageURL] = [
            (Data(#"{"message":"Invalid token","reason":null}"#.utf8), 403),
            (Data(#"{"usageBreakdownList":[{"displayName":"Credits","currentUsageWithPrecision":1.25,"usageLimitWithPrecision":10,"nextDateReset":1798761600}],"userInfo":{"userId":"user-1","email":"me@example.test"}}"#.utf8), 200)
        ]
        let importer = KiroSessionImporter(reader: KiroSessionReader(dbPath: path), session: makeSession())
        let imported = try await importer.importSession(source: .cli)
        XCTAssertEqual(imported.accessToken, "fresh-access")
        XCTAssertEqual(imported.extra["userId"], "user-1")
        XCTAssertEqual(URLProtocolStub.requestCount(for: oidcURL), 1)
        XCTAssertEqual(URLProtocolStub.requestCount(for: usageURL), 2)
        XCTAssertEqual(try KiroSessionReader(dbPath: path).readCLISession().accessToken, "copied-access")
    }

    func test_missingOIDCRegistrationExplainsUnsupportedSocialOrBuilderImport() throws {
        let path = try makeDatabase(includeRegistration: false)
        defer { try? FileManager.default.removeItem(atPath: path) }

        XCTAssertThrowsError(try KiroSessionReader(dbPath: path).readCLISession()) {
            XCTAssertEqual(($0 as? KiroSessionReaderError)?.errorDescription,
                           KiroSessionReaderError.unsupportedAuthentication.errorDescription)
        }
    }

    func test_importerRefreshesOnlyCopiedExpiredSessionAndLeavesSQLiteUntouched() async throws {
        let path = try makeDatabase(expired: true, expiry: "2026-10-09T01:27:47.304255Z")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let oidcURL = URL(string: "https://oidc.us-east-1.amazonaws.com/token")!
        let usageURL = URL(string: "https://management.us-east-1.kiro.dev/Get-Usage-Limits?profileArn=arn:aws:codewhisperer:us-east-1:123456789012:profile/work-profile&origin=KIRO_CLI&isEmailRequired=true")!
        URLProtocolStub.stubResponses[oidcURL] = (Data(#"{"accessToken":"fresh-access","refreshToken":"rotated-refresh","expiresIn":3600}"#.utf8), 200)
        URLProtocolStub.stubResponses[usageURL] = (Data(#"{"usageBreakdownList":[{"displayName":"Credits","currentUsageWithPrecision":1.25,"usageLimitWithPrecision":10,"nextDateReset":1798761600}],"userInfo":{"email":"me@example.test"}}"#.utf8), 200)

        let importer = KiroSessionImporter(reader: KiroSessionReader(dbPath: path), session: makeSession())
        let token = try await importer.importSession(source: .cli)

        XCTAssertEqual(token.accessToken, "fresh-access")
        XCTAssertEqual(token.refreshToken, "rotated-refresh")
        XCTAssertEqual(token.extra["email"], "me@example.test")
        XCTAssertEqual(token.extra["profileArn"], profileArn)
        XCTAssertEqual(token.extra["profileName"], "Work")
        XCTAssertEqual(token.extra["authMethod"], "oidc")
        XCTAssertEqual(URLProtocolStub.lastAuthorization(for: usageURL), "Bearer fresh-access")

        let original = try KiroSessionReader(dbPath: path).readCLISession()
        XCTAssertEqual(original.accessToken, "expired-access")
        XCTAssertEqual(original.refreshToken, "copied-refresh")
    }

    func test_ideImportDirectsUserToCLI() async {
        let importer = KiroSessionImporter(reader: KiroSessionReader(dbPath: "/not-present"))
        do {
            _ = try await importer.importSession(source: .ide)
            XCTFail("expected IDE import to be rejected")
        } catch {
            XCTAssertEqual((error as? KiroSessionImportError)?.errorDescription,
                           KiroSessionImportError.ideImportUnsupported.errorDescription)
        }
    }
}
