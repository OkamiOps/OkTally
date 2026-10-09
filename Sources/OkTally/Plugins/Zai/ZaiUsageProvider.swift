import Foundation

/// Read-only contract used by zai-org/zai-coding-plugins' usage-query-skill.
final class ZaiUsageProvider: UsageProvider {
    let id: String
    let displayName = "GLM / Z.ai Coding Plan"
    let authMethod: AuthMethod = .apiKey
    let refreshInterval: TimeInterval = 600
    private let apiKeyProvider: () -> String?
    private let session: URLSession
    static let quotaURL = URL(string: "https://api.z.ai/api/monitor/usage/quota/limit")!

    init(instanceId: String = "zai", apiKeyProvider: @escaping () -> String?, session: URLSession = .shared) {
        id = instanceId
        self.apiKeyProvider = apiKeyProvider
        self.session = session
    }

    func isAuthenticated() async -> Bool { !(apiKeyProvider() ?? "").isEmpty }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        guard let key = apiKeyProvider(), !key.isEmpty else { throw ProviderAPIError.missingCredential(displayName) }
        var request = URLRequest(url: Self.quotaURL, timeoutInterval: 30)
        // The official usage plugin sends the raw API key, without a Bearer prefix.
        request.setValue(key, forHTTPHeaderField: "Authorization")
        request.setValue("en-US,en", forHTTPHeaderField: "Accept-Language")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
            struct Payload: Decodable {
                struct Limit: Decodable {
                    let type: String
                    let percentage: Double?
                    let currentValue: Double?
                    let usage: Double?
                    let nextResetTime: Double?
                }
                let limits: [Limit]
                let level: String?
            }
            let success: Bool?
            let data: Payload
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data), response.success != false else {
            throw ProviderAPIError.malformedResponse("GLM / Z.ai")
        }
        var missingReset = false
        var quotas: [QuotaWindow] = []
        for (index, item) in response.data.limits.enumerated() {
            guard ["TOKENS_LIMIT", "CREDIT_LIMIT", "TIME_LIMIT"].contains(item.type) else { continue }
            let used: Double
            let limit: Double
            if item.type == "TIME_LIMIT", let current = item.currentValue, let total = item.usage,
               current.isFinite, total.isFinite, current >= 0, total > 0 {
                used = current; limit = total
            } else if let percentage = item.percentage, percentage.isFinite, percentage >= 0 {
                used = percentage; limit = 100
            } else {
                throw ProviderAPIError.malformedResponse("GLM / Z.ai")
            }
            let reset = item.nextResetTime.flatMap { epoch -> Date? in
                guard epoch.isFinite, epoch > 0 else { return nil }
                return Date(timeIntervalSince1970: epoch > 10_000_000_000 ? epoch / 1_000 : epoch)
            }
            let shape: QuotaShape
            if let reset {
                shape = .periodicCounter(used: used, limit: limit, resetAt: reset)
            } else {
                // Preserve the reported percentage/count while leaving unknown renewal
                // time unset. Never invent a reset five hours after this read.
                missingReset = true
                shape = .estimated(used: used, limit: limit, basis: .reactiveRateLimit, resetAt: nil)
            }
            let label = item.type == "TIME_LIMIT" ? "monthly tools" : "coding quota \(index + 1)"
            quotas.append(QuotaWindow(label: label, shape: shape))
        }
        guard !quotas.isEmpty else { throw ProviderAPIError.malformedResponse("GLM / Z.ai") }
        return ProviderSnapshot(providerId: instanceId, fetchedAt: now, quotas: quotas, usageDetail: nil,
                                planLabel: response.data.level,
                                connectionNote: missingReset ? L("Uso informado pela Z.ai; a API não informou a renovação de algumas cotas.") : nil)
    }
}
