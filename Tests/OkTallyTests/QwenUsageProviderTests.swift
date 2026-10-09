import XCTest
@testable import OkTally

final class QwenUsageProviderTests: XCTestCase {
    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    override func setUp() {
        super.setUp()
        URLProtocolStub.stubResponses = [:]
        URLProtocolStub.stubQueues = [:]
        URLProtocolStub.resetRequestCounts()
    }

    func test_codingPlanKeyValidatesGlobalCatalogWithoutInventingSubscriptionUsage() async throws {
        URLProtocolStub.stubResponses[QwenUsageProvider.codingPlanModelsURL] = (
            Data(#"{"data":[{"id":"qwen3-coder-plus"}]}"#.utf8),
            200
        )
        let provider = QwenUsageProvider(
            instanceId: "qwen#coding",
            apiKeyProvider: { "sk-sp-coding-key" },
            session: session()
        )

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.providerId, "qwen#coding")
        XCTAssertEqual(snapshot.planLabel, "Coding Plan")
        XCTAssertTrue(snapshot.quotas.isEmpty, "A model catalog does not prove a consumed subscription quota")
        XCTAssertNotNil(snapshot.connectionNote)
        XCTAssertEqual(URLProtocolStub.requestCount(for: QwenUsageProvider.codingPlanModelsURL), 1)
        XCTAssertEqual(URLProtocolStub.lastAuthorization(for: QwenUsageProvider.codingPlanModelsURL), "Bearer sk-sp-coding-key")
        XCTAssertEqual(URLProtocolStub.requestCount(for: QwenUsageProvider.payAsYouGoModelsURL), 0)
    }

    func test_payAsYouGoWorkspaceKeyUsesDocumentedNativeModelCatalog() async throws {
        URLProtocolStub.stubResponses[QwenUsageProvider.payAsYouGoModelsURL] = (
            Data(#"{"success":true,"output":{"total":1,"page_no":1,"page_size":20,"models":[{"model":"qwen3-max"}]}}"#.utf8),
            200
        )
        let provider = QwenUsageProvider(
            instanceId: "qwen#payg",
            apiKeyProvider: { "sk-ws-payg-key" },
            session: session()
        )

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.providerId, "qwen#payg")
        XCTAssertEqual(snapshot.planLabel, "Model Studio API")
        XCTAssertTrue(snapshot.quotas.isEmpty, "RPM/TPM limits are not PAYG spend or balance")
        XCTAssertNotNil(snapshot.connectionNote)
        XCTAssertEqual(URLProtocolStub.requestCount(for: QwenUsageProvider.payAsYouGoModelsURL), 1)
        XCTAssertEqual(URLProtocolStub.lastAuthorization(for: QwenUsageProvider.payAsYouGoModelsURL), "Bearer sk-ws-payg-key")
        XCTAssertEqual(URLProtocolStub.requestCount(for: QwenUsageProvider.codingPlanModelsURL), 0)
    }

    func test_eachInstanceReadsOnlyItsOwnKey() async throws {
        URLProtocolStub.stubResponses[QwenUsageProvider.payAsYouGoModelsURL] = (
            Data(#"{"success":true,"output":{"models":[{"model":"qwen3-max"}]}}"#.utf8),
            200
        )
        let first = QwenUsageProvider(instanceId: "qwen#one", apiKeyProvider: { "sk-first" }, session: session())
        let second = QwenUsageProvider(instanceId: "qwen#two", apiKeyProvider: { "sk-second" }, session: session())

        let firstSnapshot = try await first.fetchSnapshot()
        XCTAssertEqual(URLProtocolStub.lastAuthorization(for: QwenUsageProvider.payAsYouGoModelsURL), "Bearer sk-first")
        let secondSnapshot = try await second.fetchSnapshot()

        XCTAssertEqual(firstSnapshot.providerId, "qwen#one")
        XCTAssertEqual(secondSnapshot.providerId, "qwen#two")
        XCTAssertEqual(URLProtocolStub.lastAuthorization(for: QwenUsageProvider.payAsYouGoModelsURL), "Bearer sk-second")
        XCTAssertEqual(URLProtocolStub.requestCount(for: QwenUsageProvider.payAsYouGoModelsURL), 2)
    }

    func test_malformedCatalogNeverBecomesAZeroPercentQuota() async {
        URLProtocolStub.stubResponses[QwenUsageProvider.codingPlanModelsURL] = (Data(#"{"data":[]}"#.utf8), 200)
        let provider = QwenUsageProvider(apiKeyProvider: { "sk-sp-empty-catalog" }, session: session())

        do {
            _ = try await provider.fetchSnapshot()
            XCTFail("Expected malformed catalog")
        } catch {
            XCTAssertEqual(ProviderErrorPresentation.classify(error), .error)
        }
    }

    func test_rejectedKeyIsClassifiedForReauthentication() async {
        URLProtocolStub.stubResponses[QwenUsageProvider.codingPlanModelsURL] = (Data(), 401)
        let provider = QwenUsageProvider(apiKeyProvider: { "sk-sp-rejected" }, session: session())

        do {
            _ = try await provider.fetchSnapshot()
            XCTFail("Expected rejected credential")
        } catch {
            XCTAssertEqual(ProviderErrorPresentation.classify(error), .needsReauth)
        }
    }

    func test_keyPrefixSelectsOnlyFixedOfficialGlobalHosts() {
        XCTAssertEqual(QwenUsageProvider.accountType(for: "sk-sp-plan"), .codingPlan)
        XCTAssertEqual(QwenUsageProvider.accountType(for: "sk-payg"), .payAsYouGo)
        XCTAssertEqual(QwenUsageProvider.accountType(for: "sk-ws-payg"), .payAsYouGo)
        XCTAssertNil(QwenUsageProvider.accountType(for: "not-a-model-studio-key"))
        XCTAssertEqual(
            QwenUsageProvider.modelsURL(for: .codingPlan),
            URL(string: "https://coding-intl.dashscope.aliyuncs.com/v1/models")
        )
        XCTAssertEqual(
            QwenUsageProvider.modelsURL(for: .payAsYouGo),
            URL(string: "https://dashscope-intl.aliyuncs.com/api/v1/models")
        )
    }
}
