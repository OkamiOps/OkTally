// Sources/OkTally/Plugins/Cursor/CursorUsageAPIClient.swift
import Foundation

/// Schema confirmed via live authenticated calls to `GetCurrentPeriodUsage` (2026-08-07,
/// re-checked 2026-08-12), field names taken verbatim from the real response. See
/// `Tests/OkTallyTests/Fixtures/cursor_usage_response.json`.
///
/// Only the fields OkTally actually consumes are declared: Cursor evolves this
/// undocumented schema without notice (`bonusSpend` was dropped between 08-07 and 08-12,
/// which made the strict decoder fail the whole provider), so every extra required field
/// is a future breakage waiting to happen.
///
/// Amounts in `planUsage` are cents (e.g. `limit: 2000` == $20.00, matching Cursor Pro's
/// included monthly credit pool). `billingCycleStart`/`billingCycleEnd` are epoch
/// milliseconds encoded as strings.
struct CursorUsageResponse: Equatable {
    struct PlanUsage: Equatable {
        /// Dropped from the live schema on 2026-08-17 (same fate as `bonusSpend` before
        /// it); kept optional so its presence still enables the more precise
        /// `limit - totalSpend` balance, which can go negative on overage. Campos
        /// financeiros são todos opcionais: o app usa o que existir.
        let totalSpend: Double?
        /// The API's own remaining-credit figure, the only balance source once
        /// `totalSpend` is gone.
        let remaining: Double?
        let limit: Double?
        let totalPercentUsed: Double
    }

    let billingCycleStart: String?
    let billingCycleEnd: String?
    let planUsage: PlanUsage

    init(billingCycleStart: String?, billingCycleEnd: String?, planUsage: PlanUsage) {
        self.billingCycleStart = billingCycleStart
        self.billingCycleEnd = billingCycleEnd
        self.planUsage = planUsage
    }

    /// Parse sem `Codable`: o schema não é público e muda em produção sem versionamento.
    /// Campos novos/ausentes nunca devem derrubar a coleta se ainda houver percentual.
    init(data: Data) throws {
        guard let root = TolerantJSON.object(data: data) else {
            throw ProviderAPIError.malformedResponse("Cursor")
        }
        let plan = TolerantJSON.object(TolerantJSON.deepValue(for: "planUsage", in: root))
            ?? TolerantJSON.object(TolerantJSON.deepValue(for: "plan_usage", in: root))
            ?? root
        let directPercent = TolerantJSON.number(in: plan, camel: "totalPercentUsed")
            ?? TolerantJSON.number(in: plan, camel: "percentUsed")
            ?? TolerantJSON.number(in: plan, camel: "usagePercent")
        let totalSpend = TolerantJSON.number(in: plan, camel: "totalSpend")
        let remaining = TolerantJSON.number(in: plan, camel: "remaining")
        let limit = TolerantJSON.number(in: plan, camel: "limit")
        let derivedPercent: Double?
        if let remaining, let limit, limit > 0 {
            derivedPercent = min(100, max(0, (1 - remaining / limit) * 100))
        } else if let totalSpend, let limit, limit > 0 {
            derivedPercent = min(100, max(0, totalSpend / limit * 100))
        } else {
            derivedPercent = nil
        }
        guard let percent = directPercent ?? derivedPercent else { throw ProviderAPIError.malformedResponse("Cursor") }
        self.planUsage = PlanUsage(
            totalSpend: totalSpend,
            remaining: remaining,
            limit: limit,
            totalPercentUsed: percent
        )
        self.billingCycleStart = TolerantJSON.string(in: root, camel: "billingCycleStart")
            ?? TolerantJSON.string(TolerantJSON.deepValue(for: "billingCycleStart", in: root))
            ?? TolerantJSON.string(TolerantJSON.deepValue(for: "billing_cycle_start", in: root))
        self.billingCycleEnd = TolerantJSON.string(in: root, camel: "billingCycleEnd")
            ?? TolerantJSON.string(TolerantJSON.deepValue(for: "billingCycleEnd", in: root))
            ?? TolerantJSON.string(TolerantJSON.deepValue(for: "billing_cycle_end", in: root))
    }
}

protocol CursorUsageFetching {
    func fetchUsage(accessToken: String) async throws -> CursorUsageResponse
}

enum CursorUsageError: Error, Equatable {
    case notDetected
    case sessionUnreadable
    case badResponse(Int?)
}

extension CursorUsageError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notDetected:
            return L("Cursor não detectado — instale/entre no Cursor para acompanhar o uso.")
        case .sessionUnreadable:
            return L("Sessão do Cursor encontrada, mas não pôde ser decifrada — aprove o acesso do OkTally no Keychain ou entre no Cursor novamente.")
        case .badResponse(let statusCode):
            return LF("Cursor respondeu com erro (código %@).", statusCode.map(String.init) ?? L("desconhecido"))
        }
    }
}

final class CursorUsageAPIClient: CursorUsageFetching {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func fetchUsage(accessToken: String) async throws -> CursorUsageResponse {
        var request = URLRequest(url: URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CursorUsageError.badResponse((response as? HTTPURLResponse)?.statusCode)
        }
        return try CursorUsageResponse(data: data)
    }
}

/// Dados da conta por trás de uma sessão do Cursor.
enum CursorAccountAPI {
    private static let getEmailURL = URL(string: "https://api2.cursor.sh/aiserver.v1.AuthService/GetEmail")!

    /// `POST AuthService/GetEmail` com a própria sessão → `{"email": …}`. Conferido ao vivo
    /// em 2026-09-28. Rótulo é enfeite: qualquer falha vira `nil`.
    static func fetchEmail(accessToken: String, session: URLSession = .shared) async -> String? {
        var request = URLRequest(url: getEmailURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return email(fromGetEmail: data)
    }

    static func email(fromGetEmail data: Data) -> String? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let email = json["email"] as? String, !email.isEmpty else { return nil }
        return email
    }
}
