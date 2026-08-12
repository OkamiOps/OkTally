// Sources/OkTally/Plugins/Codex/CodexAnalyticsFetcher.swift
import Foundation

protocol CodexAnalyticsFetching {
    func fetch(accessToken: String, accountId: String?) async throws -> TokenAnalytics?
}

/// Busca as estatísticas de conta no endpoint de perfil do ChatGPT usando o mesmo token
/// OAuth do plugin de cota. Falha silenciosa vira `nil` — analytics é enfeite, nunca pode
/// derrubar a visão principal.
final class CodexAnalyticsFetcher: CodexAnalyticsFetching {
    private static let profileURL = URL(string: "https://chatgpt.com/backend-api/wham/profiles/me")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch(accessToken: String, accountId: String?) async throws -> TokenAnalytics? {
        var request = URLRequest(url: Self.profileURL)
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        // O backend segrega respostas por cliente; identificar-se como o app oficial de
        // desktop é o que faz o campo `stats` vir preenchido.
        request.addValue("Codex Desktop", forHTTPHeaderField: "Originator")
        if let accountId, !accountId.isEmpty {
            request.addValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil
        }
        return TokenAnalytics(codexProfileJSON: data)
    }
}
