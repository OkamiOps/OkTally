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
/// no `state.vscdb`, renova o access token no OAuth da Google e consulta o Cloud Code —
/// grupos "Gemini" e "Claude/GPT", cada um com janelas de 5h e semanal.
///
/// Antigravity 2.x mudou o contrato visto em 2026-08-12: além do OAuth, o Cloud Code
/// exige o `cloudaicompanionProject` da conta. Chamadas sem projeto podem responder 200
/// com quotas artificialmente cheias. Também consultamos os hosts daily/sandbox/produção
/// e escolhemos o MAIOR uso observado por bucket — o host errado tende a omitir consumo,
/// nunca a inventar consumo maior.
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
    private var cachedProject: String?

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

        let project = try await cloudProject(accessToken: accessToken)
        var summaries: [Data] = []
        var lastStatus = 0
        for base in AntigravityOAuth.cloudCodeBases {
            do {
                let (data, http) = try await postJSON(
                    AntigravityOAuth.summaryURL(base: base),
                    body: ["project": project],
                    accessToken: accessToken
                )
                if http.statusCode == 401 || http.statusCode == 403 { throw AntigravityError.tokenRejected }
                if (200...299).contains(http.statusCode) {
                    summaries.append(data)
                } else {
                    lastStatus = http.statusCode
                }
            } catch AntigravityError.tokenRejected {
                throw AntigravityError.tokenRejected
            } catch {
                // Host individual fora do ar não derruba a coleta: os demais ainda valem.
            }
        }
        let now = Date()
        let windows = Self.windows(fromSummaries: summaries, now: now)
        guard !windows.isEmpty else {
            if summaries.isEmpty, lastStatus != 0 { throw AntigravityError.badResponse(lastStatus) }
            throw ProviderAPIError.malformedResponse("Antigravity")
        }
        return ProviderSnapshot(providerId: id, fetchedAt: now, quotas: windows, usageDetail: nil)
    }

    // MARK: - Cloud Code

    private func cloudProject(accessToken: String) async throws -> String {
        if let cachedProject { return cachedProject }
        var lastStatus = 0
        for base in AntigravityOAuth.cloudCodeBases {
            do {
                let (data, http) = try await postJSON(
                    AntigravityOAuth.loadCodeAssistURL(base: base),
                    body: ["metadata": ["ideType": "ANTIGRAVITY"]],
                    accessToken: accessToken
                )
                if http.statusCode == 401 || http.statusCode == 403 { throw AntigravityError.tokenRejected }
                guard (200...299).contains(http.statusCode) else {
                    lastStatus = http.statusCode
                    continue
                }
                if let root = TolerantJSON.object(data: data),
                   let project = TolerantJSON.string(in: root, camel: "cloudaicompanionProject")
                    ?? TolerantJSON.string(TolerantJSON.deepValue(for: "cloudaicompanionProject", in: root))
                    ?? TolerantJSON.string(TolerantJSON.deepValue(for: "cloudaicompanion_project", in: root)),
                   !project.isEmpty {
                    cachedProject = project
                    return project
                }
            } catch AntigravityError.tokenRejected {
                throw AntigravityError.tokenRejected
            } catch {
                // Tenta o próximo host.
            }
        }
        if lastStatus != 0 { throw AntigravityError.badResponse(lastStatus) }
        throw ProviderAPIError.malformedResponse("Antigravity")
    }

    private func postJSON(_ url: URL, body: [String: Any], accessToken: String) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(AntigravityOAuth.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AntigravityError.badResponse(0) }
        return (data, http)
    }

    // MARK: - OAuth refresh

    private func validAccessToken(refreshToken: String, fallback: String) async throws -> String {
        if let cachedAccess, cachedAccess.expiresAt > Date().addingTimeInterval(60) {
            return cachedAccess.token
        }
        var request = URLRequest(url: AntigravityOAuth.config.tokenURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
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

    /// Resposta viva: `groups[] { displayName, buckets[] { bucketId, window
    /// ("5h"/"weekly"), resetTime ISO8601, remainingFraction 0…1 } }`. Decode tolerante:
    /// bucket sem fração ou com forma inesperada é pulado, nunca derruba o fetch.
    static func windows(fromSummary data: Data, now: Date) -> [QuotaWindow] {
        windows(fromSummaries: [data], now: now)
    }

    /// Combina respostas dos hosts. Como o host errado omite consumo (remaining=1), o
    /// maior `used` de cada janela semântica é o mais conservador e o mais próximo do IDE.
    static func windows(fromSummaries datas: [Data], now: Date) -> [QuotaWindow] {
        var best: [String: QuotaWindow] = [:]
        for data in datas {
            for window in windowsFromOneSummary(data, now: now) {
                if let existing = best[window.label],
                   (existing.shape.usedPercent ?? -1) >= (window.shape.usedPercent ?? -1) {
                    continue
                }
                best[window.label] = window
            }
        }
        let canonicalOrder = ["Gemini (5h)", "Gemini (weekly)", "Claude/GPT (5h)", "Claude/GPT (weekly)"]
        return best.values.sorted { lhs, rhs in
            let left = canonicalOrder.firstIndex(of: lhs.label) ?? canonicalOrder.count
            let right = canonicalOrder.firstIndex(of: rhs.label) ?? canonicalOrder.count
            return left == right ? lhs.label < rhs.label : left < right
        }
    }

    private static func windowsFromOneSummary(_ data: Data, now: Date) -> [QuotaWindow] {
        guard var root = TolerantJSON.object(data: data) else { return [] }
        if root["groups"] == nil, let response = TolerantJSON.object(root["response"]) { root = response }
        guard let groups = TolerantJSON.array(root["groups"]) else { return [] }

        var windows: [QuotaWindow] = []
        for group in groups {
            for bucket in TolerantJSON.array(group["buckets"]) ?? [] {
                guard let remainingFraction = TolerantJSON.number(TolerantJSON.deepValue(for: "remainingFraction", in: bucket)),
                      (0...1).contains(remainingFraction) else { continue }
                let bucketId = TolerantJSON.string(in: bucket, camel: "bucketId") ?? ""
                guard let groupLabel = Self.groupLabel(
                    displayName: TolerantJSON.string(in: group, camel: "displayName") ?? "",
                    bucketId: bucketId
                ) else { continue }
                let windowKind = (TolerantJSON.string(in: bucket, camel: "window") ?? bucketId).lowercased()
                let isWeekly = windowKind.contains("week")
                let label = "\(groupLabel) (\(isWeekly ? "weekly" : "5h"))"
                let windowLength: TimeInterval = isWeekly ? 7 * 24 * 3600 : 5 * 3600
                let resetAt = TolerantJSON.isoDate(TolerantJSON.value(in: bucket, camel: "resetTime"))
                    ?? now.addingTimeInterval(windowLength)
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

    private static func groupLabel(displayName: String, bucketId: String) -> String? {
        let lower = (displayName + " " + bucketId).lowercased()
        if lower.contains("gemini") { return "Gemini" }
        if lower.contains("claude") || lower.contains("gpt") || lower.contains("3p-") { return "Claude/GPT" }
        return nil
    }
}
