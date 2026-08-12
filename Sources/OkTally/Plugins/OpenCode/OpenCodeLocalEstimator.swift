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
    /// Per-model token totals inside the window, for cost estimation. `nil` on any DB
    /// problem (same degradation contract as `spentInCurrentWindow`).
    func modelTokens(windowHours: Int, now: Date) -> [UsageDetail]?
    /// Total de tokens por dia (para o painel de análise). `nil` on any DB problem.
    func dailyTokens(windowDays: Int, now: Date) -> [DailyTokens]?
}

extension OpenCodeLocalEstimating {
    /// Defaults so alternative estimators (and older test stubs) without token data keep
    /// compiling — "no data" is always a valid answer.
    func modelTokens(windowHours: Int, now: Date) -> [UsageDetail]? { nil }
    func dailyTokens(windowDays: Int, now: Date) -> [DailyTokens]? { nil }
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

    /// The `model` column (added to the schema after the 2026-08-07 pin; re-verified
    /// 2026-08-12) is a JSON blob `{"id": "...", "providerID": "...", ...}`. Rows whose
    /// blob can't be parsed are skipped rather than failing the whole aggregation.
    func modelTokens(windowHours: Int, now: Date) -> [UsageDetail]? {
        guard FileManager.default.fileExists(atPath: dbPath) else { return nil }

        var config = Configuration()
        config.readonly = true
        guard let dbQueue = try? DatabaseQueue(path: dbPath, configuration: config) else { return nil }

        let windowStartMs = Int64((now.addingTimeInterval(-Double(windowHours) * 3600)).timeIntervalSince1970 * 1000)

        let result: [UsageDetail]?? = try? dbQueue.read { db -> [UsageDetail]? in
            guard try db.tableExists("session"), try db.columns(in: "session").contains(where: { $0.name == "model" }) else {
                return nil
            }
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT model, SUM(tokens_input) AS input, SUM(tokens_output) AS output
                    FROM session
                    WHERE time_updated >= ? AND model IS NOT NULL
                    GROUP BY model
                    """,
                arguments: [windowStartMs]
            )
            var totals: [String: (input: Int, output: Int)] = [:]
            for row in rows {
                guard let modelJSON: String = row["model"],
                      let data = modelJSON.data(using: .utf8),
                      let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let id = parsed["id"] as? String,
                      let providerID = parsed["providerID"] as? String
                else { continue }
                let key = "\(providerID)/\(id)"
                let input: Int = row["input"] ?? 0
                let output: Int = row["output"] ?? 0
                let existing = totals[key] ?? (0, 0)
                totals[key] = (existing.input + input, existing.output + output)
            }
            return totals.map { UsageDetail(modelId: $0.key, promptTokens: $0.value.input, completionTokens: $0.value.output) }
        }
        return result.flatMap { $0 }
    }

    /// Tokens processados por dia local (input + output + reasoning + cache), agrupados
    /// direto no SQLite pela data de `time_updated`.
    func dailyTokens(windowDays: Int, now: Date) -> [DailyTokens]? {
        guard FileManager.default.fileExists(atPath: dbPath) else { return nil }

        var config = Configuration()
        config.readonly = true
        guard let dbQueue = try? DatabaseQueue(path: dbPath, configuration: config) else { return nil }

        let windowStartMs = Int64((now.addingTimeInterval(-Double(windowDays) * 24 * 3600)).timeIntervalSince1970 * 1000)

        let result: [DailyTokens]?? = try? dbQueue.read { db -> [DailyTokens]? in
            guard try db.tableExists("session"), try db.columns(in: "session").contains(where: { $0.name == "tokens_input" }) else {
                return nil
            }
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT date(time_updated / 1000, 'unixepoch', 'localtime') AS day,
                           SUM(tokens_input + tokens_output + tokens_reasoning + tokens_cache_read + tokens_cache_write) AS total
                    FROM session
                    WHERE time_updated >= ?
                    GROUP BY day
                    ORDER BY day ASC
                    """,
                arguments: [windowStartMs]
            )
            return rows.compactMap { row in
                guard let day: String = row["day"] else { return nil }
                let total: Int = row["total"] ?? 0
                return total > 0 ? DailyTokens(day: day, tokens: total) : nil
            }
        }
        return result.flatMap { $0 }
    }
}
