import XCTest
@testable import OkTally

final class MoonshotUsageProviderTests: XCTestCase {
    func test_officialBalancePreservesPrecision() throws {
        let data = Data(#"{"code":0,"status":true,"scode":"0x0","data":{"available_balance":49.58894,"voucher_balance":46.58893,"cash_balance":3.00001}}"#.utf8)
        let snapshot = try MoonshotUsageProvider.snapshot(data: data, instanceId: "kimi-api#abc123")
        XCTAssertEqual(snapshot.quotas[0].shape, .creditBalance(remaining: Decimal(string: "49.58894")!, currency: "USD"))
        XCTAssertEqual(snapshot.providerId, "kimi-api#abc123")
        XCTAssertNil(snapshot.quotas[0].renewalCadence)
    }

    func test_unsuccessfulOrMissingBalanceNeverShowsZero() {
        for json in [#"{"code":1,"status":false,"data":{"available_balance":0}}"#, #"{"code":0,"status":true,"data":{}}"#] {
            XCTAssertThrowsError(try MoonshotUsageProvider.snapshot(data: Data(json.utf8), instanceId: "kimi-api"))
        }
    }
}
