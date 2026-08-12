// Sources/OkTally/UI/AnalyticsSection.swift
import SwiftUI

/// Painel de estatísticas de uso (referência: painel de analytics do Quotio):
/// linha de chips (lifetime, pico, tarefa mais longa, streaks, hoje/ontem/30d) + heatmap
/// de uso diário estilo GitHub contributions.
struct AnalyticsSection: View {
    let analytics: TokenAnalytics

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            statChips
            if !analytics.dailyBuckets.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("TENDÊNCIA DE USO"))
                        .font(.system(size: 9, weight: .semibold)).tracking(0.5)
                        .foregroundStyle(.secondary)
                    TokenHeatmapView(analytics: analytics)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.045)))
            }
        }
    }

    private var statChips: some View {
        let today = Self.dayKey(Date())
        let yesterday = Self.dayKey(Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        var chips: [(String, String)] = []
        if let lifetime = analytics.effectiveLifetimeTokens {
            chips.append((TokenAnalytics.compactTokens(lifetime), L("Tokens totais")))
        }
        if let peak = analytics.effectivePeakDailyTokens {
            chips.append((TokenAnalytics.compactTokens(peak), L("Pico diário")))
        }
        if let longest = analytics.longestRunningTurnSeconds {
            chips.append((TokenAnalytics.durationLabel(longest), L("Tarefa mais longa")))
        }
        if let streak = analytics.effectiveCurrentStreakDays() {
            chips.append((LF("%d dias", streak), L("Streak atual")))
        }
        if let longestStreak = analytics.effectiveLongestStreakDays {
            chips.append((LF("%d dias", longestStreak), L("Maior streak")))
        }
        let dayValue: (String) -> String = { key in
            guard let tokens = analytics.tokens(onDay: key), tokens > 0 else { return L("Sem dados") }
            return LF("%@ tokens", TokenAnalytics.compactTokens(tokens))
        }
        chips.append((dayValue(today), L("Hoje")))
        chips.append((dayValue(yesterday), L("Ontem")))
        if analytics.tokensLast30Days > 0 {
            chips.append((LF("%@ tokens", TokenAnalytics.compactTokens(analytics.tokensLast30Days)), L("Últimos 30 dias")))
        }
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(chips, id: \.1) { value, caption in
                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                    Text(caption)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.045)))
            }
        }
    }

    static func dayKey(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }
}

/// Heatmap de contribuições: colunas = semanas (dom–sáb), intensidade por quartil dos
/// dias ativos (`TokenAnalytics.heatLevels`). Tooltip por célula com o valor exato.
struct TokenHeatmapView: View {
    let analytics: TokenAnalytics
    var weeks: Int = 26

    private static let cell: CGFloat = 10
    private static let gap: CGFloat = 2

    private struct Day: Identifiable {
        let id: String
        let date: Date
        let tokens: Int?
        let level: Int
    }

    var body: some View {
        let columns = makeColumns()
        VStack(alignment: .leading, spacing: 3) {
            monthLabels(columns)
            HStack(alignment: .top, spacing: Self.gap) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                    VStack(spacing: Self.gap) {
                        ForEach(column) { day in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(color(level: day.level))
                                .frame(width: Self.cell, height: Self.cell)
                                .help(tooltip(day))
                        }
                    }
                }
            }
        }
    }

    private func monthLabels(_ columns: [[Day]]) -> some View {
        let fmt = DateFormatter()
        fmt.locale = Locale.current
        fmt.setLocalizedDateFormatFromTemplate("MMM")
        let calendar = Calendar(identifier: .gregorian)
        var previousMonth = -1
        var labels: [String] = []
        for column in columns {
            let month = column.first.map { calendar.component(.month, from: $0.date) } ?? -1
            if month != previousMonth, let first = column.first {
                labels.append(fmt.string(from: first.date))
                previousMonth = month
            } else {
                labels.append("")
            }
        }
        // ZStack com offsets absolutos: um frame por coluna truncaria o nome do mês na
        // largura da célula (10 pt).
        return ZStack(alignment: .topLeading) {
            Color.clear.frame(height: 10)
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                if !label.isEmpty {
                    Text(label)
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                        .offset(x: CGFloat(index) * (Self.cell + Self.gap))
                }
            }
        }
    }

    private func makeColumns() -> [[Day]] {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())
        let weekdayIndex = calendar.component(.weekday, from: today) - 1 // 0 = domingo
        guard let firstCell = calendar.date(byAdding: .day, value: -((weeks - 1) * 7 + weekdayIndex), to: today) else {
            return []
        }
        let levels = analytics.heatLevels()
        let tokensByDay = Dictionary(uniqueKeysWithValues: analytics.dailyBuckets.map { ($0.day, $0.tokens) })

        var columns: [[Day]] = []
        for week in 0..<weeks {
            var column: [Day] = []
            for weekday in 0..<7 {
                guard let date = calendar.date(byAdding: .day, value: week * 7 + weekday, to: firstCell),
                      date <= today else { continue }
                let key = AnalyticsSection.dayKey(date)
                column.append(Day(id: key, date: date, tokens: tokensByDay[key], level: levels[key] ?? 0))
            }
            if !column.isEmpty { columns.append(column) }
        }
        return columns
    }

    private func color(level: Int) -> Color {
        switch level {
        case 1: return .blue.opacity(0.30)
        case 2: return .blue.opacity(0.50)
        case 3: return .blue.opacity(0.75)
        case 4: return .blue
        default: return Color.primary.opacity(0.06)
        }
    }

    private func tooltip(_ day: Day) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale.current
        fmt.setLocalizedDateFormatFromTemplate("d MMM")
        let dateLabel = fmt.string(from: day.date)
        guard let tokens = day.tokens, tokens > 0 else { return LF("%@: sem uso", dateLabel) }
        return LF("%@: %@ tokens", dateLabel, TokenAnalytics.compactTokens(tokens))
    }
}
