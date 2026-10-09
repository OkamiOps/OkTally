import XCTest
@testable import OkTally

final class DeepSeekUsageProviderTests: XCTestCase {
    func test_balancesKeepCurrencyAndDecimalPrecision() throws {
        let data = Data(#"{"balance_infos":[{"currency":"USD","total_balance":"78.333333"},{"currency":"CNY","total_balance":"100.01"}]}"#.utf8)
        let snapshot = try DeepSeekUsageProvider.snapshot(data: data, instanceId: "deepseek#abc123")
        XCTAssertEqual(snapshot.providerId, "deepseek#abc123")
        XCTAssertEqual(snapshot.quotas.map(\.label), ["balance (USD)", "balance (CNY)"])
        XCTAssertEqual(snapshot.quotas[0].shape, .creditBalance(remaining: Decimal(string: "78.333333")!, currency: "USD"))
    }

    func test_invalidBalanceNeverBecomesZeroOrPartialNumber() {
        for value in ["unknown", "12oops", "NaN"] {
            let data = Data("{\"balance_infos\":[{\"currency\":\"USD\",\"total_balance\":\"\(value)\"}]}".utf8)
            XCTAssertThrowsError(try DeepSeekUsageProvider.snapshot(data: data, instanceId: "deepseek"))
        }
        XCTAssertThrowsError(try DeepSeekUsageProvider.snapshot(data: Data(#"{"balance_infos":[]}"#.utf8), instanceId: "deepseek"))
    }

    func test_changedKeyCancelsResponseFromPreviousAccount() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        URLProtocolStub.stubResponses[DeepSeekUsageProvider.balanceURL] = (Data(#"{"balance_infos":[{"currency":"USD","total_balance":"10"}]}"#.utf8), 200)
        defer { URLProtocolStub.stubResponses = [:] }
        var reads = 0
        let provider = DeepSeekUsageProvider(apiKeyProvider: {
            reads += 1
            return reads == 1 ? "previous" : "replacement"
        }, session: URLSession(configuration: config))
        do {
            _ = try await provider.fetchSnapshot()
            XCTFail("old account quota must not be published")
        } catch is CancellationError { }
    }

    func test_rejectedKeyOffersReconnection() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        URLProtocolStub.stubResponses[DeepSeekUsageProvider.balanceURL] = (Data(), 401)
        let provider = DeepSeekUsageProvider(apiKeyProvider: { "example" }, session: URLSession(configuration: config))
        do {
            _ = try await provider.fetchSnapshot()
            XCTFail("Expected rejection")
        } catch {
            XCTAssertEqual(ProviderErrorPresentation.classify(error), .needsReauth)
        }
    }
}
