// Sources/OkTally/Core/ProviderSnapshot.swift
import Foundation

struct ProviderSnapshot: Codable, Equatable {
    let providerId: String
    let fetchedAt: Date
    let quotas: [QuotaWindow]
    let usageDetail: [UsageDetail]?
}

struct QuotaWindow: Codable, Equatable {
    let label: String
    let shape: QuotaShape
}

struct UsageDetail: Codable, Equatable {
    let modelId: String
    let promptTokens: Int
    let completionTokens: Int
}
