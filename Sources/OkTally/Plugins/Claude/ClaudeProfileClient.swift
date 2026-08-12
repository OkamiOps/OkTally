// Sources/OkTally/Plugins/Claude/ClaudeProfileClient.swift
import Foundation

protocol ClaudeProfileFetching {
    /// Nome de plano amigável ("Pro", "Max"…) ou `nil` quando o endpoint não responde ou
    /// não traz o tipo de organização. Nunca lança — plano é enfeite, não pode derrubar
    /// o fetch de cota.
    func fetchPlanLabel(accessToken: String) async -> String?
}

/// Consulta o perfil OAuth (`api.anthropic.com/api/oauth/profile` — o mesmo endpoint que
/// o Claude Code usa após o login) e extrai o tier da organização. Decode tolerante:
/// só os campos consumidos, e qualquer forma inesperada colapsa em `nil`.
final class ClaudeProfileClient: ClaudeProfileFetching {
    private let session: URLSession
    /// O perfil muda raramente; cachear evita somar chamadas ao rate limit agressivo do
    /// host (o /usage já tolera pouco).
    private var cached: (label: String?, at: Date)?
    private let cacheTTL: TimeInterval = 12 * 3600

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchPlanLabel(accessToken: String) async -> String? {
        if let cached, Date().timeIntervalSince(cached.at) < cacheTTL {
            return cached.label
        }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/profile")!)
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return cached?.label }

        let label = Self.planLabel(fromProfile: json)
        cached = (label, Date())
        return label
    }

    /// `organization.organization_type` chega como "claude_pro" / "claude_max" /
    /// "claude_team" / "claude_enterprise"; valores fora desse padrão são ignorados em
    /// vez de virar badge estranho.
    static func planLabel(fromProfile json: [String: Any]) -> String? {
        guard let organization = json["organization"] as? [String: Any],
              let type = (organization["organization_type"] as? String)?.lowercased()
        else { return nil }
        switch type {
        case "claude_pro": return "Pro"
        case "claude_max": return "Max"
        case "claude_team": return "Team"
        case "claude_enterprise": return "Enterprise"
        default: return nil
        }
    }
}
