// Sources/OkTally/Storage/SQLiteStorage.swift
import Foundation
import GRDB

private struct SnapshotRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "snapshots"
    static let databaseDateEncodingStrategy: DatabaseDateEncodingStrategy = .timeIntervalSinceReferenceDate
    static let databaseDateDecodingStrategy: DatabaseDateDecodingStrategy = .timeIntervalSinceReferenceDate
    var id: Int64?
    var providerId: String
    var fetchedAt: Date
    var quotasJSON: Data
    var usageDetailJSON: Data?

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

final class SQLiteStorage: StorageManaging {
    private let dbQueue: DatabaseQueue

    init(path: String) throws {
        dbQueue = try DatabaseQueue(path: path)
        try dbQueue.write { db in
            try db.create(table: "snapshots", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("providerId", .text).notNull().indexed()
                t.column("fetchedAt", .double).notNull().indexed()
                t.column("quotasJSON", .blob).notNull()
                t.column("usageDetailJSON", .blob)
            }
        }
    }

    func save(_ snapshot: ProviderSnapshot) throws {
        let quotasJSON = try JSONEncoder().encode(snapshot.quotas)
        let usageDetailJSON = try snapshot.usageDetail.map { try JSONEncoder().encode($0) }
        var record = SnapshotRecord(
            id: nil,
            providerId: snapshot.providerId,
            fetchedAt: snapshot.fetchedAt,
            quotasJSON: quotasJSON,
            usageDetailJSON: usageDetailJSON
        )
        try dbQueue.write { db in
            try record.insert(db)
        }
    }

    func latestSnapshot(providerId: String) throws -> ProviderSnapshot? {
        try dbQueue.read { db in
            guard let record = try SnapshotRecord
                .filter(Column("providerId") == providerId)
                .order(Column("fetchedAt").desc)
                .fetchOne(db) else { return nil }
            return try Self.decode(record)
        }
    }

    func snapshots(providerId: String, since: Date) throws -> [ProviderSnapshot] {
        // `since` is compared directly against the numeric `fetchedAt` column, so it must be
        // encoded with the same strategy as SnapshotRecord.databaseDateEncodingStrategy
        // (timeIntervalSinceReferenceDate). Date's own DatabaseValueConvertible conformance is
        // NOT strategy-aware (it always uses the deferredToDate string format), so passing `since`
        // directly here would compare a numeric column against a string value.
        let sinceValue = since.timeIntervalSinceReferenceDate
        return try dbQueue.read { db in
            let records = try SnapshotRecord
                .filter(Column("providerId") == providerId && Column("fetchedAt") >= sinceValue)
                .order(Column("fetchedAt").asc)
                .fetchAll(db)
            return try records.map { try Self.decode($0) }
        }
    }

    func prune(olderThan cutoff: Date) throws {
        // Same encoding-strategy caveat as `snapshots(providerId:since:)`: compare the
        // numeric column against the numerically encoded date, not Date's default string.
        let cutoffValue = cutoff.timeIntervalSinceReferenceDate
        _ = try dbQueue.write { db in
            try SnapshotRecord.filter(Column("fetchedAt") < cutoffValue).deleteAll(db)
        }
    }

    private static func decode(_ record: SnapshotRecord) throws -> ProviderSnapshot {
        let quotas = try JSONDecoder().decode([QuotaWindow].self, from: record.quotasJSON)
        let usageDetail = try record.usageDetailJSON.map { try JSONDecoder().decode([UsageDetail].self, from: $0) }
        return ProviderSnapshot(providerId: record.providerId, fetchedAt: record.fetchedAt, quotas: quotas, usageDetail: usageDetail)
    }
}
