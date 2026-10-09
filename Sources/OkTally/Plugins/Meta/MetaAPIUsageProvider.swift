import Foundation

/// The model catalog validates this connection. It exposes no account usage total.
/// https://dev.meta.ai/docs/models
final class MetaAPIUsageProvider: UsageProvider {
    let id: String
    let displayName = "Meta Muse / Spark API"
    let authMethod: AuthMethod = .apiKey
    let refreshInterval: TimeInterval = 1800
    private let apiKeyProvider: () -> String?
    private let session: URLSession
    static let modelsURL = URL(string: "https://api.meta.ai/v1/models")!

    init(instanceId: String = "meta-api", apiKeyProvider: @escaping () -> String?, session: URLSession = .shared) {
        id = instanceId
        self.apiKeyProvider = apiKeyProvider
        self.session = session
    }

    func isAuthenticated() async -> Bool { !(apiKeyProvider() ?? "").isEmpty }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        guard let key = apiKeyProvider(), !key.isEmpty else { throw ProviderAPIError.missingCredential(displayName) }
        var request = URLRequest(url: Self.modelsURL, timeoutInterval: 30)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard apiKeyProvider() == key else { throw CancellationError() }
        let status = (response as? HTTPURLResponse)?.statusCode
        if status == 401 || status == 403 { throw ProviderAPIError.rejectedCredential(displayName) }
        guard status == 200 else { throw ProviderAPIError.response(displayName, status) }
        struct Catalog: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]
        }
        guard let catalog = try? JSONDecoder().decode(Catalog.self, from: data), !catalog.data.isEmpty else {
            throw ProviderAPIError.malformedResponse(displayName)
        }
        let hasSpark = catalog.data.contains { $0.id.hasPrefix("muse-spark") }
        return ProviderSnapshot(providerId: id, fetchedAt: Date(), quotas: [], usageDetail: nil,
                                planLabel: "Meta Model API",
                                connectionNote: hasSpark
                                    ? L("Conexão validada. Saldo e uso da Meta API devem ser consultados no portal da Meta.")
                                    : L("Conexão validada. Muse Spark não aparece entre os modelos disponíveis nesta chave."))
    }
}
