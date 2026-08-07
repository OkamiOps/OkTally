import XCTest
@testable import OkTally

final class FakeClaudeUsageFetching: ClaudeUsageFetching {
    var responseToReturn: ClaudeUsageResponse!
    func fetchUsage(accessToken: String) async throws -> ClaudeUsageResponse { responseToReturn }
}

final class ClaudeUsageProviderTests: XCTestCase {
    func test_fetchSnapshot_mapsThreeWindows() async throws {
        let credentialProvider = ClaudeCredentialProvider(
            keychainReader: FakeCredentialStoreReadingWithToken(token: "tok"),
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("unused.json")
        )
        let fetcher = FakeClaudeUsageFetching()
        fetcher.responseToReturn = ClaudeUsageResponse(
            fiveHour: ClaudeUsageWindow(utilization: 42.5, resetsAt: Date(timeIntervalSince1970: 2_000_000)),
            sevenDay: ClaudeUsageWindow(utilization: 61.0, resetsAt: Date(timeIntervalSince1970: 2_500_000)),
            sevenDayOpus: ClaudeUsageWindow(utilization: 15.0, resetsAt: Date(timeIntervalSince1970: 2_500_000))
        )
        let provider = ClaudeUsageProvider(credentialProvider: credentialProvider, apiClient: fetcher)

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.providerId, "claude")
        XCTAssertEqual(snapshot.quotas.count, 3)
        XCTAssertEqual(snapshot.quotas.first { $0.label == "5h" }?.shape.usedPercent, 42.5)
        XCTAssertEqual(snapshot.quotas.first { $0.label == "weekly" }?.shape.usedPercent, 61.0)
        XCTAssertEqual(snapshot.quotas.first { $0.label == "weekly-opus" }?.shape.usedPercent, 15.0)
    }

    func test_fetchSnapshot_withoutOpusWindow_returnsTwoWindows() async throws {
        let credentialProvider = ClaudeCredentialProvider(
            keychainReader: FakeCredentialStoreReadingWithToken(token: "tok"),
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("unused.json")
        )
        let fetcher = FakeClaudeUsageFetching()
        fetcher.responseToReturn = ClaudeUsageResponse(
            fiveHour: ClaudeUsageWindow(utilization: 10, resetsAt: Date()),
            sevenDay: ClaudeUsageWindow(utilization: 20, resetsAt: Date()),
            sevenDayOpus: nil
        )
        let provider = ClaudeUsageProvider(credentialProvider: credentialProvider, apiClient: fetcher)

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.quotas.count, 2)
    }

    func test_isAuthenticated_falseWhenNoCredentials() async {
        let credentialProvider = ClaudeCredentialProvider(
            keychainReader: FakeCredentialStoreReading(),
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        let provider = ClaudeUsageProvider(credentialProvider: credentialProvider, apiClient: FakeClaudeUsageFetching())

        let isAuthenticated = await provider.isAuthenticated()

        XCTAssertFalse(isAuthenticated)
    }

    func test_apiClient_decodesFixture() async throws {
        let fixtureURL = Bundle.module.url(forResource: "claude_usage_response", withExtension: "json", subdirectory: "Fixtures")!
        let data = try Data(contentsOf: fixtureURL)
        URLProtocolStub.stubResponses[URL(string: "https://api.anthropic.com/api/oauth/usage")!] = (data, 200)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: config)

        let client = ClaudeUsageAPIClient(session: session)
        let response = try await client.fetchUsage(accessToken: "tok")

        XCTAssertEqual(response.fiveHour.utilization, 42.5)
        XCTAssertEqual(response.sevenDayOpus?.utilization, 15.0)
    }
}

private final class FakeCredentialStoreReadingWithToken: CredentialStoreReading {
    let token: String
    init(token: String) { self.token = token }
    func readClaudeCredentialsJSON() -> Data? {
        try? JSONEncoder().encode(["accessToken": token])
    }
}
