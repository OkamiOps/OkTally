// Sources/OkTally/Storage/SQLiteStorage.swift
import Foundation
import GRDB

private struct SnapshotRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "snapshots"
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
                t.column("fetchedAt", .datetime).notNull()
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
        try dbQueue.read { db in
            let records = try SnapshotRecord
                .filter(Column("providerId") == providerId && Column("fetchedAt") >= since)
                .order(Column("fetchedAt").asc)
                .fetchAll(db)
            return try records.map { try Self.decode($0) }
        }
    }

    private static func decode(_ record: SnapshotRecord) throws -> ProviderSnapshot {
        let quotas = try JSONDecoder().decode([QuotaWindow].self, from: record.quotasJSON)
        let usageDetail = try record.usageDetailJSON.map { try JSONDecoder().decode([UsageDetail].self, from: $0) }
        return ProviderSnapshot(providerId: record.providerId, fetchedAt: record.fetchedAt, quotas: quotas, usageDetail: usageDetail)
    }
}
