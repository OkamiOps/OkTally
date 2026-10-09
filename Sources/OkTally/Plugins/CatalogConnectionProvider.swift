import Foundation

/// Validates API access when the service exposes no read-only account usage API.
/// A model catalog is never turned into a quota or a balance.
final class CatalogConnectionProvider: UsageProvider {
    enum Service {
        case zai, mistral
        var name: String { self == .zai ? "GLM / Z.ai API" : "Mistral API" }
        var modelsURL: URL {
            URL(string: self == .zai ? "https://api.z.ai/api/paas/v4/models" : "https://api.mistral.ai/v1/models")!
        }
        var note: String {
            self == .zai
                ? L("Conexão da API validada. O saldo e o uso por consumo ficam no portal da Z.ai; as cotas do Coding Plan têm conexão separada.")
                : L("Conexão da API validada. Para acompanhar gastos, adicione Mistral Organização com uma chave administrativa.")
        }
    }
    let id: String
    var displayName: String { service.name }
    let authMethod: AuthMethod = .apiKey
    let refreshInterval: TimeInterval = 1800
    private let service: Service
    private let apiKeyProvider: () -> String?
    private let session: URLSession

    init(instanceId: String, service: Service, apiKeyProvider: @escaping () -> String?, session: URLSession = .shared) {
        id = instanceId
        self.service = service
        self.apiKeyProvider = apiKeyProvider
        self.session = session
    }

    func isAuthenticated() async -> Bool { !(apiKeyProvider() ?? "").isEmpty }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        guard let key = apiKeyProvider(), !key.isEmpty else { throw ProviderAPIError.missingCredential(displayName) }
        var request = URLRequest(url: service.modelsURL, timeoutInterval: 30)
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
        guard let catalog = try? JSONDecoder().decode(Catalog.self, from: data),
              catalog.data.contains(where: { !$0.id.isEmpty }) else { throw ProviderAPIError.malformedResponse(displayName) }
        return ProviderSnapshot(providerId: id, fetchedAt: Date(), quotas: [], usageDetail: nil, connectionNote: service.note)
    }
}
