import XCTest
@testable import OkTally

final class MiMoUsageProviderTests: XCTestCase {
    func test_isAuthenticated_falseWhenAllowanceNotConfigured() async {
        let provider = MiMoUsageProvider(
            allowanceProvider: { nil },
            usedCreditsProvider: { 0 }
        )

        let authenticated = await provider.isAuthenticated()

        XCTAssertFalse(authenticated)
    }

    func test_isAuthenticated_trueWhenAllowanceConfigured() async {
        let provider = MiMoUsageProvider(
            allowanceProvider: { 500 },
            usedCreditsProvider: { 0 }
        )

        let authenticated = await provider.isAuthenticated()

        XCTAssertTrue(authenticated)
    }

    func test_fetchSnapshot_returnsSingleEstimatedMensalWindow() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 7))!

        let provider = MiMoUsageProvider(
            allowanceProvider: { 500 },
            usedCreditsProvider: { 125 },
            now: { now }
        )

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.providerId, "mimo")
        XCTAssertEqual(snapshot.quotas.count, 1)
        let window = snapshot.quotas[0]
        XCTAssertEqual(window.label, "mensal")
        XCTAssertEqual(window.shape, .estimated(used: 125, limit: 500, basis: .localTokenCount, resetAt: nil))
    }

    /// MiMo's research (docs/superpowers/research/plan2-mimo.md) confirms a monthly
    /// reset but not which day it falls on — it could be the calendar month start or
    /// the subscription anniversary. Since this is an estimated provider, we must not
    /// assert a specific reset date we haven't verified.
    func test_fetchSnapshot_hasNoResetAt_sinceMiMoResetDayIsUnverified() async throws {
        let provider = MiMoUsageProvider(
            allowanceProvider: { 500 },
            usedCreditsProvider: { 0 }
        )

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertNil(snapshot.quotas[0].shape.resetAt)
    }

    func test_fetchSnapshot_usedPercentIsComputedWhenAllowanceSet() async throws {
        let provider = MiMoUsageProvider(
            allowanceProvider: { 400 },
            usedCreditsProvider: { 100 }
        )

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertNotNil(snapshot.quotas[0].shape.usedPercent)
        XCTAssertEqual(snapshot.quotas[0].shape.usedPercent, 25)
    }

    func test_fetchSnapshot_worksWithoutAllowanceConfigured() async throws {
        let provider = MiMoUsageProvider(
            allowanceProvider: { nil },
            usedCreditsProvider: { 0 }
        )

        let snapshot = try await provider.fetchSnapshot()

        guard case .estimated(let used, let limit, let basis, _) = snapshot.quotas[0].shape else {
            return XCTFail("expected .estimated shape")
        }
        XCTAssertEqual(used, 0)
        XCTAssertNil(limit)
        XCTAssertEqual(basis, .localTokenCount)
        XCTAssertNil(snapshot.quotas[0].shape.usedPercent)
    }

    func test_id_and_refreshInterval() {
        let provider = MiMoUsageProvider(
            allowanceProvider: { nil },
            usedCreditsProvider: { 0 }
        )

        XCTAssertEqual(provider.id, "mimo")
        XCTAssertEqual(provider.refreshInterval, 3600)
    }
}
