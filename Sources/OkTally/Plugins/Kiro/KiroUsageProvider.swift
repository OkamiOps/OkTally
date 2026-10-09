import Foundation

enum KiroSessionImportError: Error, LocalizedError {
    case ideImportUnsupported

    var errorDescription: String? {
        switch self {
        case .ideImportUnsupported:
            return L("O IDE Kiro não oferece uma sessão copiável com segurança. Importe a sessão pelo Kiro CLI.")
        }
    }
}

/// Importa uma cópia independente da sessão global do Kiro CLI. Nada nesta operação
/// escreve no banco do Kiro: até uma renovação de token fica apenas em memória, e o
/// chamador decide se a cópia validada será guardada no Keychain do OkTally.
final class KiroSessionImporter: KiroSessionImporting {
    private let reader: KiroSessionReading
    private let session: URLSession
    private let now: () -> Date

    init(reader: KiroSessionReading = KiroSessionReader(), session: URLSession = .shared, now: @escaping () -> Date = Date.init) {
        self.reader = reader
        self.session = session
        self.now = now
    }

    func importSession(source: KiroSessionSource) async throws -> OAuthToken {
        guard source == .cli else { throw KiroSessionImportError.ideImportUnsupported }
        let copied = try reader.readCLISession()
        var token = Self.token(from: copied)
        var refreshed = false
        if token.isExpired {
            token = try await KiroAPI.refresh(token: token, session: session, now: now)
            refreshed = true
        }
        var usage = try await KiroAPI.fetchUsage(accessToken: token.accessToken, profileArn: copied.profileArn, session: session)
        if usage.statusCode == 401, !refreshed {
            token = try await KiroAPI.refresh(token: token, session: session, now: now)
            usage = try await KiroAPI.fetchUsage(accessToken: token.accessToken, profileArn: copied.profileArn, session: session)
        }
        guard usage.statusCode != 401 else { throw ProviderAPIError.rejectedCredential("Kiro") }
        guard (200...299).contains(usage.statusCode), let response = usage.response else {
            throw ProviderAPIError.response("Kiro", usage.statusCode)
        }
        guard !response.validQuotaWindows.isEmpty else {
            throw ProviderAPIError.malformedResponse("Kiro")
        }

        var extra = token.extra
        if let email = response.userInfo?.email?.nonEmpty { extra["email"] = email }
        if let userId = response.userInfo?.userId?.nonEmpty { extra["userId"] = userId }
        // O perfil local é a fonte do nome. Não trocamos por um valor inferido da API.
        token = OAuthToken(accessToken: token.accessToken, refreshToken: token.refreshToken, expiresAt: token.expiresAt, extra: extra)
        try KiroAccountImport.validate(token, replacing: nil)
        return token
    }

    private static func token(from session: KiroCLISession) -> OAuthToken {
        var extra: [String: String] = [
            "profileArn": session.profileArn,
            "region": session.oidcRegion,
            "clientId": session.clientId,
            "clientSecret": session.clientSecret,
            "authMethod": "oidc"
        ]
        if let startURL = session.startURL?.nonEmpty { extra["startURL"] = startURL }
        if let profileName = session.profileName?.nonEmpty { extra["profileName"] = profileName }
        if let expires = session.clientSecretExpiresAt {
            extra["clientSecretExpiresAt"] = String(Int64(expires.timeIntervalSince1970))
        }
        return OAuthToken(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            expiresAt: session.expiresAt,
            extra: extra
        )
    }
}

/// O provider trabalha exclusivamente com a cópia do Keychain dessa instância. O CLI
/// nunca é relido depois da importação, o que permite monitorar contas diferentes sem a
/// sessão global de uma substituir a outra.
final class KiroUsageProvider: UsageProvider {
    let id: String
    let displayName = "Kiro"
    let authMethod: AuthMethod
    let refreshInterval: TimeInterval = 300

    private let tokenStore: TokenStoring
    private let session: URLSession
    private let tokenManager: KiroTokenManager
    private let now: () -> Date

    init(
        instanceId: String = AccountKind.kiro.rawValue,
        tokenStore: TokenStoring,
        session: URLSession = .shared,
        now: @escaping () -> Date = Date.init
    ) {
        self.id = instanceId
        self.authMethod = .oauthSession
        self.tokenStore = tokenStore
        self.session = session
        self.now = now
        self.tokenManager = KiroTokenManager(providerId: instanceId, tokenStore: tokenStore, session: session, now: now)
    }

    func isAuthenticated() async -> Bool {
        tokenStore.load(providerId: id) != nil
    }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        var token = try await tokenManager.accessToken(forceRefresh: false)
        var result = try await KiroAPI.fetchUsage(accessToken: token.accessToken, profileArn: token.extra["profileArn"], session: session)

        // Um access token revogado antes do vencimento merece uma única renovação
        // forçada. Se a segunda consulta continuar em 401, não entramos em loop.
        if result.statusCode == 401 {
            token = try await tokenManager.accessToken(forceRefresh: true, expectedAccessToken: token.accessToken)
            result = try await KiroAPI.fetchUsage(accessToken: token.accessToken, profileArn: token.extra["profileArn"], session: session)
        }

        try Task.checkCancellation()
        guard tokenStore.load(providerId: id) == token else { throw CancellationError() }
        guard result.statusCode != 401 else { throw ProviderAPIError.rejectedCredential("Kiro") }
        guard (200...299).contains(result.statusCode), let response = result.response else {
            throw ProviderAPIError.response("Kiro", result.statusCode)
        }

        let quotas = response.validQuotaWindows
        guard !quotas.isEmpty else { throw ProviderAPIError.malformedResponse("Kiro") }
        return ProviderSnapshot(
            providerId: id,
            fetchedAt: now(),
            quotas: quotas,
            usageDetail: nil,
            planLabel: response.subscriptionInfo?.subscriptionTitle?.nonEmpty
        )
    }
}

/// Single-flight por AccountID. Além de impedir o consumo duplicado de refresh tokens
/// rotativos, o `stillStored == original` antes do save evita que uma resposta atrasada
/// ressuscite uma conta removida ou substitua um login novo.
private actor KiroTokenManager {
    private let providerId: String
    private let tokenStore: TokenStoring
    private let session: URLSession
    private let now: () -> Date
    private var inFlightRefresh: Task<OAuthToken, Error>?

    init(providerId: String, tokenStore: TokenStoring, session: URLSession, now: @escaping () -> Date) {
        self.providerId = providerId
        self.tokenStore = tokenStore
        self.session = session
        self.now = now
    }

    func accessToken(forceRefresh: Bool, expectedAccessToken: String? = nil) async throws -> OAuthToken {
        guard let current = tokenStore.load(providerId: providerId) else {
            throw ProviderAPIError.missingCredential("Kiro")
        }
        if !forceRefresh && !current.isExpired { return current }
        // Dois polls podem receber 401 para o mesmo access token. Se o primeiro já
        // renovou e gravou outro, o segundo usa a cópia nova em vez de gastar de novo o
        // refresh token rotativo só porque sua resposta 401 chegou um pouco depois.
        if forceRefresh, let expectedAccessToken, current.accessToken != expectedAccessToken {
            return current
        }
        if let inFlightRefresh { return try await inFlightRefresh.value }

        let original = current
        let refresh = Task { try await self.performRefresh(original: original) }
        inFlightRefresh = refresh
        defer { inFlightRefresh = nil }
        return try await refresh.value
    }

    private func performRefresh(original: OAuthToken) async throws -> OAuthToken {
        let refreshed = try await KiroAPI.refresh(token: original, session: session, now: now)
        // `TokenStoring` não tem compare-and-swap, mas igualdade do bundle inteiro é
        // suficiente para impedir escrita após delete/reimport/login novo.
        guard tokenStore.load(providerId: providerId) == original else { throw CancellationError() }
        try tokenStore.save(refreshed, providerId: providerId)
        return refreshed
    }
}

private enum KiroAPI {
    struct UsageResult {
        let statusCode: Int
        let response: KiroUsageResponse?
    }

    static func fetchUsage(accessToken: String, profileArn: String?, session: URLSession) async throws -> UsageResult {
        guard let profileArn, let url = usageURL(profileArn: profileArn) else {
            throw ProviderAPIError.malformedResponse("Kiro")
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, urlResponse) = try await session.data(for: request)
        guard let http = urlResponse as? HTTPURLResponse else {
            throw ProviderAPIError.response("Kiro", nil)
        }
        guard (200...299).contains(http.statusCode) else {
            return UsageResult(statusCode: http.statusCode, response: nil)
        }
        guard let decoded = try? JSONDecoder().decode(KiroUsageResponse.self, from: data) else {
            throw ProviderAPIError.malformedResponse("Kiro")
        }
        return UsageResult(statusCode: http.statusCode, response: decoded)
    }

    static func refresh(token: OAuthToken, session: URLSession, now: @escaping () -> Date) async throws -> OAuthToken {
        guard let refreshToken = token.refreshToken?.nonEmpty,
              let clientId = token.extra["clientId"]?.nonEmpty,
              let clientSecret = token.extra["clientSecret"]?.nonEmpty,
              let region = token.extra["region"]?.nonEmpty,
              let url = oidcTokenURL(region: region)
        else {
            throw OAuthError.noRefreshToken
        }

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "clientId": clientId,
            "clientSecret": clientSecret,
            "grantType": "refresh_token",
            "refreshToken": refreshToken
        ])
        let (data, urlResponse) = try await session.data(for: request)
        guard let http = urlResponse as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OAuthError.refreshFailed((urlResponse as? HTTPURLResponse)?.statusCode)
        }
        guard let response = try? JSONDecoder().decode(KiroRefreshResponse.self, from: data),
              let accessToken = response.accessToken.nonEmpty
        else {
            throw OAuthError.refreshFailed(http.statusCode)
        }

        return OAuthToken(
            accessToken: accessToken,
            refreshToken: response.refreshToken?.nonEmpty ?? refreshToken,
            expiresAt: response.expiresIn.map { now().addingTimeInterval(TimeInterval($0)) },
            extra: token.extra
        )
    }

    /// Região do control plane = parte regional do profile ARN. A região OIDC do token
    /// não entra nesta URL: elas podem ser diferentes. O host é sempre construído de
    /// partes validadas e termina em domínio oficial, sem aceitar URL do banco local.
    static func usageURL(profileArn: String) -> URL? {
        guard let region = controlPlaneRegion(profileArn: profileArn) else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "management.\(region).kiro.dev"
        components.path = "/Get-Usage-Limits"
        components.queryItems = [
            URLQueryItem(name: "profileArn", value: profileArn),
            URLQueryItem(name: "origin", value: "KIRO_CLI"),
            URLQueryItem(name: "isEmailRequired", value: "true")
        ]
        return components.url
    }

    static func oidcTokenURL(region: String) -> URL? {
        guard isOfficialAWSRegion(region) else { return nil }
        return URL(string: "https://oidc.\(region).amazonaws.com/token")
    }

    private static func controlPlaneRegion(profileArn: String) -> String? {
        let parts = profileArn.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 6,
              parts[0] == "arn",
              parts[1] == "aws",
              parts[2] == "codewhisperer",
              parts[5].hasPrefix("profile/"),
              !parts[5].dropFirst("profile/".count).isEmpty
        else { return nil }
        let region = String(parts[3])
        return isOfficialAWSRegion(region) ? region : nil
    }

    private static func isOfficialAWSRegion(_ region: String) -> Bool {
        let expression = "^(?:af|ap|ca|cn|eu|il|me|sa|us)-(?:[a-z]+-){1,2}[0-9]+$"
        return region.range(of: expression, options: .regularExpression) != nil
    }
}

private struct KiroRefreshResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?

    // AWS SSO OIDC CreateToken uses camelCase on the wire. The CLI's SQLite
    // representation is snake_case, but that storage schema is not this API.
}

private struct KiroUsageResponse: Decodable {
    struct UsageBreakdown: Decodable {
        let resourceType: String?
        let displayName: String?
        let currentUsage: Double?
        let currentUsageWithPrecision: Double?
        let usageLimit: Double?
        let usageLimitWithPrecision: Double?
        let nextDateReset: Double?
    }

    struct SubscriptionInfo: Decodable {
        let subscriptionTitle: String?
    }

    struct UserInfo: Decodable {
        let userId: String?
        let email: String?
    }

    let usageBreakdownList: [UsageBreakdown]?
    let subscriptionInfo: SubscriptionInfo?
    let userInfo: UserInfo?

    var validQuotaWindows: [QuotaWindow] {
        (usageBreakdownList ?? []).compactMap { breakdown in
            // Valores de precisão são autoritativos quando existem. Fallback para os
            // inteiros é só compatibilidade de payload, nunca porcentagem inventada.
            guard let used = breakdown.currentUsageWithPrecision ?? breakdown.currentUsage,
                  let limit = breakdown.usageLimitWithPrecision ?? breakdown.usageLimit,
                  limit.isFinite, limit > 0,
                  used.isFinite, used >= 0,
                  let resetSeconds = breakdown.nextDateReset,
                  resetSeconds.isFinite, resetSeconds > 0
            else { return nil }
            let label = breakdown.displayName?.nonEmpty ?? breakdown.resourceType?.nonEmpty ?? "Kiro"
            return QuotaWindow(
                label: label,
                shape: .periodicCounter(
                    used: used,
                    limit: limit,
                    // Contrato do Kiro usa epoch em segundos, não milissegundos.
                    resetAt: Date(timeIntervalSince1970: resetSeconds)
                ),
                renewalCadence: .monthly
            )
        }
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
