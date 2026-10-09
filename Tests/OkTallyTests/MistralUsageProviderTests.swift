import XCTest
@testable import OkTally

final class MistralUsageProviderTests: XCTestCase {
    private let periodFixture = Data(#"""
    {
      "start_date": "2026-10-01T00:00:00.000Z",
      "end_date": "2026-11-01T00:00:00.000Z",
      "currency": "USD"
    }
    """#.utf8)

    func test_snapshot_mapsDocumentedTotalUsageAndLimitToMonthlyCounter() throws {
        let spendLimit = Data(#"""
        {
          "limits": {
            "completion": {
              "no_monthly_limit": false,
              "monthly_limit_reached": false,
              "usage": 12.345678,
              "vibe_usage": 0.123456,
              "total_usage": 12.469134,
              "usage_limit": 500
            },
            "currency": "USD",
            "last_payment_failure": false,
            "last_payment_failure_protection": null
          }
        }
        """#.utf8)

        let snapshot = try MistralUsageProvider.snapshot(
            usageData: periodFixture,
            spendLimitData: spendLimit,
            instanceId: "mistral#team",
            now: Date(timeIntervalSince1970: 1)
        )

        XCTAssertEqual(snapshot.providerId, "mistral#team")
        XCTAssertEqual(snapshot.fetchedAt, Date(timeIntervalSince1970: 1))
        XCTAssertEqual(snapshot.quotas[0].label, "monthly spend")
        XCTAssertEqual(snapshot.quotas[0].renewalCadence, .monthly)
        guard case .periodicCounter(let used, let limit, let resetAt) = snapshot.quotas[0].shape else {
            return XCTFail("Expected monthly periodic counter")
        }
        XCTAssertEqual(used, 12.469134)
        XCTAssertEqual(limit, 500)
        XCTAssertEqual(resetAt, ISO8601DateFormatter().date(from: "2026-11-01T00:00:00Z"))
    }

    func test_snapshot_keepsUSDDecimalPrecisionWhenLimitIsOmitted() throws {
        let spendLimit = Data(#"""
        {
          "limits": {
            "completion": {
              "no_monthly_limit": true,
              "monthly_limit_reached": false,
              "total_usage": 78.333333,
              "usage_limit": null
            },
            "currency": "USD",
            "last_payment_failure": false,
            "last_payment_failure_protection": null
          }
        }
        """#.utf8)

        let snapshot = try MistralUsageProvider.snapshot(
            usageData: periodFixture,
            spendLimitData: spendLimit,
            instanceId: "mistral"
        )

        XCTAssertEqual(snapshot.quotas[0].renewalCadence, nil)
        XCTAssertEqual(snapshot.quotas[0].shape, .meteredOnly(costAccrued: Decimal(string: "78.333333")!))
    }

    func test_snapshot_rejectsMissingTotalOrInvalidPeriodRatherThanInventingUsage() {
        let withoutTotal = Data(#"""
        {
          "limits": {
            "completion": { "monthly_limit_reached": false, "usage_limit": 500 },
            "currency": "USD"
          }
        }
        """#.utf8)
        XCTAssertThrowsError(try MistralUsageProvider.snapshot(
            usageData: periodFixture,
            spendLimitData: withoutTotal,
            instanceId: "mistral"
        ))

        let invalidPeriod = Data(#"""
        { "start_date": "2026-11-01T00:00:00Z", "end_date": "2026-10-01T00:00:00Z", "currency": "USD" }
        """#.utf8)
        let validLimit = Data(#"""
        { "limits": { "completion": { "monthly_limit_reached": false, "total_usage": 1, "usage_limit": 5 }, "currency": "USD" } }
        """#.utf8)
        XCTAssertThrowsError(try MistralUsageProvider.snapshot(
            usageData: invalidPeriod,
            spendLimitData: validLimit,
            instanceId: "mistral"
        ))
    }

    func test_usageURLUsesDocumentedMonthAndYearQuery() {
        let date = Calendar(identifier: .gregorian).date(from: DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(secondsFromGMT: 0), year: 2026, month: 10, day: 9))!
        let components = URLComponents(url: MistralUsageProvider.usageURL(for: date), resolvingAgainstBaseURL: false)!
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "api.mistral.ai")
        XCTAssertEqual(components.path, "/v1/admin/usage")
        XCTAssertEqual(components.queryItems?.reduce(into: [String: String]()) { $0[$1.name] = $1.value }, ["month": "10", "year": "2026"])
    }

    func test_rejectedAdminKeyIsClassifiedAsReauthentication() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        let usageURL = MistralUsageProvider.usageURL(for: Date())
        URLProtocolStub.stubResponses[usageURL] = (Data(), 401)
        let provider = MistralUsageProvider(apiKeyProvider: { "test-admin-key" }, session: URLSession(configuration: config))

        do {
            _ = try await provider.fetchSnapshot()
            XCTFail("Expected rejected credential")
        } catch {
            XCTAssertEqual(ProviderErrorPresentation.classify(error), .needsReauth)
        }
    }
}
