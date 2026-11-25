import XCTest
import GRDB
@testable import OkTally

final class DevinLocalUsageScannerTests: XCTestCase {
    private func makeFixtureDB() throws -> (String, (String, Int64) throws -> Void) {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db").path
        let db = try DatabaseQueue(path: path)
        try db.write { db in
            try db.execute(sql: "CREATE TABLE message_nodes (row_id INTEGER PRIMARY KEY, created_at INTEGER, chat_message TEXT)")
        }
        return (path, { json, createdAt in
            try db.write { db in
                try db.execute(sql: "INSERT INTO message_nodes (created_at, chat_message) VALUES (?, ?)", arguments: [createdAt, json])
            }
        })
    }

    func test_tokens_usesIndependentInputComponents_notContextTotal() {
        let json = #"{"content":"não importa","metadata":{"metrics":{"input_tokens":629,"output_tokens":310,"cache_read_tokens":30464,"cache_creation_tokens":12,"context_input_tokens":31093}}}"#
        XCTAssertEqual(DevinLocalUsageScanner.tokens(inMessageJSON: json), 31415)
    }

    func test_analytics_aggregatesRowsByLocalDayAndIgnoresOldRows() throws {
        let (path, insert) = try makeFixtureDB()
        let now = Date()
        let today = Int64(now.timeIntervalSince1970)
        let old = Int64(now.addingTimeInterval(-40 * 24 * 3600).timeIntervalSince1970)
        try insert(#"{"metadata":{"metrics":{"input_tokens":10,"output_tokens":5}}}"#, today)
        try insert(#"{"metadata":{"metrics":{"input_tokens":20,"output_tokens":7,"cache_read_tokens":3}}}"#, today)
        try insert(#"{"metadata":{"metrics":{"input_tokens":999,"output_tokens":1}}}"#, old)

        let analytics = DevinLocalUsageScanner(dbPath: path).analytics(windowDays: 30, now: now)

        XCTAssertEqual(analytics?.dailyBuckets.count, 1)
        XCTAssertEqual(analytics?.dailyBuckets.first?.tokens, 45)
    }

    func test_analytics_nilWhenDatabaseMissingOrRowsHaveNoUsage() throws {
        XCTAssertNil(DevinLocalUsageScanner(dbPath: "/nonexistent/sessions.db").analytics())
        let (path, insert) = try makeFixtureDB()
        try insert(#"{"metadata":{"other":true}}"#, Int64(Date().timeIntervalSince1970))
        XCTAssertNil(DevinLocalUsageScanner(dbPath: path).analytics())
    }
}
