import Foundation
import CoreFoundation

/// Kimi Code subscription usage. This is intentionally distinct from the Moonshot API-key
/// provider: the OAuth audience, account type, and quota endpoint are not interchangeable.
final class KimiUsageProvider: UsageProvider {
    let id: String
    let displayName = "Kimi Code"
    let authMethod: AuthMethod = .oauthSession
    let refreshInterval: TimeInterval = 300

    static let usageURL = URL(string: "https://api.kimi.com/coding/v1/usages")!

    private let tokenStore: TokenStoring
    private let session: URLSession
    private let tokenManager: KimiTokenManager

    init(instanceId: String, tokenStore: TokenStoring, session: URLSession = .shared) {
        self.id = instanceId
        self.tokenStore = tokenStore
        self.session = session
        self.tokenManager = KimiTokenManager(providerID: instanceId, tokenStore: tokenStore, session: session)
    }

    func isAuthenticated() async -> Bool {
        tokenStore.load(providerId: id) != nil
    }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        var token = try await tokenManager.accessToken(forceRefresh: false)
        var result = try await KimiUsageAPI.fetch(accessToken: token.accessToken, session: session)

        // A token can be revoked before its advertised expiry. Retry exactly once with a
        // forced refresh; repeated 401s become a clear reconnect state rather than a loop.
        if result.statusCode == 401 {
            token = try await tokenManager.accessToken(forceRefresh: true, expectedAccessToken: token.accessToken)
            result = try await KimiUsageAPI.fetch(accessToken: token.accessToken, session: session)
        }

        try Task.checkCancellation()
        guard tokenStore.load(providerId: id) == token else { throw CancellationError() }
        guard result.statusCode != 401 else { throw ProviderAPIError.rejectedCredential("Kimi Code") }
        guard (200...299).contains(result.statusCode) else {
            throw ProviderAPIError.response("Kimi Code", result.statusCode)
        }
        return try Self.snapshot(
            from: result.data,
            providerID: id,
            fetchedAt: Date(),
            planLabel: token.extra["userLevelName"]
        )
    }

    /// Parses Kimi's managed usage payload without inventing a quota when a field is
    /// absent, invalid, or outside the documented 0...1 range.
    static func snapshot(
        from data: Data,
        providerID: String,
        fetchedAt: Date,
        planLabel: String?
    ) throws -> ProviderSnapshot {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ProviderAPIError.malformedResponse("Kimi Code")
        }

        let monthlyReset = usageEntry(root["usages"] as? [String: Any], key: "limit_month_total")?.resetAt
            ?? usageEntry(root["usages"] as? [String: Any], key: "limit_month_code")?.resetAt
        var quotas = subscriptionWindows(from: root["usages"] as? [String: Any])
        quotas.append(contentsOf: walletWindows(from: root["boosterWallet"], monthlyReset: monthlyReset))

        return ProviderSnapshot(
            providerId: providerID,
            fetchedAt: fetchedAt,
            quotas: quotas,
            usageDetail: nil,
            planLabel: planLabel?.nonEmpty,
            connectionNote: quotas.isEmpty
                ? L("O Kimi Code não forneceu cotas utilizáveis da assinatura ou carteira para esta conta.")
                : nil
        )
    }

    private static func subscriptionWindows(from usages: [String: Any]?) -> [QuotaWindow] {
        let specs: [(key: String, label: String, duration: TimeInterval, cadence: RenewalCadence?)] = [
            ("limit_5h", "5h", 5 * 60 * 60, nil),
            ("limit_7d", "7d", 7 * 24 * 60 * 60, .weekly),
            ("limit_month_total", "Monthly total", 30 * 24 * 60 * 60, .monthly),
            ("limit_month_code", "Monthly code", 30 * 24 * 60 * 60, .monthly)
        ]

        return specs.compactMap { spec in
            guard let entry = usageEntry(usages, key: spec.key) else { return nil }
            let start = spec.cadence == .monthly
                ? calendarMonth(before: entry.resetAt) ?? entry.resetAt.addingTimeInterval(-spec.duration)
                : entry.resetAt.addingTimeInterval(-spec.duration)
            return QuotaWindow(
                label: spec.label,
                shape: .rollingWindow(used: entry.usedRatio, limit: 1, windowStart: start, resetAt: entry.resetAt),
                renewalCadence: spec.cadence
            )
        }
    }

    private static func walletWindows(from raw: Any?, monthlyReset: Date?) -> [QuotaWindow] {
        guard let wallet = raw as? [String: Any],
              let balance = wallet["balance"] as? [String: Any],
              balance["type"] as? String == "BOOSTER",
              let total = decimal(balance["amount"]), total > 0,
              let amountLeft = decimal(balance["amountLeft"]), amountLeft >= 0
        else {
            return []
        }

        let currency = money(wallet["monthlyChargeLimit"])?.currency
            ?? money(wallet["monthlyUsed"])?.currency
            ?? "USD"
        // Kimi's integer is fixed-point cents: / 1_000_000 gives cents, and / 100
        // gives the currency-unit Decimal stored by `QuotaShape.creditBalance`.
        let remaining = amountLeft / Decimal(100_000_000)
        var windows = [QuotaWindow(label: "Booster balance", shape: .creditBalance(remaining: remaining, currency: currency))]

        guard wallet["monthlyChargeLimitEnabled"] as? Bool == true,
              let limit = money(wallet["monthlyChargeLimit"]), limit.amount > 0,
              let used = money(wallet["monthlyUsed"]), used.amount >= 0,
              let resetAt = monthlyReset
        else {
            return windows
        }
        // Both `priceInCents` values are cents. Convert to currency units only at the
        // presentation boundary while retaining Decimal precision for the wallet itself.
        windows.append(QuotaWindow(
            label: "Monthly booster spend",
            shape: .periodicCounter(
                used: NSDecimalNumber(decimal: used.amount / 100).doubleValue,
                limit: NSDecimalNumber(decimal: limit.amount / 100).doubleValue,
                resetAt: resetAt
            ),
            renewalCadence: .monthly
        ))
        return windows
    }

    private static func usageEntry(_ usages: [String: Any]?, key: String) -> KimiUsageEntry? {
        guard let raw = usages?[key] as? [String: Any],
              let usedRatio = decimal(raw["used_ratio"]),
              usedRatio >= 0, usedRatio <= 1,
              let resetText = raw["reset_time"] as? String,
              let resetAt = parseISO8601(resetText)
        else {
            return nil
        }
        return KimiUsageEntry(usedRatio: NSDecimalNumber(decimal: usedRatio).doubleValue, resetAt: resetAt)
    }

    private static func money(_ raw: Any?) -> KimiMoney? {
        guard let record = raw as? [String: Any],
              let amount = decimal(record["priceInCents"]), amount >= 0,
              let currency = (record["currency"] as? String)?.nonEmpty
        else {
            return nil
        }
        return KimiMoney(amount: amount, currency: currency)
    }

    private static func decimal(_ value: Any?) -> Decimal? {
        let text: String
        if let number = value as? NSNumber {
            guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            text = number.stringValue
        } else if let string = value as? String {
            text = string
        } else { return nil }
        let scanner = Scanner(string: text)
        scanner.locale = Locale(identifier: "en_US_POSIX")
        var amount = Decimal()
        guard scanner.scanDecimal(&amount), scanner.isAtEnd, !amount.isNaN else { return nil }
        return amount
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func calendarMonth(before date: Date) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(byAdding: .month, value: -1, to: date)
    }
}

private actor KimiTokenManager {
    private let providerID: String
    private let tokenStore: TokenStoring
    private let client: KimiOAuthClient
    private var inFlightRefresh: Task<OAuthToken, Error>?

    init(providerID: String, tokenStore: TokenStoring, session: URLSession) {
        self.providerID = providerID
        self.tokenStore = tokenStore
        self.client = KimiOAuthClient(session: session)
    }

    func accessToken(forceRefresh: Bool, expectedAccessToken: String? = nil) async throws -> OAuthToken {
        guard let current = tokenStore.load(providerId: providerID) else {
            throw ProviderAPIError.missingCredential("Kimi Code")
        }
        if !forceRefresh && !current.isExpired { return current }
        if forceRefresh, let expectedAccessToken, current.accessToken != expectedAccessToken { return current }
        if let inFlightRefresh { return try await inFlightRefresh.value }

        let original = current
        let refresh = Task { try await self.performRefresh(original: original) }
        inFlightRefresh = refresh
        defer { inFlightRefresh = nil }
        return try await refresh.value
    }

    private func performRefresh(original: OAuthToken) async throws -> OAuthToken {
        let refreshed = try await client.refresh(token: original)
        // TokenStoring has no compare-and-swap; full token equality still prevents a late
        // response from recreating a deleted login or overwriting a newer account login.
        guard tokenStore.load(providerId: providerID) == original else { throw CancellationError() }
        try tokenStore.save(refreshed, providerId: providerID)
        return refreshed
    }
}

private enum KimiUsageAPI {
    struct Result {
        let statusCode: Int
        let data: Data
    }

    static func fetch(accessToken: String, session: URLSession) async throws -> Result {
        var request = URLRequest(url: KimiUsageProvider.usageURL, timeoutInterval: 30)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderAPIError.response("Kimi Code", nil)
        }
        return Result(statusCode: http.statusCode, data: data)
    }
}

private struct KimiUsageEntry {
    let usedRatio: Double
    let resetAt: Date
}

private struct KimiMoney {
    let amount: Decimal
    let currency: String
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
