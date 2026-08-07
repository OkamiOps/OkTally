// Sources/OkTally/Plugins/OpenCode/OpenCodeLocalEstimator.swift
import Foundation
import GRDB

/// Reads OpenCode's own local SQLite store (`~/.local/share/opencode/opencode.db`) to
/// estimate spend within a recent window. This is a sanctioned exception to the "don't
/// depend on third-party app internals" rule, made necessary because OpenCode ships no
/// public balance/usage API (confirmed by reading `sst/opencode` source and probing eight
/// live `console.opencode.ai` routes — see `docs/superpowers/research/plan2-opencode.md`).
/// Degrades gracefully to `nil` whenever the database can't be read as expected — file
/// missing, `session` table missing, or the database is locked, corrupted, or otherwise
/// unreadable (e.g. `SQLITE_BUSY` because OpenCode's own CLI is writing to it at the same
/// moment). All of those collapse to `nil`; this function never throws or crashes.
///
/// Schema pinned by inspecting the real local DB on 2026-08-07 (`sqlite3 ... ".schema"`,
/// structure only — no message content read). The research report's v1/v2 passes assumed
/// a per-message `data` JSON blob carrying cost; the actual local schema instead accrues
/// cost directly on the `session` row:
///
/// ```
/// CREATE TABLE `session` (
///   `id` text PRIMARY KEY,
///   ...
///   `time_created` integer NOT NULL,   -- epoch milliseconds
///   `time_updated` integer NOT NULL,   -- epoch milliseconds, bumped as the session accrues cost
///   ...
///   `cost` real DEFAULT 0 NOT NULL,    -- cumulative USD cost for the session
///   `tokens_input` integer DEFAULT 0 NOT NULL,
///   `tokens_output` integer DEFAULT 0 NOT NULL,
///   ...
/// );
/// ```
///
/// There is no per-message cost column, so "spend in the last N hours" is approximated as
/// the sum of `cost` across sessions whose `time_updated` (most recent activity) falls
/// inside the window — sessions still being worked on roll into whichever window is
/// currently open, which matches how a human would eyeball "what have I spent recently."
protocol OpenCodeLocalEstimating {
    func spentInCurrentWindow(windowHours: Int, now: Date) -> Decimal?
}

final class OpenCodeLocalEstimator: OpenCodeLocalEstimating {
    private let dbPath: String

    init(dbPath: String = NSHomeDirectory() + "/.local/share/opencode/opencode.db") {
        self.dbPath = dbPath
    }

    func spentInCurrentWindow(windowHours: Int, now: Date) -> Decimal? {
        guard FileManager.default.fileExists(atPath: dbPath) else { return nil }

        var config = Configuration()
        config.readonly = true
        guard let dbQueue = try? DatabaseQueue(path: dbPath, configuration: config) else { return nil }

        let windowStartMs = Int64((now.addingTimeInterval(-Double(windowHours) * 3600)).timeIntervalSince1970 * 1000)

        let result: Decimal?? = try? dbQueue.read { db -> Decimal? in
            guard try db.tableExists("session") else { return nil }
            let total = try Double.fetchOne(
                db,
                sql: "SELECT SUM(cost) FROM session WHERE time_updated >= ?",
                arguments: [windowStartMs]
            ) ?? 0
            return Decimal(total)
        }
        // `result` is nil if the read itself failed (locked/corrupt/unreadable database);
        // `result` is `.some(nil)` if the read succeeded but found no `session` table.
        // Both collapse to `nil` here — only a successful read with a value is returned.
        return result.flatMap { $0 }
    }
}
