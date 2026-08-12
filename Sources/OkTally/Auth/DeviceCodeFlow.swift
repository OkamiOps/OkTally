// Sources/OkTally/Auth/DeviceCodeFlow.swift
import Foundation

/// Configuration for an OAuth 2.0 Device Authorization Grant (RFC 8628) provider.
/// Distinct from `OAuthConfig` (authorization-code + PKCE) because device-code
/// login never involves a redirect URI or a local loopback listener.
struct DeviceCodeOAuthConfig {
    let providerId: String
    let deviceAuthorizationURL: URL
    let tokenURL: URL
    let clientId: String
    let scopes: [String]
}

/// Verification info to show the user (a URL + short code to enter there).
struct DeviceCodeInfo: Equatable {
    let userCode: String
    let verificationURL: URL
    let expiresInSeconds: Int
}

enum DeviceCodeError: Error, LocalizedError, Equatable {
    case requestFailed(Int?)
    case accessDenied
    case expired
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .requestFailed(let code):
            return LF("Falha ao iniciar login por código de dispositivo (código %@).", code.map(String.init) ?? L("desconhecido"))
        case .accessDenied:
            return L("Login negado pelo usuário.")
        case .expired:
            return L("Código de dispositivo expirou — tente novamente.")
        case .invalidResponse:
            return L("Resposta inválida do servidor de autenticação.")
        }
    }
}

private struct DeviceCodeResponse: Decodable {
    let deviceCode: String
    let userCode: String
    let verificationUri: String
    let verificationUriComplete: String?
    let expiresIn: Int
    let interval: Int?

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationUri = "verification_uri"
        case verificationUriComplete = "verification_uri_complete"
        case expiresIn = "expires_in"
        case interval
    }
}

private struct DeviceTokenErrorResponse: Decodable {
    let error: String
}

/// Result of requesting a device code: what to show the user, plus the
/// bookkeeping `poll(...)` needs to complete the login.
struct DeviceCodeRequest: Equatable {
    let info: DeviceCodeInfo
    let deviceCode: String
    let intervalSeconds: Int
}

/// Drives the OAuth 2.0 Device Authorization Grant (RFC 8628): request a
/// device code, show the user a verification URL + short code, then poll
/// the token endpoint until they approve, deny, or the code expires.
final class DeviceCodeFlow {
    private let tokenStore: TokenStoring
    private let session: URLSession
    private let now: () -> Date
    private let sleep: (UInt64) async throws -> Void

    init(
        tokenStore: TokenStoring,
        session: URLSession = .shared,
        now: @escaping () -> Date = Date.init,
        sleep: @escaping (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }
    ) {
        self.tokenStore = tokenStore
        self.session = session
        self.now = now
        self.sleep = sleep
    }

    /// Requests a device code from the authorization server.
    func requestDeviceCode(config: DeviceCodeOAuthConfig) async throws -> DeviceCodeRequest {
        var request = URLRequest(url: config.deviceAuthorizationURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let form = [
            "client_id": config.clientId,
            "scope": config.scopes.joined(separator: " ")
        ]
        request.httpBody = Self.encodeForm(form)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw DeviceCodeError.requestFailed((response as? HTTPURLResponse)?.statusCode)
        }
        guard let decoded = try? JSONDecoder().decode(DeviceCodeResponse.self, from: data),
              let verificationURL = URL(string: decoded.verificationUriComplete ?? decoded.verificationUri) else {
            throw DeviceCodeError.invalidResponse
        }
        let info = DeviceCodeInfo(
            userCode: decoded.userCode,
            verificationURL: verificationURL,
            expiresInSeconds: decoded.expiresIn
        )
        return DeviceCodeRequest(info: info, deviceCode: decoded.deviceCode, intervalSeconds: decoded.interval ?? 5)
    }

    /// Polls the token endpoint until the device code is approved, denied,
    /// or expires. On success, persists the token via `TokenStoring` and
    /// returns it (mirroring `OAuthManager.exchangeCode`).
    func poll(_ request: DeviceCodeRequest, config: DeviceCodeOAuthConfig) async throws -> OAuthToken {
        var interval = max(1, request.intervalSeconds)
        let deadline = now().addingTimeInterval(TimeInterval(max(request.info.expiresInSeconds, 60)))

        while now() < deadline {
            try await sleep(UInt64(interval) * 1_000_000_000)

            var tokenRequest = URLRequest(url: config.tokenURL)
            tokenRequest.httpMethod = "POST"
            tokenRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let form = [
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                "device_code": request.deviceCode,
                "client_id": config.clientId
            ]
            tokenRequest.httpBody = Self.encodeForm(form)

            let (data, response) = try await session.data(for: tokenRequest)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            if status == 200 {
                guard let payload = try? JSONDecoder().decode(TokenEndpointResponse.self, from: data) else {
                    throw DeviceCodeError.invalidResponse
                }
                let expiresAt = payload.expiresIn.map { now().addingTimeInterval(TimeInterval($0)) }
                let token = OAuthToken(
                    accessToken: payload.accessToken,
                    refreshToken: payload.refreshToken,
                    expiresAt: expiresAt,
                    extra: [:]
                )
                try tokenStore.save(token, providerId: config.providerId)
                return token
            }

            let errorCode = (try? JSONDecoder().decode(DeviceTokenErrorResponse.self, from: data))?.error
            switch errorCode {
            case "authorization_pending":
                continue
            case "slow_down":
                interval += 5
                continue
            case "access_denied":
                throw DeviceCodeError.accessDenied
            case "expired_token":
                throw DeviceCodeError.expired
            default:
                throw DeviceCodeError.requestFailed(status)
            }
        }
        throw DeviceCodeError.expired
    }

    private static func encodeForm(_ form: [String: String]) -> Data? {
        form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .deviceCodeFormValueAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
    }
}

private extension CharacterSet {
    static let deviceCodeFormValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=+")
        return set
    }()
}
