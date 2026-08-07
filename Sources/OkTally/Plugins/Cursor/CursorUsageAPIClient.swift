// Sources/OkTally/Plugins/Cursor/CursorUsageAPIClient.swift
import Foundation

/// Schema confirmed via a single live authenticated call to
/// `GetCurrentPeriodUsage` during Task 8 (2026-08-07), field names taken verbatim from
/// the real response. See `Tests/OkTallyTests/Fixtures/cursor_usage_response.json`.
///
/// Amounts in `planUsage` are cents (e.g. `limit: 2000` == $20.00, matching Cursor Pro's
/// included monthly credit pool). `billingCycleStart`/`billingCycleEnd` are epoch
/// milliseconds encoded as strings.
struct CursorUsageResponse: Codable, Equatable {
    struct PlanUsage: Codable, Equatable {
        let totalSpend: Double
        let includedSpend: Double
        let bonusSpend: Double
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
