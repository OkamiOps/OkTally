// Sources/OkTally/Storage/StorageManaging.swift
import Foundation

protocol StorageManaging {
    func save(_ snapshot: ProviderSnapshot) throws
    func latestSnapshot(providerId: String) throws -> ProviderSnapshot?
    func snapshots(providerId: String, since: Date) throws -> [ProviderSnapshot]
    /// Deletes snapshots strictly older than `cutoff` (retention policy — the history
    /// table grows on every poll forever otherwise).
    func prune(olderThan cutoff: Date) throws
}
