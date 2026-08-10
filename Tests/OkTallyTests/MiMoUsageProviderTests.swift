import XCTest
@testable import OkTally

private final class FakeMiMoSessionStore: MiMoSessionStoring {
    var isLoggedIn: Bool = false
}

private final class FakeMiMoUsageFetcher: MiMoUsageFetching {
    var json: String = "{}"
    var errorToThrow: Error?
    func fetchUsageJSON() async throws -> Data {
        if let errorToThrow { throw errorToThrow }
        return Data(json.utf8)
    }
}

final class MiMoUsageProviderTests: XCTestCase {
    private func makeProvider(
        session: FakeMiMoSessionStore = FakeMiMoSessionStore(),
        fetcher: FakeMiMoUsageFetcher = FakeMiMoUsageFetcher(),
        allowance: Double? = nil,
        used: Double = 0,
        now: @escaping () -> Date = Date.init
    ) -> MiMoUsageProvider {
        MiMoUsageProvider(
            sessionStore: session, usageFetcher: fetcher,
            allowanceProvider: { allowance }, usedCreditsProvider: { used }, now: now
        )
    }

    func test_isAuthenticated_falseWhenNoSessionAndNoAllowance() async {
        XCTAssertFalse(await makeProvider().isAuthenticated())
    }

    func test_isAuthenticated_trueWithSession() async {
        let session = FakeMiMoSessionStore(); session.isLoggedIn = true
        XCTAssertTrue(await makeProvider(session: session).isAuthenticated())
    }

    func test_liveSnapshot_mapsPlanAndMonthUsageFromWebSession() async throws {
        let session = FakeMiMoSessionStore(); session.isLoggedIn = true
        let fetcher = FakeMiMoUsageFetcher()
        // Real tokenPlan/usage shape: percent is a fraction.
        fetcher.json = #"{"code":0,"data":{"monthUsage":{"percent":0.0622},"usage":{"percent":0.06}}}"#
        let snapshot = try await makeProvider(session: session, fetcher: fetcher).fetchSnapshot()

        XCTAssertEqual(snapshot.quotas.count, 2)
        XCTAssertEqual(snapshot.quotas.first { $0.label == "mensal" }?.shape.usedPercent ?? -1, 6.22, accuracy: 0.001)
        XCTAssertEqual(snapshot.quotas.first { $0.label == "plano" }?.shape.usedPercent ?? -1, 6.0, accuracy: 0.001)
    }

    func test_expiredSession_401_clearsFlagAndFallsBackToManual() async throws {
        let session = FakeMiMoSessionStore(); session.isLoggedIn = true
        let fetcher = FakeMiMoUsageFetcher()
        fetcher.json = #"{"code":401,"loginUrl":"https://account.xiaomi.com/..."}"#
        let snapshot = try await makeProvider(session: session, fetcher: fetcher, allowance: 500, used: 125).fetchSnapshot()

        XCTAssertFalse(session.isLoggedIn) // cleared
        XCTAssertEqual(snapshot.quotas.count, 1)
        XCTAssertEqual(snapshot.quotas[0].label, "mensal")
        XCTAssertEqual(snapshot.quotas[0].shape.usedPercent, 25)
    }

    func test_noSession_usesManualEstimate() async throws {
        let snapshot = try await makeProvider(allowance: 400, used: 100).fetchSnapshot()
        XCTAssertEqual(snapshot.quotas[0].label, "mensal")
        XCTAssertEqual(snapshot.quotas[0].shape.usedPercent, 25)
    }

    func test_id_and_refreshInterval() {
        let provider = makeProvider()
        XCTAssertEqual(provider.id, "mimo")
        XCTAssertEqual(provider.refreshInterval, 600)
    }
}
