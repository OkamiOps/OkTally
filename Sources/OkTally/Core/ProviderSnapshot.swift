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

enum RenewalCadence: String, Codable, Equatable {
    case weekly
    case monthly
}

struct QuotaWindow: Codable, Equatable {
    let label: String
    let shape: QuotaShape
    /// Only real renewable subscription windows opt in. A missing value keeps snapshots
    /// written by older builds decodable and excludes synthetic/short windows from pace
    /// forecasting.
    let renewalCadence: RenewalCadence?

    init(label: String, shape: QuotaShape, renewalCadence: RenewalCadence? = nil) {
        self.label = label
        self.shape = shape
        self.renewalCadence = renewalCadence
    }
}

struct UsageDetail: Codable, Equatable {
    let modelId: String
    let promptTokens: Int
    let completionTokens: Int
}
