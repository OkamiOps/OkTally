// Sources/OkTally/Core/TrendSeries.swift
import Foundation

/// Janelas oferecidas pelo seletor da aba Análise.
enum TrendWindow: Int, CaseIterable {
    case days30 = 30
    case days90 = 90
    case days365 = 365

    var label: String {
        switch self {
        case .days30: return L("30 d")
        case .days90: return L("90 d")
        case .days365: return L("12 m")
        }
    }
}

/// Um ponto do gráfico empilhado: um dia, de um provider.
struct TrendPoint: Equatable {
    let day: String
    let providerId: String
    let tokens: Int
}

/// Transformações puras entre `TokenAnalytics` e o que os gráficos consomem. Fora das
/// views para poder ser testado sem renderizar nada.
enum TrendSeries {
    /// Pontos por provider dentro da janela, ordenados por dia. Dias sem uso de um
    /// provider simplesmente não geram ponto — o gráfico empilhado soma o que existe.
    static func points(byProvider: [String: TokenAnalytics], window: TrendWindow, now: Date = Date()) -> [TrendPoint] {
        let cutoff = dayKeys(lastDays: window.rawValue, now: now)
        let allowed = Set(cutoff)
        var points: [TrendPoint] = []
        for (providerId, analytics) in byProvider {
            for bucket in analytics.dailyBuckets where allowed.contains(bucket.day) && bucket.tokens > 0 {
                points.append(TrendPoint(day: bucket.day, providerId: providerId, tokens: bucket.tokens))
            }
        }
        return points.sorted { ($0.day, $0.providerId) < ($1.day, $1.providerId) }
    }

    /// Série densa dos últimos `lastDays` dias, do mais antigo para o mais recente,
    /// com zero nos dias sem uso — um gráfico de área com buracos mente sobre o ritmo.
    static func dailyTotals(_ analytics: TokenAnalytics, lastDays: Int, now: Date = Date()) -> [DailyTokens] {
        let byDay = Dictionary(uniqueKeysWithValues: analytics.dailyBuckets.map { ($0.day, $0.tokens) })
        return dayKeys(lastDays: lastDays, now: now).map { DailyTokens(day: $0, tokens: byDay[$0] ?? 0) }
    }

    /// Variação relativa. `nil` quando não há base de comparação: crescer a partir de
    /// zero não é uma porcentagem.
    static func delta(current: Int, previous: Int) -> Double? {
        guard previous > 0 else { return nil }
        return (Double(current) - Double(previous)) / Double(previous)
    }

    /// Total por provider na janela, do maior para o menor, sem os zerados.
    static func share(byProvider: [String: TokenAnalytics], lastDays: Int, now: Date = Date()) -> [(providerId: String, tokens: Int)] {
        let allowed = Set(dayKeys(lastDays: lastDays, now: now))
        return byProvider
            .map { entry in
                (providerId: entry.key,
                 tokens: entry.value.dailyBuckets.filter { allowed.contains($0.day) }.reduce(0) { $0 + $1.tokens })
            }
            .filter { $0.tokens > 0 }
            .sorted { ($0.tokens, $1.providerId) > ($1.tokens, $0.providerId) }
    }

    /// Chaves "yyyy-MM-dd" do mais antigo para o mais recente — ordem que `dailyTotals`
    /// expõe direto para o gráfico de área, sem precisar reordenar.
    private static func dayKeys(lastDays: Int, now: Date) -> [String] {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: now)
        return (0..<max(0, lastDays)).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map(TokenAnalytics.dayKey)
        }
    }
}
