// Sources/OkTally/UI/QuotaUsageSection.swift
import SwiftUI

/// Estatísticas derivadas do histórico de quota medido pelo próprio app. Esta seção
/// existe para providers que não expõem tokens: ela mostra consumo real em pontos
/// percentuais da janela, com a base explicitada, em vez de inventar volume de tokens.
struct QuotaUsageSection: View {
    let statistics: QuotaUsageStatistics
    let tint: Color

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                HStack(alignment: .firstTextBaseline) {
                    SectionHeader(L("Estatísticas de uso"))
                    Text(L("derivado da quota local"))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(tint.opacity(0.12)))
                    Spacer(minLength: 0)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: Theme.Space.lg)], spacing: Theme.Space.md) {
                    metric(L("Uso atual"), percent(statistics.currentUsedPercent, suffix: "%"))
                    metric(L("Consumo 24h"), percent(statistics.consumedLast24h))
                    metric(L("Consumo 7d"), percent(statistics.consumedLast7d))
                    metric(L("Dias observados"), "\(statistics.observedDays)")
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        SectionHeader(L("Tendência de consumo"))
                        Spacer()
                        Text(L("pontos percentuais por dia"))
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    consumptionBars
                }

                Text(L("Calculado a partir das leituras de quota gravadas nesta máquina. Quedas por reset não contam como consumo; uso anterior à primeira leitura não é inventado."))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionHeader(label)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Heatmap estilo GitHub, mas sem mentir a unidade: cada quadrado é um dia de
    /// consumo em pontos percentuais de quota. São oito semanas porque o histórico de
    /// quota do próprio app costuma existir muito antes de qualquer fonte de tokens.
    private var consumptionBars: some View {
        let columns = heatmapColumns
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 4) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                    VStack(spacing: 4) {
                        ForEach(column, id: \.day) { point in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(color(for: point.percentPoints))
                                .frame(width: 11, height: 11)
                                .help(LF("%@: %@", point.day, percent(point.percentPoints)))
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 4) {
                Text(L("menos"))
                ForEach([0.0, 0.28, 0.5, 0.76, 1.0], id: \.self) { opacity in
                    RoundedRectangle(cornerRadius: 2).fill(opacity == 0 ? Color.primary.opacity(0.08) : tint.opacity(opacity))
                        .frame(width: 8, height: 8)
                }
                Text(L("mais"))
                Spacer()
                Text(L("8 semanas"))
            }
            .font(.system(size: 8))
            .foregroundStyle(.tertiary)
        }
    }

    private var heatmapColumns: [[DailyQuotaConsumption]] {
        let days = statistics.dailyConsumption
        guard !days.isEmpty else { return [] }
        return stride(from: 0, to: days.count, by: 7).map { start in
            Array(days[start..<min(start + 7, days.count)])
        }
    }

    private func color(for value: Double) -> Color {
        guard value > 0 else { return Color.primary.opacity(0.08) }
        let positive = statistics.dailyConsumption.map(\.percentPoints).filter { $0 > 0 }.sorted()
        guard !positive.isEmpty else { return Color.primary.opacity(0.08) }
        func percentile(_ p: Double) -> Double {
            positive[min(positive.count - 1, Int((Double(positive.count - 1)) * p))]
        }
        switch value {
        case ..<percentile(0.25): return tint.opacity(0.30)
        case ..<percentile(0.50): return tint.opacity(0.52)
        case ..<percentile(0.75): return tint.opacity(0.76)
        default: return tint
        }
    }

    private func percent(_ value: Double, suffix: String = " pts") -> String {
        String(format: value >= 10 ? "%.0f%@" : "%.1f%@", value, suffix)
    }

    private func dayLabel(_ day: String) -> String {
        guard let date = TokenAnalytics.date(fromDay: day) else { return "" }
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE"
        fmt.locale = .autoupdatingCurrent
        return fmt.string(from: date).prefix(3).uppercased()
    }
}
