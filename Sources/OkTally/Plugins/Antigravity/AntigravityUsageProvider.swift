// Sources/OkTally/Plugins/Antigravity/AntigravityUsageProvider.swift
import Foundation

enum AntigravityError: Error, Equatable {
    case notDetected
    case tokenRejected
    case badResponse(Int)
}

extension AntigravityError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notDetected:
            return L("Antigravity não detectado — instale/entre no IDE Antigravity para acompanhar o uso.")
        case .tokenRejected:
            return L("Login do Antigravity recusado — entre novamente no IDE.")
        case .badResponse(let status):
            return LF("Antigravity respondeu HTTP %d.", status)
        }
    }
}

/// Antigravity (IDE da Google). A conta legada é zero-config: lê o login que o IDE guarda
/// no `state.vscdb`, renova o access token no OAuth da Google e consulta o
/// `retrieveUserQuotaSummary` do Cloud Code — grupos "Gemini" e "Claude/GPT", cada um
/// com janelas de 5h e semanal. Cadeia inteira confirmada ao vivo em 2026-08-12.
///
/// Contas extras não têm IDE para ler: usam o login Google próprio do OkTally
/// (`AntigravityOAuth.config`), com o token no Keychain sob o id da conta.
final class AntigravityUsageProvider: UsageProvider {
    let id: String
    let displayName = "Antigravity"
    let authMethod: AuthMethod = .localFile(path: "~/Library/Application Support/Antigravity")
    let refreshInterval: TimeInterval = 600

    /// De onde vem a credencial: o login do IDE (conta legada) ou o login próprio do
    /// OkTally (contas extras, via `OAuthManager`).
    enum CredentialSource {
        case ide(AntigravityTokenReading)
        case appOwned(OAuthManaging, TokenStoring)
    }

    private let source: CredentialSource
    private let session: URLSession
    /// Access token renovado, cacheado até perto do vencimento para não bater no
    /// endpoint de token a cada poll.
    private var cachedAccess: (token: String, expiresAt: Date)?

    init(
        instanceId: String = AccountKind.antigravity.rawValue,
        tokenReader: AntigravityTokenReading = AntigravityTokenReader(),
        session: URLSession = .shared
    ) {
        self.id = instanceId
        self.source = .ide(tokenReader)
        self.session = session
    }

    /// Conta extra: login Google próprio, token no Keychain sob `instanceId`.
    init(instanceId: String, oauthManager: OAuthManaging, tokenStore: TokenStoring, session: URLSession = .shared) {
        self.id = instanceId
        self.source = .appOwned(oauthManager, tokenStore)
        self.session = session
    }

    func isAuthenticated() async -> Bool {
        switch source {
        case .ide(let reader): return reader.readTokens() != nil
        case .appOwned(_, let store): return store.load(providerId: id) != nil
        }
    }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        let accessToken: String
        switch source {
        case .ide(let reader):
            guard let tokens = reader.readTokens() else { throw AntigravityError.notDetected }
            accessToken = try await validAccessToken(refreshToken: tokens.refreshToken, fallback: tokens.accessToken)
        case .appOwned(let manager, let store):
            guard store.load(providerId: id) != nil else { throw AntigravityError.notDetected }
            // A Google não gira o refresh token; o `OAuthManager` mantém o anterior quando
            // a resposta do refresh não traz um novo.
            accessToken = try await manager.validAccessToken(providerId: id, config: AntigravityOAuth.config.forInstance(id))
        }

        var request = URLRequest(url: AntigravityOAuth.summaryURL)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(AntigravityOAuth.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AntigravityError.badResponse(0) }
        if http.statusCode == 401 || http.statusCode == 403 { throw AntigravityError.tokenRejected }
        guard (200...299).contains(http.statusCode) else { throw AntigravityError.badResponse(http.statusCode) }

        let now = Date()
        return ProviderSnapshot(
            providerId: id,
            fetchedAt: now,
            quotas: Self.windows(fromSummary: data, now: now),
            usageDetail: nil
        )
    }

    // MARK: - OAuth refresh

    private func validAccessToken(refreshToken: String, fallback: String) async throws -> String {
        if let cachedAccess, cachedAccess.expiresAt > Date().addingTimeInterval(60) {
            return cachedAccess.token
        }
        var request = URLRequest(url: AntigravityOAuth.config.tokenURL)
        request.httpMethod = "POST"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "client_id": AntigravityOAuth.clientId,
            "client_secret": AntigravityOAuth.clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ].map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)" }
            .joined(separator: "&")
        request.httpBody = Data(body.utf8)

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse
        else {
            // Sem rede para renovar: tenta o access token que o IDE deixou — pode ainda
            // estar válido.
            return fallback
        }
        if http.statusCode == 400 || http.statusCode == 401 { throw AntigravityError.tokenRejected }
        guard (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String
        else { return fallback }
        let expiresIn = (json["expires_in"] as? Double) ?? 3600
        cachedAccess = (token, Date().addingTimeInterval(expiresIn))
        return token
    }

    // MARK: - Mapping

    /// Resposta viva (2026-08-12): `groups[] { displayName, buckets[] { bucketId,
    /// window ("5h"/"weekly"), resetTime ISO8601, remainingFraction 0…1 } }`. Decode
    /// tolerante: bucket sem fração ou com forma inesperada é pulado, nunca derruba o
    /// fetch.
    static func windows(fromSummary data: Data, now: Date) -> [QuotaWindow] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let groups = root["groups"] as? [[String: Any]] else { return [] }

        let iso = ISO8601DateFormatter()
        var windows: [QuotaWindow] = []
        for group in groups {
            guard let groupLabel = Self.groupLabel(group["displayName"] as? String ?? "") else { continue }
            for bucket in (group["buckets"] as? [[String: Any]]) ?? [] {
                guard let remainingFraction = bucket["remainingFraction"] as? Double
                        ?? (bucket["remainingFraction"] as? Int).map(Double.init) else { continue }
                let windowKind = (bucket["window"] as? String ?? bucket["bucketId"] as? String ?? "").lowercased()
                let isWeekly = windowKind.contains("week")
                let label = "\(groupLabel) (\(isWeekly ? "weekly" : "5h"))"
                let windowLength: TimeInterval = isWeekly ? 7 * 24 * 3600 : 5 * 3600
                let resetAt = (bucket["resetTime"] as? String).flatMap { iso.date(from: $0) } ?? now.addingTimeInterval(windowLength)
                let used = min(100, max(0, (1 - remainingFraction) * 100))
                windows.append(QuotaWindow(label: label, shape: .rollingWindow(
                    used: used, limit: 100,
                    windowStart: resetAt.addingTimeInterval(-windowLength),
                    resetAt: resetAt
                ), renewalCadence: isWeekly ? .weekly : nil))
            }
        }
        return windows
    }

    private static func groupLabel(_ displayName: String) -> String? {
        let lower = displayName.lowercased()
        if lower.contains("gemini") { return "Gemini" }
        if lower.contains("claude") || lower.contains("gpt") { return "Claude/GPT" }
        return nil
    }
}
