import Foundation

/// Validates one Qwen / Model Studio API key without representing rate limits as
/// account usage. The documented `GET /api/v1/quotas` response contains per-model
/// request/token *limits*, not the consumed Coding Plan or PAYG balance.
///
/// Coding Plan usage is exposed by the official Bailian CLI only through its
/// separately authenticated Console domain (`bl usage coding-plan`); an API key
/// cannot safely substitute for that console access token. Keep this provider
/// deliberately read-only and per-key: it validates the key against the fixed
/// global endpoint appropriate to its key type and never consults CLI profiles.
///
/// Sources:
/// - https://github.com/QwenLM/qwen-code/blob/main/docs/users/configuration/auth.md
/// - https://docs.modelstudio.console.alibabacloud.com/en/model-studio/list-models
final class QwenUsageProvider: UsageProvider {
    enum AccountType: Equatable {
        case codingPlan
        case payAsYouGo
    }

    let id: String
    let displayName = "Qwen / Model Studio"
    let authMethod: AuthMethod = .apiKey
    /// Catalog validation is not usage telemetry; avoid needlessly polling it.
    let refreshInterval: TimeInterval = 1800

    private let apiKeyProvider: () -> String?
    private let session: URLSession

    /// Qwen Code's documented international Coding Plan OpenAI-compatible base URL.
    static let codingPlanModelsURL = URL(string: "https://coding-intl.dashscope.aliyuncs.com/v1/models")!
    /// Model Studio's documented international PAYG native API model-catalog endpoint.
    static let payAsYouGoModelsURL = URL(string: "https://dashscope-intl.aliyuncs.com/api/v1/models")!

    init(
        instanceId: String = "qwen",
        apiKeyProvider: @escaping () -> String?,
        session: URLSession = .shared
    ) {
        id = instanceId
        self.apiKeyProvider = apiKeyProvider
        self.session = session
    }

    func isAuthenticated() async -> Bool {
        !(apiKeyProvider()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
    }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        guard let rawKey = apiKeyProvider() else {
            throw ProviderAPIError.missingCredential(displayName)
        }
        let apiKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw ProviderAPIError.missingCredential(displayName)
        }
        guard let accountType = Self.accountType(for: apiKey) else {
            throw ProviderAPIError.rejectedCredential(displayName)
        }

        let url = Self.modelsURL(for: accountType)
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            try Task.checkCancellation()
            throw ProviderAPIError.response(displayName, nil)
        }

        try Task.checkCancellation()
        guard apiKeyProvider()?.trimmingCharacters(in: .whitespacesAndNewlines) == apiKey else { throw CancellationError() }
        let status = (response as? HTTPURLResponse)?.statusCode
        if status == 401 || status == 403 {
            throw ProviderAPIError.rejectedCredential(displayName)
        }
        guard status == 200 else {
            throw ProviderAPIError.response(displayName, status)
        }
        guard Self.hasModels(in: data, for: accountType) else {
            throw ProviderAPIError.malformedResponse(displayName)
        }

        let planLabel: String
        let connectionNote: String
        switch accountType {
        case .codingPlan:
            planLabel = "Coding Plan"
            connectionNote = L("Conexão validada. O uso do Coding Plan não é exposto por API key; consulte o console da Alibaba Cloud.")
        case .payAsYouGo:
            planLabel = "Model Studio API"
            connectionNote = L("Conexão validada. O catálogo e os limites de taxa não representam gasto ou saldo PAYG; consulte o console da Alibaba Cloud.")
        }

        return ProviderSnapshot(
            providerId: id,
            fetchedAt: Date(),
            quotas: [],
            usageDetail: nil,
            planLabel: planLabel,
            connectionNote: connectionNote
        )
    }

    static func accountType(for apiKey: String) -> AccountType? {
        // `sk-sp-` is the Coding Plan key prefix used by Qwen Code. Ordinary
        // Model Studio PAYG keys, including workspace keys (`sk-ws-`), use `sk-`.
        if apiKey.hasPrefix("sk-sp-") { return .codingPlan }
        if apiKey.hasPrefix("sk-") { return .payAsYouGo }
        return nil
    }

    static func modelsURL(for accountType: AccountType) -> URL {
        switch accountType {
        case .codingPlan: codingPlanModelsURL
        case .payAsYouGo: payAsYouGoModelsURL
        }
    }

    static func hasModels(in data: Data, for accountType: AccountType) -> Bool {
        switch accountType {
        case .codingPlan:
            struct Response: Decodable {
                struct Model: Decodable { let id: String }
                let data: [Model]
            }
            guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return false }
            return response.data.contains { !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        case .payAsYouGo:
            struct Response: Decodable {
                struct Output: Decodable {
                    struct Model: Decodable { let model: String }
                    let models: [Model]
                }
                let success: Bool
                let output: Output
            }
            guard let response = try? JSONDecoder().decode(Response.self, from: data), response.success else {
                return false
            }
            return response.output.models.contains { !$0.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
    }
}
