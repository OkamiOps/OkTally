// Sources/OkTally/Core/QuotaUsageStatistics.swift
import Foundation

/// Consumo de quota derivado dos snapshots que o próprio OkTally já grava localmente.
/// A unidade é ponto percentual da janela de quota — nunca token. Essa separação é o que
/// permite mostrar tendência para SuperGrok/Kiro/Copilot/etc. sem fingir que porcentagem
/// de assinatura virou contador de token.
struct DailyQuotaConsumption: Equatable {
    let day: String
    let percentPoints: Double
}

struct QuotaUsageStatistics: Equatable {
    let windowLabel: String
    let currentUsedPercent: Double
    let consumedLast24h: Double
    let consumedLast7d: Double
    let peakDailyConsumption: Double
    let observedDays: Int
    let dailyConsumption: [DailyQuotaConsumption]

    /// Soma somente deltas positivos entre leituras consecutivas da MESMA janela. Quedas
    /// são reset ou expiração de janela rolante, não consumo negativo. O consumo anterior
    /// à primeira leitura é desconhecido e por isso não é inventado.
    static func derive(
        snapshots: [ProviderSnapshot],
        windowLabel: String,
        now: Date = Date(),
        days: Int = 7
    ) -> QuotaUsageStatistics? {
        let samples = snapshots
            .sorted { $0.fetchedAt < $1.fetchedAt }
            .compactMap { snapshot -> (date: Date, used: Double)? in
                guard let used = snapshot.quotas.first(where: { $0.label == windowLabel })?.shape.usedPercent,
                      used.isFinite else { return nil }
                return (snapshot.fetchedAt, min(max(used, 0), 100))
            }
        guard let latest = samples.last else { return nil }

        var byDay: [String: Double] = [:]
        var consumed24h = 0.0
        var consumed7d = 0.0
        for (previous, current) in zip(samples, samples.dropFirst()) {
            let delta = current.used - previous.used
            guard delta > 0.005 else { continue }
            let day = TokenAnalytics.dayKey(current.date)
            byDay[day, default: 0] += delta
            if now.timeIntervalSince(current.date) <= 24 * 3600 { consumed24h += delta }
            if now.timeIntervalSince(current.date) <= Double(days) * 24 * 3600 { consumed7d += delta }
        }

        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.startOfDay(for: now.addingTimeInterval(-Double(days - 1) * 24 * 3600))
        let dense = (0..<days).compactMap { offset -> DailyQuotaConsumption? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let day = TokenAnalytics.dayKey(date)
            return DailyQuotaConsumption(day: day, percentPoints: byDay[day] ?? 0)
        }
        let observedDays = Set(samples.map { TokenAnalytics.dayKey($0.date) }).count
        return QuotaUsageStatistics(
            windowLabel: windowLabel,
            currentUsedPercent: latest.used,
            consumedLast24h: consumed24h,
            consumedLast7d: consumed7d,
            peakDailyConsumption: dense.map(\.percentPoints).max() ?? 0,
            observedDays: observedDays,
            dailyConsumption: dense
        )
    }
}
