// Sources/OkTally/Plugins/Cursor/CursorDeepLoginFlow.swift
import Foundation
import AppKit

/// Login próprio do OkTally no Cursor (contas extras), o mesmo "deep login" com PKCE que
/// o CLI do Cursor usa: o navegador abre `cursor.com/loginDeepControl` com o `challenge`
/// e um `uuid`; o app consulta `api2.cursor.sh/auth/poll` com o `uuid` e o `verifier` até
/// o login terminar (404 enquanto isso), e recebe uma sessão só dele — independente do
/// IDE, que pode trocar de conta à vontade sem derrubar esta.
///
/// Conferido ao vivo em 2026-09-28 (docs/superpowers/research/multi-account-cursor.md):
/// o poll responde `404 Not found` enquanto não há login; a forma do `200` vem das
/// implementações da comunidade citadas no plano e precisa da QA do dono.
final class CursorDeepLoginFlow {
    struct Start: Equatable {
        let browserURL: URL
        let uuid: String
        /// Fica só no app: é ele que prova, no poll, que quem abriu o login é quem busca.
        let verifier: String
    }

    static let defaultMaxAttempts = 150
    private static let loginURL = URL(string: "https://cursor.com/loginDeepControl")!
    private static let pollBase = URL(string: "https://api2.cursor.sh/auth/poll")!

    private let tokenStore: TokenStoring
    private let session: URLSession
    private let sleep: (UInt64) async throws -> Void
    private let maxAttempts: Int

    init(
        tokenStore: TokenStoring,
        session: URLSession = .shared,
        sleep: @escaping (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) },
        maxAttempts: Int = CursorDeepLoginFlow.defaultMaxAttempts
    ) {
        self.tokenStore = tokenStore
        self.session = session
        self.sleep = sleep
        self.maxAttempts = maxAttempts
    }

    static func makeStart(verifier: String, uuid: String) -> Start {
        var comps = URLComponents(url: loginURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "challenge", value: PKCE.challenge(for: verifier)),
            .init(name: "uuid", value: uuid),
            .init(name: "mode", value: "login"),
            .init(name: "redirectTarget", value: "cli")
        ]
        return Start(browserURL: comps.url!, uuid: uuid, verifier: verifier)
    }

    static func pollURL(uuid: String, verifier: String) -> URL {
        var comps = URLComponents(url: pollBase, resolvingAgainstBaseURL: false)!
        comps.queryItems = [.init(name: "uuid", value: uuid), .init(name: "verifier", value: verifier)]
        return comps.url!
    }

    /// Verifier e uuid novos a cada tentativa de login.
    func begin() -> Start {
        Self.makeStart(verifier: PKCE.makeVerifier(), uuid: UUID().uuidString.lowercased())
    }

    /// Abre o navegador no login.
    func open(_ start: Start) {
        NSWorkspace.shared.open(start.browserURL)
    }

    /// Consulta até o login terminar. Espera 1 s, depois ×1,5 a cada volta, no máximo 10 s,
    /// por até `maxAttempts` consultas (~20 min no padrão). Sucesso grava a sessão no
    /// Keychain sob `instanceId`.
    func poll(_ start: Start, instanceId: String) async throws -> OAuthToken {
        let url = Self.pollURL(uuid: start.uuid, verifier: start.verifier)
        var delay: Double = 1
        for _ in 0..<maxAttempts {
            try await sleep(UInt64(delay * 1_000_000_000))
            delay = min(delay * 1.5, 10)

            guard let (data, response) = try? await session.data(from: url),
                  let status = (response as? HTTPURLResponse)?.statusCode
            else { continue } // rede instável: tenta de novo na próxima volta

            switch status {
            case 200:
                guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let accessToken = json["accessToken"] as? String, !accessToken.isEmpty
                else { throw OAuthError.tokenExchangeFailed(status) }
                let token = OAuthToken(
                    accessToken: accessToken,
                    refreshToken: (json["refreshToken"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                    expiresAt: Self.expiry(ofJWT: accessToken),
                    extra: [:]
                )
                try tokenStore.save(token, providerId: instanceId)
                return token
            case 401, 403:
                throw OAuthError.tokenExchangeFailed(status)
            default:
                continue // 404 = ainda não logou; 5xx = passageiro
            }
        }
        throw OAuthError.loginTimeout
    }

    /// `exp` da sessão (JWT de ~60 dias). Token opaco = sem validade conhecida.
    static func expiry(ofJWT token: String) -> Date? {
        guard let exp = JWT.decodePayload(token)?["exp"] as? Double else {
            return (JWT.decodePayload(token)?["exp"] as? Int).map { Date(timeIntervalSince1970: TimeInterval($0)) }
        }
        return Date(timeIntervalSince1970: exp)
    }
}
