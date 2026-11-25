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
    /// Uma conexão pode ser válida sem o serviço expor cotas consultáveis.
    /// Ausente nos snapshots antigos e nos provedores com monitoramento completo.
    let connectionNote: String?

    init(
        providerId: String,
        fetchedAt: Date,
        quotas: [QuotaWindow],
        usageDetail: [UsageDetail]?,
        planLabel: String? = nil,
        connectionNote: String? = nil
    ) {
        self.providerId = providerId
        self.fetchedAt = fetchedAt
        self.quotas = quotas
        self.usageDetail = usageDetail
        self.planLabel = planLabel
        self.connectionNote = connectionNote
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
    /// Opcionais para preservar snapshots persistidos antes do detalhamento de cache.
    /// Quando presentes, `promptTokens` representa somente o input não-cacheado.
    let cacheReadTokens: Int?
    let cacheWriteTokens: Int?
    /// Anthropic cobra escrita de cache com TTL de 1h mais caro que a de 5min.
    let cacheWrite1hTokens: Int?

    init(
        modelId: String,
        promptTokens: Int,
        completionTokens: Int,
        cacheReadTokens: Int? = nil,
        cacheWriteTokens: Int? = nil,
        cacheWrite1hTokens: Int? = nil
    ) {
        self.modelId = modelId
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.cacheWrite1hTokens = cacheWrite1hTokens
    }
}
