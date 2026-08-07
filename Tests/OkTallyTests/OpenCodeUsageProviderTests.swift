// Tests/OkTallyTests/OpenCodeUsageProviderTests.swift
import XCTest
import GRDB
@testable import OkTally

final class OpenCodeLocalEstimatorTests: XCTestCase {
    /// Mirrors the real `session` table schema pinned from `~/.local/share/opencode/opencode.db`
    /// on 2026-08-07 (`sqlite3 ... ".schema"`), trimmed to the columns the estimator reads.
    private func makeFixtureDB() throws -> (path: String, insert: (_ id: String, _ cost: Double, _ timeUpdated: Int64) throws -> Void) {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db").path
        let db = try DatabaseQueue(path: path)
        try db.write { db in
            try db.execute(sql: """
                CREATE TABLE session (
                    id text PRIMARY KEY,
                    time_created integer NOT NULL,
                    time_updated integer NOT NULL,
                    cost real DEFAULT 0 NOT NULL
                )
                """)
        }
        let insert: (String, Double, Int64) throws -> Void = { id, cost, timeUpdated in
            try db.write { txn in
                try txn.execute(
                    sql: "INSERT INTO session (id, time_created, time_updated, cost) VALUES (?, ?, ?, ?)",
                    arguments: [id, timeUpdated, timeUpdated, cost]
                )
            }
        }
        return (path, insert)
    }

    func test_spentInCurrentWindow_sumsOnlyRowsInsideWindow() throws {
        let (path, insert) = try makeFixtureDB()
        let now = Date()
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        let hour: Int64 = 3600 * 1000

        try insert("in-window-1", 1.50, nowMs - 1 * hour)
        try insert("in-window-2", 2.25, nowMs - 4 * hour)
        try insert("out-of-window", 100.0, nowMs - 10 * hour)

        let estimator = OpenCodeLocalEstimator(dbPath: path)
        let spent = try estimator.spentInCurrentWindow(windowHours: 5, now: now)

        XCTAssertEqual(spent, Decimal(3.75))
    }

    func test_spentInCurrentWindow_nilWhenFileMissing() throws {
        let estimator = OpenCodeLocalEstimator(dbPath: "/nonexistent/opencode.db")
        XCTAssertNil(try estimator.spentInCurrentWindow(windowHours: 5, now: Date()))
    }

    func test_spentInCurrentWindow_nilWhenTableMissing() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db").path
        _ = try DatabaseQueue(path: path) // valid SQLite file, no `session` table
        let estimator = OpenCodeLocalEstimator(dbPath: path)
        XCTAssertNil(try estimator.spentInCurrentWindow(windowHours: 5, now: Date()))
    }

    func test_spentInCurrentWindow_zeroWhenNoRowsInWindow() throws {
        let (path, insert) = try makeFixtureDB()
        let now = Date()
        try insert("long-ago", 5.0, Int64(now.timeIntervalSince1970 * 1000) - 30 * 24 * 3600 * 1000)

        let estimator = OpenCodeLocalEstimator(dbPath: path)
        let spent = try estimator.spentInCurrentWindow(windowHours: 5, now: now)

        XCTAssertEqual(spent, Decimal(0))
    }
}

final class OpenCodeRateLimitParserTests: XCTestCase {
    func test_parse_extractsLimitNameAndRetryAfter_forGoUsageLimitError() throws {
        let body = Data("""
            {"_tag":"GoUsageLimitError","metadata":{"workspace":"ws_123","limitName":"weekly"}}
            """.utf8)

        let result = OpenCodeRateLimitParser.parse(statusCode: 429, body: body, retryAfterHeader: "120")

        XCTAssertEqual(result?.limitName, "weekly")
        let resetAt = try XCTUnwrap(result?.resetAt)
        XCTAssertEqual(resetAt.timeIntervalSinceNow, 120, accuracy: 2)
    }

    func test_parse_extractsLimitName_forFreeUsageLimitError() {
        let body = Data("""
            {"_tag":"FreeUsageLimitError","metadata":{"workspace":"ws_123","limitName":"5h"}}
            """.utf8)

        let result = OpenCodeRateLimitParser.parse(statusCode: 429, body: body, retryAfterHeader: nil)

        XCTAssertEqual(result?.limitName, "5h")
        XCTAssertNil(result?.resetAt)
    }

    func test_parse_nilForNon429Status() {
        let body = Data("""
            {"_tag":"GoUsageLimitError","metadata":{"limitName":"weekly"}}
            """.utf8)
        XCTAssertNil(OpenCodeRateLimitParser.parse(statusCode: 200, body: body, retryAfterHeader: "120"))
    }

    func test_parse_nilForUnrecognizedErrorTag() {
        let body = Data("""
            {"_tag":"SomeOtherError","metadata":{"limitName":"weekly"}}
            """.utf8)
        XCTAssertNil(OpenCodeRateLimitParser.parse(statusCode: 429, body: body, retryAfterHeader: nil))
    }

    func test_parse_nilForUnparseableBody() {
        let body = Data("not json".utf8)
        XCTAssertNil(OpenCodeRateLimitParser.parse(statusCode: 429, body: body, retryAfterHeader: nil))
    }
}

final class FakeOpenCodeLocalEstimating: OpenCodeLocalEstimating {
    var spentByWindowHours: [Int: Decimal] = [:]
    var throwError: Error?

    func spentInCurrentWindow(windowHours: Int, now: Date) throws -> Decimal? {
        if let throwError { throw throwError }
        return spentByWindowHours[windowHours]
    }
}

final class OpenCodeUsageProviderTests: XCTestCase {
    private let budgets: [(label: String, hours: Int, budget: Decimal)] = [
        ("5h", 5, 12),
        ("weekly", 168, 30),
        ("monthly", 720, 60)
    ]

    func test_isAuthenticated_reflectsAPIKeyPresence() async {
        let provider = OpenCodeUsageProvider(apiKeyProvider: { "key" }, estimator: FakeOpenCodeLocalEstimating())
        let authenticated = await provider.isAuthenticated()
        XCTAssertTrue(authenticated)

        let unauthenticated = OpenCodeUsageProvider(apiKeyProvider: { nil }, estimator: FakeOpenCodeLocalEstimating())
        let notAuthenticated = await unauthenticated.isAuthenticated()
        XCTAssertFalse(notAuthenticated)
    }

    func test_fetchSnapshot_notDetected_whenNoAPIKey() async {
        let provider = OpenCodeUsageProvider(apiKeyProvider: { nil }, estimator: FakeOpenCodeLocalEstimating())
        do {
            _ = try await provider.fetchSnapshot()
            XCTFail("expected to throw")
        } catch OpenCodeError.notDetected {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func test_fetchSnapshot_notDetected_whenDBAbsent() async {
        let estimator = FakeOpenCodeLocalEstimating()
        // no entries -> nil for every window, simulating a missing DB
        let provider = OpenCodeUsageProvider(apiKeyProvider: { "key" }, estimator: estimator, goWindowBudgets: budgets)
        do {
            _ = try await provider.fetchSnapshot()
            XCTFail("expected to throw")
        } catch OpenCodeError.notDetected {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func test_fetchSnapshot_buildsThreeEstimatedWindows() async throws {
        let estimator = FakeOpenCodeLocalEstimating()
        estimator.spentByWindowHours = [5: 6, 168: 15, 720: 30]
        let provider = OpenCodeUsageProvider(apiKeyProvider: { "key" }, estimator: estimator, goWindowBudgets: budgets)

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.providerId, "opencode")
        XCTAssertEqual(snapshot.quotas.count, 3)

        let byLabel = Dictionary(uniqueKeysWithValues: snapshot.quotas.map { ($0.label, $0.shape) })

        guard case .estimated(let used5h, let limit5h, let basis5h, let reset5h) = byLabel["5h"] else {
            return XCTFail("expected estimated shape for 5h window")
        }
        XCTAssertEqual(used5h, 6)
        XCTAssertEqual(limit5h, 12)
        XCTAssertEqual(basis5h, .localTokenCount)
        XCTAssertNil(reset5h)
        XCTAssertEqual(byLabel["5h"]?.usedPercent, 50)

        guard case .estimated(let usedWeekly, let limitWeekly, _, _) = byLabel["weekly"] else {
            return XCTFail("expected estimated shape for weekly window")
        }
        XCTAssertEqual(usedWeekly, 15)
        XCTAssertEqual(limitWeekly, 30)
        XCTAssertEqual(byLabel["weekly"]?.usedPercent, 50)

        guard case .estimated(let usedMonthly, let limitMonthly, _, _) = byLabel["monthly"] else {
            return XCTFail("expected estimated shape for monthly window")
        }
        XCTAssertEqual(usedMonthly, 30)
        XCTAssertEqual(limitMonthly, 60)
        XCTAssertEqual(byLabel["monthly"]?.usedPercent, 50)
    }

    func test_fetchSnapshot_recordedRateLimit_overridesMatchingWindowOnly() async throws {
        let estimator = FakeOpenCodeLocalEstimating()
        estimator.spentByWindowHours = [5: 6, 168: 15, 720: 30]
        let provider = OpenCodeUsageProvider(apiKeyProvider: { "key" }, estimator: estimator, goWindowBudgets: budgets)

        let resetAt = Date().addingTimeInterval(3600)
        provider.recordRateLimit(limitName: "weekly", resetAt: resetAt)

        let snapshot = try await provider.fetchSnapshot()
        let byLabel = Dictionary(uniqueKeysWithValues: snapshot.quotas.map { ($0.label, $0.shape) })

        guard case .estimated(let used, let limit, let basis, let reset) = byLabel["weekly"] else {
            return XCTFail("expected estimated shape for weekly window")
        }
        XCTAssertEqual(used, 30)
        XCTAssertEqual(limit, 30)
        XCTAssertEqual(basis, .reactiveRateLimit)
        XCTAssertEqual(reset, resetAt)

        // Other windows remain untouched local estimates.
        guard case .estimated(_, _, let basis5h, _) = byLabel["5h"] else {
            return XCTFail("expected estimated shape for 5h window")
        }
        XCTAssertEqual(basis5h, .localTokenCount)
    }

    func test_fetchSnapshot_ignoresRateLimitOncePastResetTime() async throws {
        let estimator = FakeOpenCodeLocalEstimating()
        estimator.spentByWindowHours = [5: 6, 168: 15, 720: 30]
        let provider = OpenCodeUsageProvider(apiKeyProvider: { "key" }, estimator: estimator, goWindowBudgets: budgets)

        provider.recordRateLimit(limitName: "weekly", resetAt: Date().addingTimeInterval(-60))

        let snapshot = try await provider.fetchSnapshot()
        let byLabel = Dictionary(uniqueKeysWithValues: snapshot.quotas.map { ($0.label, $0.shape) })

        guard case .estimated(_, _, let basis, _) = byLabel["weekly"] else {
            return XCTFail("expected estimated shape for weekly window")
        }
        XCTAssertEqual(basis, .localTokenCount)
    }
}
