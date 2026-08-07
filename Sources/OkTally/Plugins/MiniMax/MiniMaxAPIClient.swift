// Sources/OkTally/Plugins/MiniMax/MiniMaxAPIClient.swift
import Foundation

enum MiniMaxRegion: String, Equatable {
    case global
    case china

    var baseURL: String {
        switch self {
        case .global: return "https://api.minimax.io"
        case .china: return "https://api.minimaxi.com"
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

// NOTE (schema pin, Step 1): the research report only ever reproduces the *per-model* field
// list above — it explicitly states it never observed the literal raw JSON envelope (array vs
// object-wrapped-array), see §8: "no source produced the literal raw JSON wrapper". The task
// brief's own Interfaces section specifies this wrapper as `models: [MiniMaxModelRemains]`
// (overriding the brief's separate illustrative Step-2 JSON, which used `model_remains` instead)
// so `models` is used here as the interface contract, not as a research-confirmed field name.
struct MiniMaxRemainsResponse: Codable, Equatable {
    let models: [MiniMaxModelRemains]
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
            return "Configure sua chave de API do MiniMax nas Preferências."
        case .badResponse(let statusCode):
            return "MiniMax respondeu com erro (código \(statusCode.map(String.init) ?? "desconhecido"))."
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
