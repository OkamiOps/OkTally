import XCTest
@testable import OkTally

final class DevinUsageProviderTests: XCTestCase {
    private final class FixedCredentials: DevinCredentialReading {
        let credentials: DevinCredentials?
        init(_ credentials: DevinCredentials?) { self.credentials = credentials }
        func readCredentials() -> DevinCredentials? { credentials }
    }

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: config)
    }

    private let responseJSON = """
    {
      "userStatus": {
        "name": "Marcos Vinicius",
        "email": "devin@example.com",
        "planStatus": {
          "planInfo": {
            "planName": "Max",
            "billingStrategy": "BILLING_STRATEGY_QUOTA",
            "hideDailyQuota": true
          },
          "planStart": "2026-11-21T03:41:22Z",
          "planEnd": "2026-12-21T03:41:22Z",
          "dailyQuotaRemainingPercent": 100,
          "weeklyQuotaRemainingPercent": 52,
          "dailyQuotaResetAtUnix": "1795680000",
          "weeklyQuotaResetAtUnix": "1795939200"
        }
      }
    }
    """

    func test_credentialReader_readsDevinCredentialsToml() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        try """
        # comentário
        windsurf_api_key = "test-key"
        api_server_url = "https://server.example.com"
        """.write(toFile: path, atomically: true, encoding: .utf8)

        let credentials = DevinCredentialReader(path: path).readCredentials()
        XCTAssertEqual(credentials?.apiKey, "test-key")
        XCTAssertEqual(credentials?.serverURL.absoluteString, "https://server.example.com")
    }

    func test_snapshotData_convertsRemainingPercentToUsedAndHidesDailyOnMax() throws {
        let data = DevinUsageProvider.snapshotData(from: Data(responseJSON.utf8))
        XCTAssertEqual(data?.weekly?.used ?? -1, 48, accuracy: 0.0001)
        XCTAssertEqual(data?.weekly?.resetAt, Date(timeIntervalSince1970: 1795939200))
        XCTAssertEqual(data?.daily?.used ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(data?.hideDailyQuota, true)
        XCTAssertEqual(data?.planName, "Max")
        XCTAssertEqual(data?.email, "devin@example.com")
    }

    func test_fetchSnapshot_postsConnectMetadataAndEmitsOnlyWeeklyForMax() async throws {
        let server = URL(string: "https://server.example.com")!
        let url = server.appendingPathComponent("exa.seat_management_pb.SeatManagementService/GetUserStatus")
        URLProtocolStub.stubResponses[url] = (Data(responseJSON.utf8), 200)
        let provider = DevinUsageProvider(
            credentialReader: FixedCredentials(DevinCredentials(apiKey: "secret-key", serverURL: server)),
            session: makeSession()
        )

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.providerId, "devin")
        XCTAssertEqual(snapshot.planLabel, "Max")
        XCTAssertEqual(snapshot.quotas.count, 1)
        XCTAssertEqual(snapshot.quotas.first?.label, "weekly")
        XCTAssertEqual(snapshot.quotas.first?.shape.usedPercent ?? -1, 48, accuracy: 0.0001)
        XCTAssertEqual(snapshot.quotas.first?.renewalCadence, .weekly)
        let body = URLProtocolStub.lastBody(for: url) ?? ""
        XCTAssertTrue(body.contains("\"apiKey\":\"secret-key\"") || body.contains("\"apiKey\" : \"secret-key\""))
        XCTAssertTrue(body.contains("\"ideName\":\"devin\"") || body.contains("\"ideName\" : \"devin\""))
    }

    func test_fetchSnapshot_includesDailyWhenNotHidden() async throws {
        let json = responseJSON.replacingOccurrences(of: "\"hideDailyQuota\": true", with: "\"hideDailyQuota\": false")
        let server = URL(string: "https://server.example.com")!
        let url = server.appendingPathComponent("exa.seat_management_pb.SeatManagementService/GetUserStatus")
        URLProtocolStub.stubResponses[url] = (Data(json.utf8), 200)
        let provider = DevinUsageProvider(
            credentialReader: FixedCredentials(DevinCredentials(apiKey: "secret-key", serverURL: server)),
            session: makeSession()
        )

        let snapshot = try await provider.fetchSnapshot()
        XCTAssertEqual(snapshot.quotas.map(\.label), ["weekly", "daily"])
    }

    func test_errorClassification() {
        XCTAssertEqual(ProviderErrorPresentation.classify(DevinError.notDetected), .notConfigured)
        XCTAssertEqual(ProviderErrorPresentation.classify(DevinError.tokenRejected), .needsReauth)
        XCTAssertEqual(ProviderErrorPresentation.classify(DevinError.badResponse(500)), .error)
    }
    func test_snapshotData_acceptsProtoJsonNumericStrings() throws {
        let json = #"{"userStatus":{"planStatus":{"planInfo":{"planName":"Pro","hideDailyQuota":"false"},"weeklyQuotaRemainingPercent":"25","weeklyQuotaResetAtUnix":"1795939200","dailyQuotaRemainingPercent":"60","dailyQuotaResetAtUnix":"1795680000"}}}"#
        let data = DevinUsageProvider.snapshotData(from: Data(json.utf8))
        XCTAssertEqual(data?.weekly?.used ?? -1, 75, accuracy: 0.0001)
        XCTAssertEqual(data?.daily?.used ?? -1, 40, accuracy: 0.0001)
        XCTAssertEqual(data?.hideDailyQuota, false)
    }

    func test_snapshotData_rejectsPayloadWithoutQuotaWindows() {
        XCTAssertNil(DevinUsageProvider.snapshotData(from: Data(#"{"userStatus":{"planStatus":{"planInfo":{"planName":"Max"}}}}"#.utf8)))
    }

}
