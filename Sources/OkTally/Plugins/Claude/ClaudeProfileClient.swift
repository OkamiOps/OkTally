// Sources/OkTally/Plugins/Claude/ClaudeProfileClient.swift
import Foundation

protocol ClaudeProfileFetching {
    /// Nome de plano amigável ("Pro", "Max"…) ou `nil` quando o endpoint não responde ou
    /// não traz o tipo de organização. Nunca lança — plano é enfeite, não pode derrubar
    /// o fetch de cota.
    func fetchPlanLabel(accessToken: String) async -> String?
}

/// Quem é a conta por trás de um token: o e-mail vira o rótulo automático e a chave de
/// dedup; a org fica guardada só para diagnóstico.
struct ClaudeIdentity: Equatable {
    let email: String?
    let orgUUID: String?
}

protocol ClaudeIdentityFetching {
    /// `nil` quando o perfil não responde — nunca lança.
    func fetchIdentity(accessToken: String) async -> ClaudeIdentity?
}

/// Consulta o perfil OAuth (`api.anthropic.com/api/oauth/profile` — o mesmo endpoint que
/// o Claude Code usa após o login) e extrai o tier da organização e a identidade da
/// conta. Decode tolerante: só os campos consumidos, e qualquer forma inesperada colapsa
/// em `nil`.
final class ClaudeProfileClient: ClaudeProfileFetching, ClaudeIdentityFetching {
    private let session: URLSession
    /// O perfil muda raramente; cachear evita somar chamadas ao rate limit agressivo do
    /// host (o /usage já tolera pouco). Plano e identidade saem da MESMA resposta, então
    /// dividem o cache. A chave é o access token: com duas contas do Claude, o perfil de
    /// uma nunca pode responder pela outra.
    private var cache: [String: (json: [String: Any], at: Date)] = [:]
    private let lock = NSLock()
    private let cacheTTL: TimeInterval = 12 * 3600

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchPlanLabel(accessToken: String) async -> String? {
        await fetchProfile(accessToken: accessToken).flatMap(Self.planLabel(fromProfile:))
    }

    func fetchIdentity(accessToken: String) async -> ClaudeIdentity? {
        guard let json = await fetchProfile(accessToken: accessToken) else { return nil }
        let identity = Self.identity(fromProfile: json)
        return ClaudeIdentity(email: identity.email, orgUUID: identity.orgUUID)
    }

    private func fetchProfile(accessToken: String) async -> [String: Any]? {
        let cached = cachedProfile(for: accessToken)
        if let cached, Date().timeIntervalSince(cached.at) < cacheTTL {
            return cached.json
        }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/profile")!)
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return cached?.json }

        lock.lock()
        // Token renovado deixa a entrada antiga órfã; o cache só guarda o último.
        cache = [accessToken: (json, Date())]
        lock.unlock()
        return json
    }

    private func cachedProfile(for accessToken: String) -> (json: [String: Any], at: Date)? {
        lock.lock()
        defer { lock.unlock() }
        return cache[accessToken]
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

    /// `account.email` e `organization.uuid` do perfil.
    static func identity(fromProfile json: [String: Any]) -> (email: String?, orgUUID: String?) {
        let email = ((json["account"] as? [String: Any])?["email"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let org = (json["organization"] as? [String: Any])?["uuid"] as? String
        return (email, org)
    }
}
