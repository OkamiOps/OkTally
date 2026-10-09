import XCTest
@testable import OkTally

final class ZaiUsageProviderTests: XCTestCase {
    func test_reportedCountsAndPercentagesKeepActualReset() throws {
        let data = Data(#"{"data":{"level":"max","limits":[{"type":"TOKENS_LIMIT","percentage":37.5,"nextResetTime":1793491200000},{"type":"TIME_LIMIT","currentValue":14,"usage":100,"percentage":14,"nextResetTime":1793491200000}]}}"#.utf8)
        let snapshot = try ZaiUsageProvider.snapshot(data: data, instanceId: "zai#abc123")
        XCTAssertEqual(try XCTUnwrap(snapshot.quotas[0].shape.usedPercent), 37.5, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(snapshot.quotas[1].shape.usedPercent), 14, accuracy: 0.000001)
        XCTAssertEqual(snapshot.quotas[0].shape.resetAt, Date(timeIntervalSince1970: 1793491200))
        XCTAssertEqual(snapshot.planLabel, "max")
        XCTAssertEqual(snapshot.providerId, "zai#abc123")
    }

    func test_missingRenewalDoesNotInventOne() throws {
        let data = Data(#"{"data":{"limits":[{"type":"TOKENS_LIMIT","percentage":42}]}}"#.utf8)
        let snapshot = try ZaiUsageProvider.snapshot(data: data, instanceId: "zai")
        XCTAssertEqual(snapshot.quotas[0].shape.usedPercent, 42)
        XCTAssertNil(snapshot.quotas[0].shape.resetAt)
        XCTAssertNotNil(snapshot.connectionNote)
        XCTAssertNil(snapshot.quotas[0].renewalCadence)
    }

    func test_missingUsageNeverBecomesZero() {
        for json in [#"{"data":{"limits":[{"type":"TOKENS_LIMIT"}]}}"#, #"{"data":{"limits":[]}}"#, #"{"success":false,"data":{"limits":[{"type":"TOKENS_LIMIT","percentage":0}]}}"#] {
            XCTAssertThrowsError(try ZaiUsageProvider.snapshot(data: Data(json.utf8), instanceId: "zai"))
        }
    }
}
