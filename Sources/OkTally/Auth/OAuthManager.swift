import Foundation

struct TokenEndpointResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
    let idToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case idToken = "id_token"
    }
}

enum OAuthError: Error, LocalizedError {
    case tokenExchangeFailed(Int?)
    case noRefreshToken
    case refreshFailed(Int?)
    case loginTimeout
    case portInUse(Int)

    var errorDescription: String? {
        switch self {
        case .tokenExchangeFailed(let code):
            return LF("Falha na troca do código OAuth (código %@).", code.map(String.init) ?? L("desconhecido"))
        case .noRefreshToken:
            return L("Sessão expirada e sem refresh token — entre novamente.")
        case .refreshFailed(let code):
            return LF("Falha ao renovar a sessão (código %@) — entre novamente.", code.map(String.init) ?? L("desconhecido"))
        case .loginTimeout:
            return L("Login expirou — tente novamente.")
        case .portInUse(let port):
            return LF("A porta %d está em uso — feche o outro app que faz login e tente de novo.", port)
        }
    }
}

protocol OAuthManaging {
    func validAccessToken(providerId: String, config: OAuthConfig) async throws -> String
    func exchangeCode(_ code: String, verifier: String, config: OAuthConfig) async throws -> OAuthToken
    func exchangeManualCode(code: String, state: String, verifier: String, config: OAuthConfig) async throws -> OAuthToken
    func refresh(providerId: String, config: OAuthConfig) async throws -> OAuthToken
}

/// Actor, not a class: `validAccessToken`/`refresh` must be serialized per provider.
/// Two overlapping callers hitting the same expired token (e.g. the periodic scheduler
/// loop and a manual "Atualizar agora") would otherwise each fire an independent
/// `POST /token` refresh with the SAME refresh token. OpenAI and Anthropic rotate refresh
/// tokens on use, so the second request consumes an already-invalidated token and the
/// slower response can overwrite the Keychain with a stale (and now-invalid) pair,
/// permanently signing the user out. `refresh(providerId:config:)` below de-duplicates
/// concurrent calls for the same `providerId` onto a single in-flight `Task`.
actor OAuthManager: OAuthManaging {
    private let store: TokenStoring
    private let session: URLSession
    private let now: () -> Date
    private var inFlightRefreshes: [String: Task<OAuthToken, Error>] = [:]

    init(store: TokenStoring, session: URLSession = .shared, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.session = session
        self.now = now
    }

    func validAccessToken(providerId: String, config: OAuthConfig) async throws -> String {
        guard let token = store.load(providerId: providerId) else {
            throw OAuthError.noRefreshToken
        }
        if !token.isExpired { return token.accessToken }
        return try await refresh(providerId: providerId, config: config).accessToken
    }

    func exchangeCode(_ code: String, verifier: String, config: OAuthConfig) async throws -> OAuthToken {
        let form = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": config.redirectURI,
            "client_id": config.clientId,
            "code_verifier": verifier
        ]
        let response = try await postForm(form, to: config.tokenURL, failure: OAuthError.tokenExchangeFailed)
        let token = makeToken(from: response, previousRefresh: nil, previousExtra: extraClaims(from: response))
        try store.save(token, providerId: config.providerId)
        return token
    }

    /// Exchange for providers whose OAuth app uses a FIXED hosted redirect (not loopback)
    /// and hands the user a `CODE#STATE` string to paste back — currently Claude. The
    /// token endpoint expects a JSON body carrying `state`, unlike the form-encoded
    /// loopback exchange above.
    func exchangeManualCode(code: String, state: String, verifier: String, config: OAuthConfig) async throws -> OAuthToken {
        let body = [
            "grant_type": "authorization_code",
            "code": code,
            "state": state,
            "client_id": config.clientId,
            "redirect_uri": config.redirectURI,
            "code_verifier": verifier
        ]
        let response = try await postJSON(body, to: config.tokenURL, failure: OAuthError.tokenExchangeFailed)
        let token = makeToken(from: response, previousRefresh: nil, previousExtra: extraClaims(from: response))
        try store.save(token, providerId: config.providerId)
        return token
    }

    /// De-duplicates concurrent refreshes for the same `providerId`: a second caller that
    /// arrives while a refresh is already in flight awaits that SAME task instead of
    /// starting a new one, so the (single-use, rotating) refresh token is only ever
    /// consumed once per cycle.
    func refresh(providerId: String, config: OAuthConfig) async throws -> OAuthToken {
        if let inFlight = inFlightRefreshes[providerId] {
            return try await inFlight.value
        }
        let task = Task { try await self.performRefresh(providerId: providerId, config: config) }
        inFlightRefreshes[providerId] = task
        defer { inFlightRefreshes[providerId] = nil }
        return try await task.value
    }

    private func performRefresh(providerId: String, config: OAuthConfig) async throws -> OAuthToken {
        guard let existing = store.load(providerId: providerId), let refreshToken = existing.refreshToken else {
            throw OAuthError.noRefreshToken
        }
        let form = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": config.clientId
        ]
        let response = try await postForm(form, to: config.tokenURL, failure: OAuthError.refreshFailed)
        var extra = existing.extra
        extra.merge(extraClaims(from: response)) { _, new in new }
        let token = makeToken(from: response, previousRefresh: refreshToken, previousExtra: extra)
        try store.save(token, providerId: providerId)
        return token
    }

    /// Best-effort extraction of known auxiliary claims from the token response's
    /// `id_token` (a JWT), if present. Currently understands OpenAI's
    /// `https://api.openai.com/auth.chatgpt_account_id` claim, needed to send the
    /// `ChatGPT-Account-Id` header for multi-workspace ChatGPT accounts. Decoding is
    /// entirely best-effort: any failure (no id_token, malformed JWT, missing claim)
    /// simply yields no extra entries — the access token remains valid regardless.
    private func extraClaims(from response: TokenEndpointResponse) -> [String: String] {
        guard let idToken = response.idToken, let payload = JWT.decodePayload(idToken) else { return [:] }
        var extra: [String: String] = [:]
        if let authClaim = payload["https://api.openai.com/auth"] as? [String: Any],
           let accountId = authClaim["chatgpt_account_id"] as? String {
            extra["account_id"] = accountId
        }
        return extra
    }

    private func makeToken(from response: TokenEndpointResponse, previousRefresh: String?, previousExtra: [String: String] = [:]) -> OAuthToken {
        let expiresAt = response.expiresIn.map { now().addingTimeInterval(TimeInterval($0)) }
        return OAuthToken(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? previousRefresh,
            expiresAt: expiresAt,
            extra: previousExtra
        )
    }

    private func postForm(_ form: [String: String], to url: URL, failure: (Int?) -> OAuthError) async throws -> TokenEndpointResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? $0.value)" }
            .joined(separator: "&").data(using: .utf8)
        let (data, urlResponse) = try await session.data(for: request)
        guard let http = urlResponse as? HTTPURLResponse, http.statusCode == 200 else {
            throw failure((urlResponse as? HTTPURLResponse)?.statusCode)
        }
        return try JSONDecoder().decode(TokenEndpointResponse.self, from: data)
    }

    private func postJSON(_ body: [String: String], to url: URL, failure: (Int?) -> OAuthError) async throws -> TokenEndpointResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, urlResponse) = try await session.data(for: request)
        guard let http = urlResponse as? HTTPURLResponse, http.statusCode == 200 else {
            throw failure((urlResponse as? HTTPURLResponse)?.statusCode)
        }
        return try JSONDecoder().decode(TokenEndpointResponse.self, from: data)
    }
}

private extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=+")
        return set
    }()
}
