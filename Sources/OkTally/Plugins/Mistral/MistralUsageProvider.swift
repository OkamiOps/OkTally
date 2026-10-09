import Foundation

/// Organization billing usage from Mistral's Admin API.
///
/// Schema source: https://docs.mistral.ai/openapi.yaml (`UsageOUTJSON`, `LimitsOUT`,
/// and `UsageLimits`). This deliberately reads `total_usage` from the spend-limit
/// response instead of deriving a cost from the per-model usage maps, whose value
/// shapes are intentionally open-ended in the published OpenAPI schema.
final class MistralUsageProvider: UsageProvider {
    let id: String
    let displayName = "Mistral"
    let authMethod: AuthMethod = .apiKey
    let refreshInterval: TimeInterval = 600

    private let apiKeyProvider: () -> String?
    private let session: URLSession

    static let adminBaseURL = URL(string: "https://api.mistral.ai/v1/admin")!
    static let spendLimitURL = URL(string: "https://api.mistral.ai/v1/admin/spend-limit")!

    init(
        instanceId: String = "mistral",
        apiKeyProvider: @escaping () -> String?,
        session: URLSession = .shared
    ) {
        id = instanceId
        self.apiKeyProvider = apiKeyProvider
        self.session = session
    }

    func isAuthenticated() async -> Bool {
        !(apiKeyProvider() ?? "").isEmpty
    }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        guard let apiKey = apiKeyProvider(), !apiKey.isEmpty else {
            throw ProviderAPIError.missingCredential(displayName)
        }

        // Both endpoints are organization-level Admin API reads. Keep these separate:
        // `/usage` is authoritative for the report period, while `/spend-limit`
        // exposes the documented total that is counted against its monthly limit.
        let usageData = try await fetch(url: Self.usageURL(for: Date()), apiKey: apiKey)
        let spendLimitData = try await fetch(url: Self.spendLimitURL, apiKey: apiKey)
        try Task.checkCancellation()
        guard apiKeyProvider() == apiKey else { throw CancellationError() }
        return try Self.snapshot(
            usageData: usageData,
            spendLimitData: spendLimitData,
            instanceId: id
        )
    }

    /// Kept internal so tests can pin the URL contract without relying on the clock.
    static func usageURL(for date: Date) -> URL {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.month, .year], from: date)

        var urlComponents = URLComponents(url: adminBaseURL.appendingPathComponent("usage"), resolvingAgainstBaseURL: false)!
        urlComponents.queryItems = [
            URLQueryItem(name: "month", value: String(components.month!)),
            URLQueryItem(name: "year", value: String(components.year!)),
        ]
        return urlComponents.url!
    }

    static func snapshot(
        usageData: Data,
        spendLimitData: Data,
        instanceId: String,
        now: Date = Date()
    ) throws -> ProviderSnapshot {
        let decoder = JSONDecoder()
        guard let usage = try? decoder.decode(UsagePeriod.self, from: usageData),
              let limits = try? decoder.decode(SpendLimitResponse.self, from: spendLimitData),
              let totalUsage = limits.limits.completion.totalUsage,
              totalUsage >= 0,
              usage.startDate < usage.endDate,
              limits.limits.currency == "USD",
              usage.currency == nil || usage.currency == limits.limits.currency else {
            throw ProviderAPIError.malformedResponse("Mistral")
        }

        let window: QuotaWindow
        if limits.limits.completion.noMonthlyLimit != true,
           let usageLimit = limits.limits.completion.usageLimit,
           usageLimit > 0 {
            window = QuotaWindow(
                label: "monthly spend",
                shape: .periodicCounter(
                    used: NSDecimalNumber(decimal: totalUsage).doubleValue,
                    limit: NSDecimalNumber(decimal: usageLimit).doubleValue,
                    resetAt: usage.endDate
                ),
                renewalCadence: .monthly
            )
        } else {
            // `meteredOnly` keeps a Decimal end-to-end, avoiding a false cent-level
            // total when the organization has no monthly spending cap.
            window = QuotaWindow(
                label: "monthly spend",
                shape: .meteredOnly(costAccrued: totalUsage)
            )
        }

        return ProviderSnapshot(providerId: instanceId, fetchedAt: now, quotas: [window], usageDetail: nil,
                                connectionNote: L("Gastos e limite de consumo da organização Mistral. As cotas da assinatura pessoal não são incluídas."))
    }

    private func fetch(url: URL, apiKey: String) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ProviderAPIError.response(displayName, nil)
        }

        let status = (response as? HTTPURLResponse)?.statusCode
        if status == 401 || status == 403 {
            throw ProviderAPIError.rejectedCredential(displayName)
        }
        guard status == 200 else {
            throw ProviderAPIError.response(displayName, status)
        }
        return data
    }
}

private extension MistralUsageProvider {
    struct UsagePeriod: Decodable {
        let startDate: Date
        let endDate: Date
        let currency: String?

        enum CodingKeys: String, CodingKey {
            case startDate = "start_date"
            case endDate = "end_date"
            case currency
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            startDate = try Self.date(from: container, forKey: .startDate)
            endDate = try Self.date(from: container, forKey: .endDate)
            currency = try container.decodeIfPresent(String.self, forKey: .currency)
        }

        private static func date(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Date {
            let raw = try container.decode(String.self, forKey: key)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Expected ISO 8601 date-time")
        }
    }

    struct SpendLimitResponse: Decodable {
        let limits: LimitsContext
    }

    struct LimitsContext: Decodable {
        let completion: UsageLimits
        let currency: String
    }

    struct UsageLimits: Decodable {
        let noMonthlyLimit: Bool?
        let monthlyLimitReached: Bool
        let totalUsage: Decimal?
        let usageLimit: Decimal?

        enum CodingKeys: String, CodingKey {
            case noMonthlyLimit = "no_monthly_limit"
            case monthlyLimitReached = "monthly_limit_reached"
            case totalUsage = "total_usage"
            case usageLimit = "usage_limit"
        }
    }
}
