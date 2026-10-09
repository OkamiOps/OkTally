import XCTest
@testable import OkTally

final class CatalogConnectionProviderTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.stubResponses = [:]
        super.tearDown()
    }

    func test_apiValidationDoesNotFabricateAccountQuota() async throws {
        for service in [CatalogConnectionProvider.Service.zai, .mistral] {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [URLProtocolStub.self]
            URLProtocolStub.stubResponses[service.modelsURL] = (Data(#"{"data":[{"id":"example-model"}]}"#.utf8), 200)
            let provider = CatalogConnectionProvider(instanceId: "account#abc123", service: service,
                                                       apiKeyProvider: { "example-key" }, session: URLSession(configuration: configuration))
            let snapshot = try await provider.fetchSnapshot()
            XCTAssertTrue(snapshot.quotas.isEmpty)
            XCTAssertNotNil(snapshot.connectionNote)
            XCTAssertEqual(snapshot.providerId, "account#abc123")
            XCTAssertEqual(URLProtocolStub.lastAuthorization(for: service.modelsURL), "Bearer example-key")
        }
    }

    func test_invalidCatalogDoesNotConfirmConnection() async {
        let service = CatalogConnectionProvider.Service.mistral
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        URLProtocolStub.stubResponses[service.modelsURL] = (Data(#"{"data":[]}"#.utf8), 200)
        let provider = CatalogConnectionProvider(instanceId: "mistral-api", service: service,
                                                 apiKeyProvider: { "example-key" }, session: URLSession(configuration: configuration))
        do { _ = try await provider.fetchSnapshot(); XCTFail("Empty catalog must not confirm a key") }
        catch { XCTAssertEqual(ProviderErrorPresentation.classify(error), .error) }
    }
}
