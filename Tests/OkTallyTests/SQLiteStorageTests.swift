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
}
