// Sources/OkTally/Plugins/Copilot/CopilotUsageProvider.swift
import Foundation

enum CopilotError: Error, Equatable {
    /// Nenhum token local encontrado (Copilot/gh CLI não instalados ou deslogados).
    case notDetected
    /// O GitHub recusou o token (401/403) — precisa logar de novo no Copilot/gh.
    case tokenRejected
    case badResponse(Int)
}

extension CopilotError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notDetected:
            return L("Copilot não detectado — nenhum login do Copilot ou gh CLI neste Mac.")
        case .tokenRejected:
            return L("Token do GitHub recusado — faça login no Copilot ou gh novamente.")
        case .badResponse(let status):
            return LF("GitHub respondeu HTTP %d.", status)
        }
    }
}

/// GitHub Copilot via o endpoint interno de entitlement que os próprios plugins de IDE
/// usam (`copilot_internal/user` — mesma fonte do Quotio, MIT). Zero-config: autentica
/// com o token que o Copilot/gh CLI já deixou em disco (`CopilotTokenReader`).
final class CopilotUsageProvider: UsageProvider {
    let id = "copilot"
    let displayName = "GitHub Copilot"
    let authMethod: AuthMethod = .localFile(path: "~/.config/github-copilot")
    let refreshInterval: TimeInterval = 600

    private let tokenReader: CopilotTokenReading
    private let session: URLSession
    private static let entitlementURL = URL(string: "https://api.github.com/copilot_internal/user")!

    init(tokenReader: CopilotTokenReading = CopilotTokenReader(), session: URLSession = .shared) {
        self.tokenReader = tokenReader
        self.session = session
    }

    func isAuthenticated() async -> Bool {
        tokenReader.firstToken() != nil
    }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        guard let token = tokenReader.firstToken() else { throw CopilotError.notDetected }

        var request = URLRequest(url: Self.entitlementURL)
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.addValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CopilotError.badResponse(0) }
        if http.statusCode == 401 || http.statusCode == 403 { throw CopilotError.tokenRejected }
        guard (200...299).contains(http.statusCode) else { throw CopilotError.badResponse(http.statusCode) }

        let entitlement = try JSONDecoder().decode(Entitlement.self, from: data)
        let now = Date()
        return ProviderSnapshot(
            providerId: id,
            fetchedAt: now,
            quotas: Self.windows(from: entitlement, now: now),
            usageDetail: nil,
            planLabel: entitlement.planDisplayName
        )
    }

    // MARK: - Mapping

    static func windows(from entitlement: Entitlement, now: Date) -> [QuotaWindow] {
        // O GitHub sempre manda uma data de reset nos planos com limite; se faltar
        // (plano em transição), o ciclo mensal do Copilot torna o 1º do próximo mês a
        // melhor aproximação disponível.
        let resetAt = entitlement.resetDate ?? Self.startOfNextMonth(after: now)

        // Formato 1: quota_snapshots (planos pagos com janela premium).
        if let snapshots = entitlement.quotaSnapshots {
            var windows: [QuotaWindow] = []
            let pairs: [(String, Entitlement.Snapshot?)] = [
                ("chat", snapshots.chat),
                ("completions", snapshots.completions),
                ("premium", snapshots.premiumInteractions),
            ]
            for (label, snapshot) in pairs {
                guard let snapshot, snapshot.unlimited != true,
                      let percentRemaining = snapshot.resolvedPercentRemaining else { continue }
                windows.append(QuotaWindow(
                    label: label,
                    shape: .periodicCounter(used: 100 - percentRemaining, limit: 100, resetAt: resetAt)
                ))
            }
            if !windows.isEmpty { return windows }
        }

        // Formato 2: planos free/individual — restante e total absolutos.
        var windows: [QuotaWindow] = []
        if let remaining = entitlement.limitedUserQuotas, let total = entitlement.monthlyQuotas {
            if let chatRemaining = remaining.chat, let chatTotal = total.chat, chatTotal > 0 {
                windows.append(QuotaWindow(
                    label: "chat",
                    shape: .periodicCounter(used: Double(chatTotal - chatRemaining), limit: Double(chatTotal), resetAt: resetAt)
                ))
            }
            if let compRemaining = remaining.completions, let compTotal = total.completions, compTotal > 0 {
                windows.append(QuotaWindow(
                    label: "completions",
                    shape: .periodicCounter(used: Double(compTotal - compRemaining), limit: Double(compTotal), resetAt: resetAt)
                ))
            }
        }
        return windows
    }

    private static func startOfNextMonth(after date: Date) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        return calendar.date(byAdding: .month, value: 1, to: startOfMonth) ?? date.addingTimeInterval(30 * 24 * 3600)
    }

    // MARK: - DTOs (nomes de campo idênticos aos da resposta do GitHub)

    struct Entitlement: Decodable {
        struct Snapshot: Decodable {
            let entitlement: Int?
            let remaining: Int?
            let percentRemaining: Double?
            let unlimited: Bool?

            enum CodingKeys: String, CodingKey {
                case entitlement, remaining, unlimited
                case percentRemaining = "percent_remaining"
            }

            /// `percent_remaining` quando presente; senão deriva de remaining/entitlement.
            var resolvedPercentRemaining: Double? {
                if let percentRemaining { return min(100, max(0, percentRemaining)) }
                guard let remaining, let entitlement, entitlement > 0 else { return nil }
                return min(100, max(0, Double(remaining) / Double(entitlement) * 100))
            }
        }

        struct Snapshots: Decodable {
            let chat: Snapshot?
            let completions: Snapshot?
            let premiumInteractions: Snapshot?

            enum CodingKeys: String, CodingKey {
                case chat, completions
                case premiumInteractions = "premium_interactions"
            }
        }

        struct CountQuotas: Decodable {
            let chat: Int?
            let completions: Int?
        }

        let quotaResetDate: String?
        let quotaResetDateUtc: String?
        let limitedUserResetDate: String?
        let quotaSnapshots: Snapshots?
        let limitedUserQuotas: CountQuotas?
        let monthlyQuotas: CountQuotas?
        let accessTypeSku: String?
        let copilotPlan: String?

        enum CodingKeys: String, CodingKey {
            case quotaResetDate = "quota_reset_date"
            case quotaResetDateUtc = "quota_reset_date_utc"
            case limitedUserResetDate = "limited_user_reset_date"
            case quotaSnapshots = "quota_snapshots"
            case limitedUserQuotas = "limited_user_quotas"
            case monthlyQuotas = "monthly_quotas"
            case accessTypeSku = "access_type_sku"
            case copilotPlan = "copilot_plan"
        }

        /// Nome de plano amigável a partir do SKU/plano cru (regras portadas do Quotio,
        /// que as calibrou contra contas reais de cada tier).
        var planDisplayName: String? {
            let sku = accessTypeSku?.lowercased() ?? ""
            let plan = copilotPlan?.lowercased() ?? ""
            if sku.contains("enterprise") || plan == "enterprise" { return "Enterprise" }
            if sku.contains("business") || plan == "business" { return "Business" }
            // Cota educacional se comporta como Pro (chat/completions ilimitados).
            if sku.contains("educational") { return "Pro" }
            if sku.contains("pro") || plan.contains("pro") { return "Pro" }
            if plan == "individual" && !sku.contains("free_limited") { return "Pro" }
            if sku.contains("free_limited") || sku == "free" || plan.contains("free") { return "Free" }
            if let plan = copilotPlan, !plan.isEmpty { return plan.capitalized }
            if let sku = accessTypeSku, !sku.isEmpty { return sku.capitalized }
            return nil
        }

        var resetDate: Date? {
            guard let raw = quotaResetDateUtc ?? quotaResetDate ?? limitedUserResetDate else { return nil }
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso.date(from: raw) { return date }
            iso.formatOptions = [.withInternetDateTime]
            if let date = iso.date(from: raw) { return date }
            let dateOnly = DateFormatter()
            dateOnly.dateFormat = "yyyy-MM-dd"
            dateOnly.timeZone = TimeZone(identifier: "UTC")
            return dateOnly.date(from: raw)
        }
    }
}
