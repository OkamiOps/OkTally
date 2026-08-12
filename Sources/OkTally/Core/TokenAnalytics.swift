// Sources/OkTally/Core/TokenAnalytics.swift
import Foundation

/// Um dia de uso em tokens. `day` é "yyyy-MM-dd" e serve de chave/etiqueta.
struct DailyTokens: Equatable {
    let day: String
    let tokens: Int
}

/// Estatísticas de uso em tokens de uma fonte qualquer (API do Codex, JSONL local do
/// Claude Code, banco do OpenCode…). Campos armazenados são opcionais porque só algumas
/// fontes os fornecem prontos; os `effective*` caem para derivações dos próprios baldes,
/// então toda fonte ganha streaks/pico/total de graça.
struct TokenAnalytics: Equatable {
    let lifetimeTokens: Int?
    let peakDailyTokens: Int?
    let currentStreakDays: Int?
    let longestStreakDays: Int?
    let longestRunningTurnSeconds: Int?
    /// Ordenado por dia ascendente.
    let dailyBuckets: [DailyTokens]

    init(
        lifetimeTokens: Int? = nil,
        peakDailyTokens: Int? = nil,
        currentStreakDays: Int? = nil,
        longestStreakDays: Int? = nil,
        longestRunningTurnSeconds: Int? = nil,
        dailyBuckets: [DailyTokens]
    ) {
        self.lifetimeTokens = lifetimeTokens
        self.peakDailyTokens = peakDailyTokens
        self.currentStreakDays = currentStreakDays
        self.longestStreakDays = longestStreakDays
        self.longestRunningTurnSeconds = longestRunningTurnSeconds
        self.dailyBuckets = dailyBuckets.sorted { $0.day < $1.day }
    }

    // MARK: - Valores efetivos (armazenado ou derivado dos baldes)

    /// Total da fonte quando ela sabe o lifetime real (Codex); senão a soma do que foi
    /// coletado localmente — um piso honesto, não o histórico completo.
    var effectiveLifetimeTokens: Int? {
        if let lifetimeTokens { return lifetimeTokens }
        let sum = dailyBuckets.reduce(0) { $0 + $1.tokens }
        return sum > 0 ? sum : nil
    }

    var effectivePeakDailyTokens: Int? {
        if let peakDailyTokens { return peakDailyTokens }
        return dailyBuckets.map(\.tokens).max().flatMap { $0 > 0 ? $0 : nil }
    }

    /// Streak atual: dias consecutivos com uso terminando hoje — ou ontem, se hoje ainda
    /// não teve uso (semântica GitHub).
    func effectiveCurrentStreakDays(now: Date = Date()) -> Int? {
        if let currentStreakDays { return currentStreakDays }
        let active = activeDaySet()
        guard !active.isEmpty else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        var cursor = calendar.startOfDay(for: now)
        if !active.contains(Self.dayKey(cursor)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor),
                  active.contains(Self.dayKey(yesterday)) else { return 0 }
            cursor = yesterday
        }
        var streak = 0
        while active.contains(Self.dayKey(cursor)) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    var effectiveLongestStreakDays: Int? {
        if let longestStreakDays { return longestStreakDays }
        let days = dailyBuckets.filter { $0.tokens > 0 }.compactMap { Self.date(fromDay: $0.day) }.sorted()
        guard !days.isEmpty else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        var longest = 1, current = 1
        for (previous, next) in zip(days, days.dropFirst()) {
            let gap = calendar.dateComponents([.day], from: previous, to: next).day ?? .max
            current = gap == 1 ? current + 1 : 1
            longest = max(longest, current)
        }
        return longest
    }

    // MARK: - Consultas

    func tokens(onDay day: String) -> Int? {
        dailyBuckets.first { $0.day == day }?.tokens
    }

    var tokensLast30Days: Int {
        dailyBuckets.sorted { $0.day > $1.day }.prefix(30).reduce(0) { $0 + $1.tokens }
    }

    /// Intensidade 0–4 por dia para o heatmap: 0 = sem uso; 1–4 = quartis dos dias com
    /// uso (padrão GitHub contributions).
    func heatLevels() -> [String: Int] {
        let active = dailyBuckets.filter { $0.tokens > 0 }.map(\.tokens).sorted()
        guard !active.isEmpty else { return [:] }
        func quantile(_ q: Double) -> Int {
            active[Int((Double(active.count - 1) * q).rounded())]
        }
        let q1 = quantile(0.25), q2 = quantile(0.5), q3 = quantile(0.75)
        var levels: [String: Int] = [:]
        for bucket in dailyBuckets where bucket.tokens > 0 {
            if bucket.tokens <= q1 { levels[bucket.day] = 1 }
            else if bucket.tokens <= q2 { levels[bucket.day] = 2 }
            else if bucket.tokens <= q3 { levels[bucket.day] = 3 }
            else { levels[bucket.day] = 4 }
        }
        return levels
    }

    // MARK: - Agregação

    /// Soma várias fontes num painel só: baldes somados por dia; lifetime = soma dos
    /// efetivos; pico/streaks recalculados sobre os baldes somados (o pico agregado num
    /// mesmo dia pode superar o pico individual de qualquer fonte); tarefa mais longa =
    /// máximo entre as fontes.
    static func aggregate(_ sources: [TokenAnalytics]) -> TokenAnalytics? {
        let nonEmpty = sources.filter { !$0.dailyBuckets.isEmpty || $0.effectiveLifetimeTokens != nil }
        guard !nonEmpty.isEmpty else { return nil }
        var byDay: [String: Int] = [:]
        for source in nonEmpty {
            for bucket in source.dailyBuckets {
                byDay[bucket.day, default: 0] += bucket.tokens
            }
        }
        let buckets = byDay.map { DailyTokens(day: $0.key, tokens: $0.value) }.sorted { $0.day < $1.day }
        let lifetimes = nonEmpty.compactMap(\.effectiveLifetimeTokens)
        return TokenAnalytics(
            lifetimeTokens: lifetimes.isEmpty ? nil : lifetimes.reduce(0, +),
            peakDailyTokens: nil,
            currentStreakDays: nil,
            longestStreakDays: nil,
            longestRunningTurnSeconds: nonEmpty.compactMap(\.longestRunningTurnSeconds).max(),
            dailyBuckets: buckets
        )
    }

    // MARK: - Formatação

    /// "1.2K" / "3.4M" / "2.2B" — escala compacta do painel de referência.
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

    // MARK: - Datas

    static func dayKey(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }

    static func date(fromDay day: String) -> Date? {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.date(from: day)
    }

    private func activeDaySet() -> Set<String> {
        Set(dailyBuckets.filter { $0.tokens > 0 }.map(\.day))
    }
}
