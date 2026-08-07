// Sources/OkTally/Plugins/SuperGrok/SuperGrokAPIClient.swift
import Foundation

/// A resolved usage snapshot for the SuperGrok/Grok Build weekly credit pool.
struct SuperGrokUsageSnapshot: Equatable {
    /// `nil` when the proxy omits the field, which per xAI's own community
    /// tooling means "0%" (proto/JSON omits zero values) — callers should
    /// treat `nil` as 0, not "unknown". Kept optional here so the provider
    /// layer decides how to render an absent value.
    let creditUsagePercent: Double?
    let resetAt: Date?
}

enum SuperGrokUsageError: Error, LocalizedError {
    case badResponse(Int?)
    case invalidIdentity

    var errorDescription: String? {
        switch self {
        case .badResponse(let code):
            return "SuperGrok respondeu com erro (código \(code.map(String.init) ?? "desconhecido"))."
        case .invalidIdentity:
            return "Não foi possível confirmar a identidade da conta SuperGrok."
        }
    }
}

protocol SuperGrokUsageFetching {
    func fetchUsage(accessToken: String) async throws -> SuperGrokUsageSnapshot
}

/// Talks to the unofficial `cli-chat-proxy.grok.com` proxy that the official
/// Grok CLI (and community OAuth clients pi-grok / pi-xai-oauth) use to read
/// Grok Build's weekly credit pool. There is no officially documented xAI
/// usage API (see docs/superpowers/research/plan2-supergrok.md); these two
/// calls are pinned from working, production client code, not guessed:
///   - GET  /v1/user                    (resolves the account's userId)
///   - GET  /v1/billing?format=credits  (creditUsagePercent + period, keyed
///           to that userId via the `x-userid` header)
/// Source: github.com/stnly/pi-grok, account.ts:82 + usage.ts:345-380;
/// github.com/BlockedPath/pi-xai-oauth, extensions/xai/constants.ts:28-29.
final class SuperGrokAPIClient: SuperGrokUsageFetching {
    private static let baseURL = URL(string: "https://cli-chat-proxy.grok.com/v1")!

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchUsage(accessToken: String) async throws -> SuperGrokUsageSnapshot {
        let userId = try await fetchUserId(accessToken: accessToken)
        return try await fetchBilling(accessToken: accessToken, userId: userId)
    }

    private func proxyHeaders(accessToken: String) -> [String: String] {
        [
            "Authorization": "Bearer \(accessToken)",
            "X-XAI-Token-Auth": "xai-grok-cli",
            "x-authenticateresponse": "authenticate-response"
        ]
    }

    private struct UserResponse: Decodable {
        let userId: String
    }

    private func fetchUserId(accessToken: String) async throws -> String {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("user"))
        proxyHeaders(accessToken: accessToken).forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SuperGrokUsageError.badResponse((response as? HTTPURLResponse)?.statusCode)
        }
        guard let decoded = try? JSONDecoder().decode(UserResponse.self, from: data), !decoded.userId.isEmpty else {
            throw SuperGrokUsageError.invalidIdentity
        }
        return decoded.userId
    }

    private struct BillingPeriod: Decodable {
        let start: Date?
        let end: Date?
    }

    private struct BillingConfig: Decodable {
        let creditUsagePercent: Double?
        let currentPeriod: BillingPeriod?
        let billingPeriodStart: Date?
        let billingPeriodEnd: Date?
    }

    private struct BillingResponse: Decodable {
        let config: BillingConfig?
    }

    private func fetchBilling(accessToken: String, userId: String) async throws -> SuperGrokUsageSnapshot {
        var components = URLComponents(url: Self.baseURL.appendingPathComponent("billing"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "format", value: "credits")]

        var request = URLRequest(url: components.url!)
        proxyHeaders(accessToken: accessToken).forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.setValue(userId, forHTTPHeaderField: "x-userid")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SuperGrokUsageError.badResponse((response as? HTTPURLResponse)?.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode(BillingResponse.self, from: data) else {
            throw SuperGrokUsageError.badResponse(http.statusCode)
        }

        let config = decoded.config
        let resetAt = config?.currentPeriod?.end ?? config?.billingPeriodEnd
        return SuperGrokUsageSnapshot(creditUsagePercent: config?.creditUsagePercent, resetAt: resetAt)
    }
}
