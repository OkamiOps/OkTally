// Sources/OkTally/Plugins/MiniMax/MiniMaxAPIClient.swift
import Foundation

enum MiniMaxRegion: String, Equatable {
    case global
    case china

    var baseURL: String {
        switch self {
        // Token Plan usage is served from the www. host, not api. (MiniMax runs separate
        // backends per domain) — confirmed against the official token-plan docs and tokscale.
        case .global: return "https://www.minimax.io"
        case .china: return "https://www.minimaxi.com"
        }
    }
}

// Field names pinned from docs/superpowers/research/plan2-minimax.md §3 (Response schema),
// captured from real GitHub issue reports against MiniMax-AI/MiniMax-M2.7#48 and
// MiniMax-AI/cli#173. `current_interval_*` = 5h rolling window, `current_weekly_*` = weekly
// window, `remains_time` = milliseconds until the (shared) window reset countdown, not an
// absolute timestamp. `*_status` semantics are undocumented/opaque per the research report;
// decoded here for schema fidelity but not used in the quota mapping.
struct MiniMaxModelRemains: Codable, Equatable {
    let modelName: String
    let currentIntervalTotalCount: Int
    let currentIntervalUsageCount: Int
    let currentWeeklyTotalCount: Int
    let currentWeeklyUsageCount: Int
    let currentIntervalRemainingPercent: Double
    let currentWeeklyRemainingPercent: Double
    let currentIntervalStatus: Int
    let currentWeeklyStatus: Int
    let remainsTime: Int

    enum CodingKeys: String, CodingKey {
        case modelName = "model_name"
        case currentIntervalTotalCount = "current_interval_total_count"
        case currentIntervalUsageCount = "current_interval_usage_count"
        case currentWeeklyTotalCount = "current_weekly_total_count"
        case currentWeeklyUsageCount = "current_weekly_usage_count"
        case currentIntervalRemainingPercent = "current_interval_remaining_percent"
        case currentWeeklyRemainingPercent = "current_weekly_remaining_percent"
        case currentIntervalStatus = "current_interval_status"
        case currentWeeklyStatus = "current_weekly_status"
        case remainsTime = "remains_time"
    }
}

// Envelope confirmed from a real live response: the array is under `model_remains`, alongside
// a `base_resp` status object.
struct MiniMaxRemainsResponse: Codable, Equatable {
    let models: [MiniMaxModelRemains]

    enum CodingKeys: String, CodingKey {
        case models = "model_remains"
    }
}

protocol MiniMaxRemainsFetching {
    func fetchRemains(apiKey: String, region: MiniMaxRegion) async throws -> MiniMaxRemainsResponse
}

enum MiniMaxError: Error, Equatable {
    case badResponse(Int?)
    case missingAPIKey
}

extension MiniMaxError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return L("Configure sua chave de API do MiniMax nas Preferências.")
        case .badResponse(let statusCode):
            return LF("MiniMax respondeu com erro (código %@).", statusCode.map(String.init) ?? L("desconhecido"))
        }
    }
}

final class MiniMaxAPIClient: MiniMaxRemainsFetching {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func fetchRemains(apiKey: String, region: MiniMaxRegion) async throws -> MiniMaxRemainsResponse {
        var request = URLRequest(url: URL(string: "\(region.baseURL)/v1/token_plan/remains")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw MiniMaxError.badResponse((response as? HTTPURLResponse)?.statusCode)
        }
        return try JSONDecoder().decode(MiniMaxRemainsResponse.self, from: data)
    }
}
