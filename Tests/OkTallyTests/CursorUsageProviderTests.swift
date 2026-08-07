// Tests/OkTallyTests/CursorUsageProviderTests.swift
import XCTest
import GRDB
@testable import OkTally

final class CursorTokenReaderTests: XCTestCase {
    private func makeFixtureDB(withToken token: String?) throws -> String {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".vscdb").path
        let db = try DatabaseQueue(path: path)
        try db.write { db in
            try db.execute(sql: "CREATE TABLE ItemTable (key TEXT PRIMARY KEY, value BLOB)")
            if let token {
                try db.execute(sql: "INSERT INTO ItemTable (key, value) VALUES (?, ?)", arguments: ["cursorAuth/accessToken", token])
            }
        }
        return path
    }

    func test_readAccessToken_returnsStoredValue() throws {
        let path = try makeFixtureDB(withToken: "cursor-token-123")
        XCTAssertEqual(CursorTokenReader(dbPath: path).readAccessToken(), "cursor-token-123")
    }

    func test_readAccessToken_nilWhenRowMissing() throws {
        let path = try makeFixtureDB(withToken: nil)
        XCTAssertNil(CursorTokenReader(dbPath: path).readAccessToken())
    }

    func test_readAccessToken_nilWhenFileMissing() {
        XCTAssertNil(CursorTokenReader(dbPath: "/nonexistent/state.vscdb").readAccessToken())
    }

    func test_readAccessToken_nilWhenTableMissing() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".vscdb").path
        _ = try DatabaseQueue(path: path) // create an empty, valid SQLite file with no ItemTable
        XCTAssertNil(CursorTokenReader(dbPath: path).readAccessToken())
    }

    func test_readAccessToken_readsBlobValue() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".vscdb").path
        let db = try DatabaseQueue(path: path)
        try db.write { db in
            try db.execute(sql: "CREATE TABLE ItemTable (key TEXT PRIMARY KEY, value BLOB)")
            try db.execute(
                sql: "INSERT INTO ItemTable (key, value) VALUES (?, ?)",
                arguments: ["cursorAuth/accessToken", Data("blob-token-456".utf8)]
            )
        }
        XCTAssertEqual(CursorTokenReader(dbPath: path).readAccessToken(), "blob-token-456")
    }
}

final class FakeCursorTokenReading: CursorTokenReading {
    var tokenToReturn: String?
    func readAccessToken() -> String? { tokenToReturn }
}

final class FakeCursorUsageFetching: CursorUsageFetching {
    var responseToReturn: CursorUsageResponse!
    var receivedAccessToken: String?
    func fetchUsage(accessToken: String) async throws -> CursorUsageResponse {
        receivedAccessToken = accessToken
        return responseToReturn
    }
}

final class CursorUsageProviderTests: XCTestCase {
    private func makeResponse(
        totalSpend: Double = 25423,
        includedSpend: Double = 2000,
        bonusSpend: Double = 23423,
        limit: Double = 2000,
        totalPercentUsed: Double = 73.68985507246377
    ) -> CursorUsageResponse {
        CursorUsageResponse(
            billingCycleStart: "1783750752000",
            billingCycleEnd: "1786429152000",
            planUsage: .init(
                totalSpend: totalSpend,
                includedSpend: includedSpend,
                bonusSpend: bonusSpend,
                limit: limit,
                totalPercentUsed: totalPercentUsed
            )
        )
    }

    func test_isAuthenticated_reflectsTokenPresence() async {
        let reader = FakeCursorTokenReading()
        reader.tokenToReturn = "tok"
        let provider = CursorUsageProvider(tokenReader: reader, client: FakeCursorUsageFetching())
        let authenticated = await provider.isAuthenticated()
        XCTAssertTrue(authenticated)

        let unauthenticatedReader = FakeCursorTokenReading()
        let unauthenticatedProvider = CursorUsageProvider(tokenReader: unauthenticatedReader, client: FakeCursorUsageFetching())
        let notAuthenticated = await unauthenticatedProvider.isAuthenticated()
        XCTAssertFalse(notAuthenticated)
    }

    func test_fetchSnapshot_notDetected_whenNoToken() async {
        let reader = FakeCursorTokenReading()
        let provider = CursorUsageProvider(tokenReader: reader, client: FakeCursorUsageFetching())

        do {
            _ = try await provider.fetchSnapshot()
            XCTFail("expected to throw")
        } catch CursorUsageError.notDetected {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func test_fetchSnapshot_computesRemainingCreditBalance() async throws {
        let reader = FakeCursorTokenReading()
        reader.tokenToReturn = "session-token"
        let fetcher = FakeCursorUsageFetching()
        fetcher.responseToReturn = makeResponse()
        let provider = CursorUsageProvider(tokenReader: reader, client: fetcher)

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.providerId, "cursor")
        XCTAssertEqual(fetcher.receivedAccessToken, "session-token")
        XCTAssertEqual(snapshot.quotas.count, 2)
        guard case .creditBalance(let remaining, let currency) = snapshot.quotas.first(where: { $0.label == "balance" })?.shape else {
            return XCTFail("expected creditBalance shape")
        }
        // limit (2000c) - totalSpend (25423c) = -23423c = -$234.23
        XCTAssertEqual(remaining, Decimal(string: "-234.23")!)
        XCTAssertEqual(currency, "USD")
    }

    func test_fetchSnapshot_emitsPercentWindow_fromTotalPercentUsedAndBillingCycleEnd() async throws {
        let reader = FakeCursorTokenReading()
        reader.tokenToReturn = "session-token"
        let fetcher = FakeCursorUsageFetching()
        fetcher.responseToReturn = makeResponse(totalPercentUsed: 73.68985507246377)
        let provider = CursorUsageProvider(tokenReader: reader, client: fetcher)

        let snapshot = try await provider.fetchSnapshot()

        guard case .periodicCounter(let used, let limit, let resetAt) = snapshot.quotas.first(where: { $0.label == "percent" })?.shape else {
            return XCTFail("expected periodicCounter shape")
        }
        XCTAssertEqual(used, 73.68985507246377)
        XCTAssertEqual(limit, 100)
        XCTAssertEqual(resetAt, Date(timeIntervalSince1970: 1786429152))
    }

    func test_apiClient_decodesFixture() async throws {
        let fixtureURL = Bundle.module.url(forResource: "cursor_usage_response", withExtension: "json", subdirectory: "Fixtures")!
        let data = try Data(contentsOf: fixtureURL)
        let url = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")!
        URLProtocolStub.stubResponses[url] = (data, 200)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: config)

        let client = CursorUsageAPIClient(session: session)
        let response = try await client.fetchUsage(accessToken: "session-token")

        XCTAssertEqual(response.billingCycleStart, "1783750752000")
        XCTAssertEqual(response.billingCycleEnd, "1786429152000")
        XCTAssertEqual(response.planUsage.totalSpend, 25423)
        XCTAssertEqual(response.planUsage.includedSpend, 2000)
        XCTAssertEqual(response.planUsage.bonusSpend, 23423)
        XCTAssertEqual(response.planUsage.limit, 2000)
        XCTAssertEqual(response.planUsage.totalPercentUsed, 73.68985507246377)
    }
}
