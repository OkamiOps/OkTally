import XCTest
@testable import OkTally

final class MetaAPIUsageProviderTests: XCTestCase {
    func test_verifiedCatalogDoesNotInventAccountQuota() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        URLProtocolStub.stubResponses[MetaAPIUsageProvider.modelsURL] =
            (Data(#"{"data":[{"id":"muse-spark-1.3"}]}"#.utf8), 200)
        let provider = MetaAPIUsageProvider(instanceId: "meta-api#abc123", apiKeyProvider: { "example" },
                                            session: URLSession(configuration: config))
        let snapshot = try await provider.fetchSnapshot()
        XCTAssertEqual(snapshot.providerId, "meta-api#abc123")
        XCTAssertTrue(snapshot.quotas.isEmpty)
        XCTAssertNotNil(snapshot.connectionNote)
        XCTAssertNil(ProviderPresentationPolicy.recoveryAction(for: nil))
    }

    func test_snapshotFromBeforeConnectionNoteStillDecodes() throws {
        let data = Data(#"{"providerId":"example","fetchedAt":0,"quotas":[],"usageDetail":null}"#.utf8)
        let old = try JSONDecoder().decode(ProviderSnapshot.self, from: data)
        XCTAssertNil(old.connectionNote)
    }
}
