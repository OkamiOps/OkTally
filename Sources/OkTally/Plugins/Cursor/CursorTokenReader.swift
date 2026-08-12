// Sources/OkTally/Plugins/Cursor/CursorTokenReader.swift
import Foundation
import GRDB

protocol CursorTokenReading {
    func readAccessToken() -> String?
    /// Plano da conta ("pro", "free", "pro_student"…) que o app Cursor cacheia no mesmo
    /// banco. `nil` quando ausente — o badge só não aparece.
    func readMembershipType() -> String?
}

extension CursorTokenReading {
    func readMembershipType() -> String? { nil }
}

/// Reads the Cursor desktop app's own session token from its local VS Code-style
/// `state.vscdb` SQLite store. This is a sanctioned exception to the "don't depend on
/// third-party app internals" rule: without Cursor installed and logged in there is no
/// Cursor usage to measure in the first place, so this plugin degrades to a graceful
/// "not detected" state whenever the file, table, or row is absent — never a crash or
/// raw error.
final class CursorTokenReader: CursorTokenReading {
    private let dbPath: String

    init(dbPath: String = NSHomeDirectory() + "/Library/Application Support/Cursor/User/globalStorage/state.vscdb") {
        self.dbPath = dbPath
    }

    func readAccessToken() -> String? {
        readItem(key: "cursorAuth/accessToken")
    }

    func readMembershipType() -> String? {
        readItem(key: "cursorAuth/stripeMembershipType")
    }

    private func readItem(key: String) -> String? {
        guard FileManager.default.fileExists(atPath: dbPath) else { return nil }

        var config = Configuration()
        config.readonly = true

        guard let dbQueue = try? DatabaseQueue(path: dbPath, configuration: config) else { return nil }

        return try? dbQueue.read { db -> String? in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT value FROM ItemTable WHERE key = ?",
                arguments: [key]
            ) else { return nil }

            if let string: String = row["value"] {
                return string
            }
            if let data: Data = row["value"] {
                return String(data: data, encoding: .utf8)
            }
            return nil
        }
    }
}
