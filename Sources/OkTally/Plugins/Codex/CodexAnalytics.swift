// Sources/OkTally/Plugins/Codex/CodexAnalytics.swift
import Foundation

/// Parsing das estatísticas de conta do Codex vindas do endpoint de perfil do ChatGPT
/// (`backend-api/wham/profiles/me`) para o `TokenAnalytics` genérico.
///
/// Deliberadamente tolerante (endpoint não documentado): aceita snake_case e camelCase,
/// baldes como array de objetos ou dicionário data→tokens, e contagens como total direto
/// ou input+output — a mesma robustez a drift adotada nos outros providers.
extension TokenAnalytics {
    init?(codexProfileJSON data: Data) {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let stats = json["stats"] as? [String: Any] else { return nil }
        let lifetime = Self.int(stats["lifetime_tokens"] ?? stats["lifetimeTokens"])
        let peak = Self.int(stats["peak_daily_tokens"] ?? stats["peakDailyTokens"])
        let buckets = Self.decodeBuckets(stats["daily_usage_buckets"] ?? stats["dailyUsageBuckets"])
        if lifetime == nil && peak == nil && buckets.isEmpty { return nil }
        self.init(
            lifetimeTokens: lifetime,
            peakDailyTokens: peak,
            currentStreakDays: Self.int(stats["current_streak_days"] ?? stats["currentStreakDays"]),
            longestStreakDays: Self.int(stats["longest_streak_days"] ?? stats["longestStreakDays"]),
            longestRunningTurnSeconds: Self.int(stats["longest_running_turn_sec"] ?? stats["longestRunningTurnSec"]),
            dailyBuckets: buckets
        )
    }

    private static func decodeBuckets(_ value: Any?) -> [DailyTokens] {
        if let array = value as? [Any] {
            return array.compactMap { element in
                guard let object = element as? [String: Any],
                      let day = object["date"] as? String ?? object["day"] as? String
                        ?? object["bucket"] as? String ?? object["start_date"] as? String
                        ?? object["startDate"] as? String,
                      let tokens = tokenCount(object)
                else { return nil }
                return DailyTokens(day: String(day.prefix(10)), tokens: tokens)
            }
        }
        if let object = value as? [String: Any] {
            return object.compactMap { key, element in
                guard let tokens = tokenCount(element) else { return nil }
                return DailyTokens(day: String(key.prefix(10)), tokens: tokens)
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
}
