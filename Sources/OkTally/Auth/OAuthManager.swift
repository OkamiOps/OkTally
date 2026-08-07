import Foundation

struct TokenEndpointResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

enum OAuthError: Error, LocalizedError {
    case tokenExchangeFailed(Int?)
    case noRefreshToken
    case refreshFailed(Int?)

    var errorDescription: String? {
        switch self {
        case .tokenExchangeFailed(let code):
            return "Falha na troca do código OAuth (código \(code.map(String.init) ?? "desconhecido"))."
        case .noRefreshToken:
            return "Sessão expirada e sem refresh token — entre novamente."
        case .refreshFailed(let code):
            return "Falha ao renovar a sessão (código \(code.map(String.init) ?? "desconhecido")) — entre novamente."
        }
    }
}

protocol OAuthManaging {
    func validAccessToken(providerId: String, config: OAuthConfig) async throws -> String
    func exchangeCode(_ code: String, verifier: String, config: OAuthConfig) async throws -> OAuthToken
    func refresh(providerId: String, config: OAuthConfig) async throws -> OAuthToken
}

final class OAuthManager: OAuthManaging {
    private let store: TokenStoring
    private let session: URLSession
    private let now: () -> Date

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
        let token = makeToken(from: response, previousRefresh: nil)
        try store.save(token, providerId: config.providerId)
        return token
    }

    func refresh(providerId: String, config: OAuthConfig) async throws -> OAuthToken {
        guard let existing = store.load(providerId: providerId), let refreshToken = existing.refreshToken else {
            throw OAuthError.noRefreshToken
        }
        let form = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": config.clientId
        ]
        let response = try await postForm(form, to: config.tokenURL, failure: OAuthError.refreshFailed)
        let token = makeToken(from: response, previousRefresh: refreshToken, previousExtra: existing.extra)
        try store.save(token, providerId: providerId)
        return token
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
}

private extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=+")
        return set
    }()
}
