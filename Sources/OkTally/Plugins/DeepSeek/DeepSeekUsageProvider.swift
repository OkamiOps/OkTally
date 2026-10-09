import Foundation

/// https://api-docs.deepseek.com/api/get-user-balance/
final class DeepSeekUsageProvider: UsageProvider {
    let id: String
    let displayName = "DeepSeek API"
    let authMethod: AuthMethod = .apiKey
    let refreshInterval: TimeInterval = 600
    private let apiKeyProvider: () -> String?
    private let session: URLSession
    static let balanceURL = URL(string: "https://api.deepseek.com/user/balance")!

    init(instanceId: String = "deepseek", apiKeyProvider: @escaping () -> String?, session: URLSession = .shared) {
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
            struct Balance: Decodable { let currency: String; let total_balance: String }
            let balance_infos: [Balance]
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data), !response.balance_infos.isEmpty else {
            throw ProviderAPIError.malformedResponse("DeepSeek API")
        }
        let quotas = try response.balance_infos.map { balance -> QuotaWindow in
            let scanner = Scanner(string: balance.total_balance)
            scanner.locale = Locale(identifier: "en_US_POSIX")
            var amount = Decimal()
            guard scanner.scanDecimal(&amount), scanner.isAtEnd,
                  !amount.isNaN, ["USD", "CNY"].contains(balance.currency) else {
                throw ProviderAPIError.malformedResponse("DeepSeek API")
            }
            let label = response.balance_infos.count == 1 ? "balance" : "balance (\(balance.currency))"
            return QuotaWindow(label: label, shape: .creditBalance(remaining: amount, currency: balance.currency))
        }
        return ProviderSnapshot(providerId: instanceId, fetchedAt: now, quotas: quotas, usageDetail: nil)
    }
}
