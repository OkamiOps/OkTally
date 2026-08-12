// Tests/OkTallyTests/SQLiteStorageTests.swift
import XCTest
@testable import OkTally

final class SQLiteStorageTests: XCTestCase {
    func test_save_and_latestSnapshot_roundTrips() throws {
        let storage = try SQLiteStorage(path: ":memory:")
        let older = ProviderSnapshot(
            providerId: "claude",
            fetchedAt: Date(timeIntervalSince1970: 1000),
            quotas: [QuotaWindow(label: "5h", shape: .rollingWindow(used: 10, limit: 100, windowStart: Date(timeIntervalSince1970: 0), resetAt: Date(timeIntervalSince1970: 2000)))],
            usageDetail: nil
        )
        let newer = ProviderSnapshot(
            providerId: "claude",
            fetchedAt: Date(timeIntervalSince1970: 2000),
            quotas: [QuotaWindow(label: "5h", shape: .rollingWindow(used: 20, limit: 100, windowStart: Date(timeIntervalSince1970: 0), resetAt: Date(timeIntervalSince1970: 2000)))],
            usageDetail: nil
        )

        try storage.save(older)
        try storage.save(newer)

        let latest = try storage.latestSnapshot(providerId: "claude")
        XCTAssertEqual(latest, newer)
    }

    func test_latestSnapshot_forUnknownProvider_returnsNil() throws {
        let storage = try SQLiteStorage(path: ":memory:")
        XCTAssertNil(try storage.latestSnapshot(providerId: "nope"))
    }

    func test_snapshots_since_returnsAscendingSubset() throws {
        let storage = try SQLiteStorage(path: ":memory:")
        let t0 = ProviderSnapshot(providerId: "claude", fetchedAt: Date(timeIntervalSince1970: 0), quotas: [], usageDetail: nil)
        let t100 = ProviderSnapshot(providerId: "claude", fetchedAt: Date(timeIntervalSince1970: 100), quotas: [], usageDetail: nil)
        let t200 = ProviderSnapshot(providerId: "claude", fetchedAt: Date(timeIntervalSince1970: 200), quotas: [], usageDetail: nil)
        try storage.save(t0)
        try storage.save(t100)
        try storage.save(t200)

        let result = try storage.snapshots(providerId: "claude", since: Date(timeIntervalSince1970: 50))

        XCTAssertEqual(result, [t100, t200])
    }

    func test_save_preservesFullPrecisionFetchedAt() throws {
        let storage = try SQLiteStorage(path: ":memory:")
        let preciseDate = Date(timeIntervalSinceReferenceDate: 12345.123456789)
        let snapshot = ProviderSnapshot(providerId: "claude", fetchedAt: preciseDate, quotas: [], usageDetail: nil)
        try storage.save(snapshot)
        let latest = try storage.latestSnapshot(providerId: "claude")
        XCTAssertEqual(latest?.fetchedAt, preciseDate)
        XCTAssertEqual(latest, snapshot)
    }

    func test_save_withUsageDetail_roundTrips() throws {
        let storage = try SQLiteStorage(path: ":memory:")
        let snapshot = ProviderSnapshot(
            providerId: "openrouter",
            fetchedAt: Date(timeIntervalSince1970: 500),
            quotas: [QuotaWindow(label: "balance", shape: .creditBalance(remaining: 12.5, currency: "USD"))],
            usageDetail: [UsageDetail(modelId: "m1", promptTokens: 10, completionTokens: 5)]
        )
        try storage.save(snapshot)
        let latest = try storage.latestSnapshot(providerId: "openrouter")
        XCTAssertEqual(latest, snapshot)
    }

    func test_planLabel_roundTrips_andOldRowsWithoutItDecode() throws {
        let storage = try SQLiteStorage(path: ":memory:")
        let snapshot = ProviderSnapshot(
            providerId: "copilot",
            fetchedAt: Date(timeIntervalSince1970: 100),
            quotas: [],
            usageDetail: nil,
            planLabel: "Pro"
        )
        try storage.save(snapshot)
        XCTAssertEqual(try storage.latestSnapshot(providerId: "copilot")?.planLabel, "Pro")

        // Linhas antigas não têm a chave — o decode não pode falhar.
        let legacyJSON = Data(#"{"providerId":"claude","fetchedAt":0,"quotas":[]}"#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let legacy = try decoder.decode(ProviderSnapshot.self, from: legacyJSON)
        XCTAssertNil(legacy.planLabel)
    }

    func test_prune_deletesOnlySnapshotsOlderThanCutoff() throws {
        let storage = try SQLiteStorage(path: ":memory:")
        let old = ProviderSnapshot(providerId: "claude", fetchedAt: Date(timeIntervalSince1970: 100), quotas: [], usageDetail: nil)
        let recent = ProviderSnapshot(providerId: "claude", fetchedAt: Date(timeIntervalSince1970: 5000), quotas: [], usageDetail: nil)
        let otherProviderOld = ProviderSnapshot(providerId: "codex", fetchedAt: Date(timeIntervalSince1970: 200), quotas: [], usageDetail: nil)
        try storage.save(old)
        try storage.save(recent)
        try storage.save(otherProviderOld)

        try storage.prune(olderThan: Date(timeIntervalSince1970: 1000))

        XCTAssertEqual(try storage.snapshots(providerId: "claude", since: .distantPast), [recent])
        XCTAssertEqual(try storage.snapshots(providerId: "codex", since: .distantPast), [])
    }

    func test_prune_atExactCutoff_keepsSnapshotAtCutoff() throws {
        let storage = try SQLiteStorage(path: ":memory:")
        let cutoff = Date(timeIntervalSince1970: 1000)
        let atCutoff = ProviderSnapshot(providerId: "claude", fetchedAt: cutoff, quotas: [], usageDetail: nil)
        try storage.save(atCutoff)

        try storage.prune(olderThan: cutoff)

        XCTAssertEqual(try storage.snapshots(providerId: "claude", since: .distantPast), [atCutoff])
    }
}
