import Foundation
import CoreFoundation

/// The information needed to continue a Kimi Code OAuth device login after the user has
/// been sent to the browser. This value intentionally contains no access credential.
struct KimiDeviceAuthorization: Equatable {
    let userCode: String
    let deviceCode: String
    let verificationURL: URL
    let expiresAt: Date
    let interval: TimeInterval
}

enum KimiOAuthError: Error, Equatable, LocalizedError {
    case requestFailed(Int?)
    case invalidResponse
    case accessDenied
    case expired
    case noRefreshToken
    case profileFailed(Int?)

    var errorDescription: String? {
        switch self {
        case .requestFailed(let status):
            return LF("Falha na autorização Kimi Code (HTTP %@).", status.map(String.init) ?? "—")
        case .invalidResponse:
            return L("O Kimi Code retornou uma autorização inválida.")
        case .accessDenied:
            return L("O login no Kimi Code foi recusado.")
        case .expired:
            return L("A autorização do Kimi Code expirou. Entre novamente.")
        case .noRefreshToken:
            return L("A sessão do Kimi Code não pode ser renovada. Entre novamente.")
        case .profileFailed(let status):
            return LF("Falha ao consultar a conta Kimi Code (HTTP %@).", status.map(String.init) ?? "—")
        }
    }
}

/// Kimi Code's OAuth client is deliberately HTTP-only. It does not receive a
/// `TokenStoring` dependency and never writes credentials; the login coordinator decides
/// whether a completed token belongs to an account and persists it only after that check.
final class KimiOAuthClient {
    static let authorizationURL = URL(string: "https://auth.kimi.com/api/oauth/device_authorization")!
    static let tokenURL = URL(string: "https://auth.kimi.com/api/oauth/token")!
    static let profileURL = URL(string: "https://api.kimi.com/coding/v1/me")!
    static let clientID = "17e5f671-d194-4dfb-9706-5516cb48c098"

    /// OkTally identifies itself consistently instead of impersonating the Kimi CLI or
    /// deriving a device id from a person or their OAuth credentials. These values stay
    /// stable across requests and contain no user identity.
    private static let identityHeaders = [
        "User-Agent": "OkTally/1",
        "X-Msh-Platform": "oktally_macos",
        "X-Msh-Version": "1",
        "X-Msh-Device-Name": "OkTally",
        "X-Msh-Device-Model": "Mac",
        "X-Msh-Os-Version": "macOS"
    ]

    private static let installationDeviceID: String = {
        let defaults = UserDefaults.standard
        let key = "kimiCodeDeviceIdentifier"
        if let existing = defaults.string(forKey: key), !existing.isEmpty { return existing }
        let identifier = UUID().uuidString
        defaults.set(identifier, forKey: key)
        return identifier
    }()

    private let deviceIdentifier: String
    private let session: URLSession
    private let now: () -> Date
    private let sleep: (UInt64) async throws -> Void

    init(
        session: URLSession = .shared,
        deviceIdentifier: String? = nil,
        now: @escaping () -> Date = Date.init,
        sleep: @escaping (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }
    ) {
        self.deviceIdentifier = deviceIdentifier ?? Self.installationDeviceID
        self.session = session
        self.now = now
        self.sleep = sleep
    }

    func beginDeviceLogin() async throws -> KimiDeviceAuthorization {
        try Task.checkCancellation()
        let (data, response) = try await postForm(["client_id": Self.clientID], to: Self.authorizationURL)
        guard response.statusCode == 200 else { throw KimiOAuthError.requestFailed(response.statusCode) }
        guard let payload = Self.object(from: data),
              let userCode = Self.nonEmptyString(payload["user_code"]),
              let deviceCode = Self.nonEmptyString(payload["device_code"]),
              let verificationURI = Self.nonEmptyString(payload["verification_uri_complete"])
                ?? Self.nonEmptyString(payload["verification_uri"]),
              let verificationURL = URL(string: verificationURI),
              let expiresIn = Self.positiveSeconds(payload["expires_in"])
        else {
            throw KimiOAuthError.invalidResponse
        }

        let interval = Self.positiveSeconds(payload["interval"]) ?? 5
        return KimiDeviceAuthorization(
            userCode: userCode,
            deviceCode: deviceCode,
            verificationURL: verificationURL,
            expiresAt: now().addingTimeInterval(expiresIn),
            interval: interval
        )
    }

    /// Polls the device endpoint until Kimi Code authorizes the browser session. The task
    /// checks cancellation before and after every sleep/request so cancelling the UI task
    /// stops polling rather than accidentally continuing a detached login.
    func waitForToken(authorization: KimiDeviceAuthorization) async throws -> OAuthToken {
        var interval = max(1, authorization.interval)
        while now() < authorization.expiresAt {
            try Task.checkCancellation()
            try await sleep(Self.nanoseconds(for: interval))
            try Task.checkCancellation()
            guard now() < authorization.expiresAt else { throw KimiOAuthError.expired }

            let (data, response) = try await postForm([
                "client_id": Self.clientID,
                "device_code": authorization.deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
            ], to: Self.tokenURL)

            if response.statusCode == 200 {
                return try await token(from: data, previous: nil)
            }

            let error = Self.object(from: data).flatMap { Self.nonEmptyString($0["error"]) }
            switch error {
            case "authorization_pending":
                continue
            case "slow_down":
                interval += 5
            case "access_denied":
                throw KimiOAuthError.accessDenied
            case "expired_token":
                throw KimiOAuthError.expired
            default:
                throw KimiOAuthError.requestFailed(response.statusCode)
            }
        }
        throw KimiOAuthError.expired
    }

    /// Refreshes an existing Kimi Code credential without writing it anywhere. Some
    /// refresh responses omit `refresh_token`; keeping the already-stored one avoids
    /// turning a valid session into a forced logout.
    func refresh(token: OAuthToken) async throws -> OAuthToken {
        try Task.checkCancellation()
        guard let refreshToken = token.refreshToken.flatMap(Self.nonEmptyString) else {
            throw KimiOAuthError.noRefreshToken
        }
        let (data, response) = try await postForm([
            "client_id": Self.clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ], to: Self.tokenURL)
        guard response.statusCode == 200 else { throw KimiOAuthError.requestFailed(response.statusCode) }
        return try await self.token(from: data, previous: token)
    }

    private func token(from data: Data, previous: OAuthToken?) async throws -> OAuthToken {
        guard let payload = Self.object(from: data),
              let accessToken = Self.nonEmptyString(payload["access_token"]),
              let expiresIn = Self.positiveSeconds(payload["expires_in"])
        else {
            throw KimiOAuthError.invalidResponse
        }

        let responseRefresh = Self.nonEmptyString(payload["refresh_token"])
        guard responseRefresh != nil || previous?.refreshToken != nil else {
            // Device authorization must give us a renewable token. A refresh response is
            // allowed to omit it only because `previous` preserves the old credential.
            throw KimiOAuthError.invalidResponse
        }

        let profile = try await fetchProfile(accessToken: accessToken)
        var extra = previous?.extra ?? [:]
        extra["userId"] = profile.userID
        if let email = profile.email { extra["email"] = email }
        if let nickname = profile.nickname { extra["nickname"] = nickname }
        if let userLevelName = profile.userLevelName { extra["userLevelName"] = userLevelName }

        return OAuthToken(
            accessToken: accessToken,
            refreshToken: responseRefresh ?? previous?.refreshToken,
            expiresAt: now().addingTimeInterval(expiresIn),
            extra: extra
        )
    }

    private func fetchProfile(accessToken: String) async throws -> KimiProfile {
        var request = URLRequest(url: Self.profileURL, timeoutInterval: 30)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await perform(request)
        guard response.statusCode == 200 else { throw KimiOAuthError.profileFailed(response.statusCode) }
        guard let payload = Self.object(from: data),
              let userID = Self.nonEmptyString(payload["user_id"])
        else {
            throw KimiOAuthError.invalidResponse
        }
        return KimiProfile(
            userID: userID,
            email: Self.nonEmptyString(payload["email"]),
            nickname: Self.nonEmptyString(payload["nickname"]),
            userLevelName: Self.nonEmptyString(payload["user_level_name"])
        )
    }

    private func postForm(_ form: [String: String], to url: URL) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(deviceIdentifier, forHTTPHeaderField: "X-Msh-Device-Id")
        Self.identityHeaders.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.httpBody = Self.formData(form)
        return try await perform(request)
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, urlResponse) = try await session.data(for: request)
            guard let response = urlResponse as? HTTPURLResponse else {
                throw KimiOAuthError.requestFailed(nil)
            }
            return (data, response)
        } catch {
            try Task.checkCancellation()
            throw error
        }
    }

    private static func object(from data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func positiveSeconds(_ value: Any?) -> TimeInterval? {
        let seconds: Double?
        switch value {
        case let numeric as NSNumber:
            seconds = CFGetTypeID(numeric) == CFBooleanGetTypeID() ? nil : numeric.doubleValue
        case let string as String: seconds = Double(string)
        default: seconds = nil
        }
        guard let seconds, seconds.isFinite, seconds > 0 else { return nil }
        return seconds
    }

    private static func formData(_ form: [String: String]) -> Data {
        form.sorted { $0.key < $1.key }
            .map { key, value in
                let escaped = value.addingPercentEncoding(withAllowedCharacters: .formValueAllowed) ?? value
                return "\(key)=\(escaped)"
            }
            .joined(separator: "&")
            .data(using: .utf8) ?? Data()
    }

    private static func nanoseconds(for seconds: TimeInterval) -> UInt64 {
        UInt64(min(seconds * 1_000_000_000, Double(UInt64.max)))
    }
}

private struct KimiProfile {
    let userID: String
    let email: String?
    let nickname: String?
    let userLevelName: String?
}

private extension CharacterSet {
    static let formValueAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+")
        return allowed
    }()
}
