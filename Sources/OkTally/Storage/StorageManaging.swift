// Sources/OkTally/Storage/StorageManaging.swift
import Foundation

protocol StorageManaging {
    func save(_ snapshot: ProviderSnapshot) throws
    func latestSnapshot(providerId: String) throws -> ProviderSnapshot?
    func snapshots(providerId: String, since: Date) throws -> [ProviderSnapshot]
}
