import Foundation

/// https://platform.kimi.ai/docs/api/balance — independent of Kimi Code OAuth.
final class MoonshotUsageProvider: UsageProvider {
    let id: String
    let displayName = "Kimi / Moonshot API"
    let authMethod: AuthMethod = .apiKey
    let refreshInterval: TimeInterval = 600
    private let apiKeyProvider: () -> String?
    private let session: URLSession
    static let balanceURL = URL(string: "https://api.moonshot.ai/v1/users/me/balance")!

    init(instanceId: String = "kimi-api", apiKeyProvider: @escaping () -> String?, session: URLSession = .shared) {
        id = instanceId
        self.apiKeyProvider = apiKeyProvider
        self.session = session
    }

    func isAuthenticated() async -> Bool { !(apiKeyProvider() ?? "").isEmpty }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        guard let key = apiKeyProvider(), !key.isEmpty else { throw ProviderAPIError.missingCredential(displayName) }
        var request = URLRequest(url: Self.balanceURL, timeoutInterval: 30)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard apiKeyProvider() == key else { throw CancellationError() }
        let status = (response as? HTTPURLResponse)?.statusCode
        if status == 401 || status == 403 { throw ProviderAPIError.rejectedCredential(displayName) }
        guard status == 200 else { throw ProviderAPIError.response(displayName, status) }
        return try Self.snapshot(data: data, instanceId: id)
    }

    static func snapshot(data: Data, instanceId: String, now: Date = Date()) throws -> ProviderSnapshot {
        struct Response: Decodable {
            struct Balance: Decodable { let available_balance: Decimal }
            let code: Int
            let status: Bool
            let data: Balance
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data), response.code == 0,
              response.status, !response.data.available_balance.isNaN else {
            throw ProviderAPIError.malformedResponse("Kimi / Moonshot API")
        }
        return ProviderSnapshot(providerId: instanceId, fetchedAt: now,
                                quotas: [QuotaWindow(label: "balance", shape: .creditBalance(remaining: response.data.available_balance, currency: "USD"))],
                                usageDetail: nil)
    }
}
