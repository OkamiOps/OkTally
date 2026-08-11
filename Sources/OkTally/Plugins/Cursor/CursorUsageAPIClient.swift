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
struct CursorUsageResponse: Codable, Equatable {
    struct PlanUsage: Codable, Equatable {
        let totalSpend: Double
        let limit: Double
        let totalPercentUsed: Double
    }

    let billingCycleStart: String
    let billingCycleEnd: String
    let planUsage: PlanUsage
}

protocol CursorUsageFetching {
    func fetchUsage(accessToken: String) async throws -> CursorUsageResponse
}

enum CursorUsageError: Error, Equatable {
    case notDetected
    case badResponse(Int?)
}

extension CursorUsageError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notDetected:
            return "Cursor não detectado — instale/entre no Cursor para acompanhar o uso."
        case .badResponse(let statusCode):
            return "Cursor respondeu com erro (código \(statusCode.map(String.init) ?? "desconhecido"))."
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
        return try JSONDecoder().decode(CursorUsageResponse.self, from: data)
    }
}
