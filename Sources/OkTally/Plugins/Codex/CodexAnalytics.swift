// Sources/OkTally/Plugins/Codex/CodexAnalytics.swift
import Foundation

/// Estatísticas de conta do Codex vindas do endpoint de perfil do ChatGPT
/// (`backend-api/wham/profiles/me` — mesma fonte do painel de analytics do Quotio):
/// tokens lifetime/pico, streaks, tarefa mais longa e baldes diários para o heatmap.
///
/// O parser é deliberadamente tolerante (endpoint não documentado): aceita snake_case e
/// camelCase, baldes como array de objetos ou dicionário data→tokens, e contagens como
/// total direto ou input+output — a mesma robustez a drift adotada nos outros providers.
struct CodexDailyTokens: Equatable {
    /// Dia no formato "yyyy-MM-dd" (UTC do backend; usado só como chave/etiqueta).
    let day: String
    let tokens: Int
}

struct CodexAnalytics: Equatable {
    let lifetimeTokens: Int?
    let peakDailyTokens: Int?
    let currentStreakDays: Int?
    let longestStreakDays: Int?
    let longestRunningTurnSeconds: Int?
    /// Ordenado por dia ascendente.
    let dailyBuckets: [CodexDailyTokens]

    // MARK: - Parsing

    init?(profileJSON data: Data) {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let stats = json["stats"] as? [String: Any] else { return nil }
        lifetimeTokens = Self.int(stats["lifetime_tokens"] ?? stats["lifetimeTokens"])
        peakDailyTokens = Self.int(stats["peak_daily_tokens"] ?? stats["peakDailyTokens"])
        currentStreakDays = Self.int(stats["current_streak_days"] ?? stats["currentStreakDays"])
        longestStreakDays = Self.int(stats["longest_streak_days"] ?? stats["longestStreakDays"])
        longestRunningTurnSeconds = Self.int(stats["longest_running_turn_sec"] ?? stats["longestRunningTurnSec"])
        dailyBuckets = Self.decodeBuckets(stats["daily_usage_buckets"] ?? stats["dailyUsageBuckets"])
            .sorted { $0.day < $1.day }
        if lifetimeTokens == nil && peakDailyTokens == nil && dailyBuckets.isEmpty { return nil }
    }

    init(
        lifetimeTokens: Int?,
        peakDailyTokens: Int?,
        currentStreakDays: Int?,
        longestStreakDays: Int?,
        longestRunningTurnSeconds: Int?,
        dailyBuckets: [CodexDailyTokens]
    ) {
        self.lifetimeTokens = lifetimeTokens
        self.peakDailyTokens = peakDailyTokens
        self.currentStreakDays = currentStreakDays
        self.longestStreakDays = longestStreakDays
        self.longestRunningTurnSeconds = longestRunningTurnSeconds
        self.dailyBuckets = dailyBuckets
    }

    private static func decodeBuckets(_ value: Any?) -> [CodexDailyTokens] {
        if let array = value as? [Any] {
            return array.compactMap { element in
                guard let object = element as? [String: Any],
                      let day = string(object["date"] ?? object["day"] ?? object["bucket"] ?? object["start_date"] ?? object["startDate"]),
                      let tokens = tokenCount(object)
                else { return nil }
                return CodexDailyTokens(day: String(day.prefix(10)), tokens: tokens)
            }
        }
        if let object = value as? [String: Any] {
            return object.compactMap { key, element in
                guard let tokens = tokenCount(element) else { return nil }
                return CodexDailyTokens(day: String(key.prefix(10)), tokens: tokens)
            }
        }
        return []
    }

    private static func tokenCount(_ value: Any?) -> Int? {
        if let object = value as? [String: Any] {
            if let total = int(object["tokens"] ?? object["token_count"] ?? object["tokenCount"]
                ?? object["total_tokens"] ?? object["totalTokens"] ?? object["value"] ?? object["count"]) {
                return total
            }
            let input = int(object["input_tokens"] ?? object["inputTokens"]) ?? 0
            let output = int(object["output_tokens"] ?? object["outputTokens"]) ?? 0
            return input + output > 0 ? input + output : nil
        }
        return int(value)
    }

    private static func int(_ value: Any?) -> Int? {
        switch value {
        case let v as Int: return v
        case let v as Double: return Int(v)
        case let v as String: return Int(v) ?? Double(v).map(Int.init)
        default: return nil
        }
    }

    private static func string(_ value: Any?) -> String? {
        value as? String
    }

    // MARK: - Derivações para a UI

    func tokens(onDay day: String) -> Int? {
        dailyBuckets.first { $0.day == day }?.tokens
    }

    var tokensLast30Days: Int {
        dailyBuckets.sorted { $0.day > $1.day }.prefix(30).reduce(0) { $0 + $1.tokens }
    }

    /// "1.2K" / "3.4M" / "2.2B" — mesma escala compacta do painel de referência.
    static func compactTokens(_ value: Int) -> String {
        let v = Double(value)
        let absV = abs(v)
        func trim(_ s: String) -> String {
            s.replacingOccurrences(of: ".0B", with: "B")
                .replacingOccurrences(of: ".0M", with: "M")
                .replacingOccurrences(of: ".0K", with: "K")
        }
        if absV >= 1_000_000_000 { return trim(String(format: "%.1fB", v / 1_000_000_000)) }
        if absV >= 1_000_000 { return trim(String(format: "%.1fM", v / 1_000_000)) }
        if absV >= 1_000 { return trim(String(format: "%.1fK", v / 1_000)) }
        return "\(value)"
    }

    static func durationLabel(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(secs)s" }
        return "\(secs)s"
    }

    /// Intensidade 0–4 por dia para o heatmap: 0 = sem uso; 1–4 = quartis dos dias com
    /// uso, calculados sobre os próprios baldes (padrão GitHub contributions).
    func heatLevels() -> [String: Int] {
        let active = dailyBuckets.filter { $0.tokens > 0 }.map(\.tokens).sorted()
        guard !active.isEmpty else { return [:] }
        func quantile(_ q: Double) -> Int {
            let index = Int((Double(active.count - 1) * q).rounded())
            return active[index]
        }
        let q1 = quantile(0.25), q2 = quantile(0.5), q3 = quantile(0.75)
        var levels: [String: Int] = [:]
        for bucket in dailyBuckets {
            guard bucket.tokens > 0 else { continue }
            if bucket.tokens <= q1 { levels[bucket.day] = 1 }
            else if bucket.tokens <= q2 { levels[bucket.day] = 2 }
            else if bucket.tokens <= q3 { levels[bucket.day] = 3 }
            else { levels[bucket.day] = 4 }
        }
        return levels
    }
}
