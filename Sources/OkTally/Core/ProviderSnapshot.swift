// Sources/OkTally/Core/ProviderSnapshot.swift
import Foundation

struct ProviderSnapshot: Codable, Equatable {
    let providerId: String
    let fetchedAt: Date
    let quotas: [QuotaWindow]
    let usageDetail: [UsageDetail]?
    /// Nome do plano da conta ("Pro", "Plus", "Free"…) quando o provider o expõe.
    /// Opcional e com default para manter compatibilidade com snapshots persistidos
    /// antes do campo existir.
    let planLabel: String?

    init(
        providerId: String,
        fetchedAt: Date,
        quotas: [QuotaWindow],
        usageDetail: [UsageDetail]?,
        planLabel: String? = nil
    ) {
        self.providerId = providerId
        self.fetchedAt = fetchedAt
        self.quotas = quotas
        self.usageDetail = usageDetail
        self.planLabel = planLabel
    }
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
