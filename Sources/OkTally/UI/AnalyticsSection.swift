// Sources/OkTally/UI/AnalyticsSection.swift
import SwiftUI

/// Painel de estatísticas de uso (referência: painel de analytics do Quotio):
/// linha de chips (lifetime, pico, tarefa mais longa, streaks, hoje/ontem/30d) + heatmap
/// de uso diário estilo GitHub contributions.
struct AnalyticsSection: View {
    let analytics: TokenAnalytics

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            statChips
            if !analytics.dailyBuckets.isEmpty {
                DashboardCard {
                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                        // Mesma chave em caixa normal do resto do app: quem maiusculiza é
                        // o `SectionHeader`, em runtime. Antes esta era a única chave
                        // pré-maiusculizada do catálogo.
                        SectionHeader(L("Tendência de uso"))
                        TokenHeatmapView(analytics: analytics)
                    }
                }
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
        // `StatTile` no lugar dos oito chips iguais desenhados à mão: mesma tipografia,
        // mesmo raio e mesma borda da aba Análise, que renderiza logo acima nesta janela.
        // `fillsHeight` faz todos os tiles de uma linha terminarem juntos.
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Theme.Space.sm)],
                         alignment: .leading, spacing: Theme.Space.sm) {
            ForEach(chips, id: \.1) { value, caption in
                StatTile(title: caption, value: value, fillsHeight: true)
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
///
/// Fix round 1 (revisão de qualidade): a versão anterior usava `GeometryReader` +
/// `.frame(height: 132)` fixo. `GeometryReader` não tem tamanho intrínseco — ele adota
/// o que for proposto — então o `132` era um número inventado para não colapsar a zero,
/// e não batia com a altura real do conteúdo (que varia com `metrics.cell`, entre ~97pt
/// e ~153pt conforme a largura). Agora o heatmap usa dois `Layout` customizados
/// (`HeatmapMonthLabelsLayout` e `HeatmapGridLayout`) que calculam a própria altura a
/// partir de `HeatmapLayout.metrics`, sem nenhum valor fixo — a altura do `VStack` vira a
/// soma natural das alturas dos filhos.
struct TokenHeatmapView: View {
    let analytics: TokenAnalytics

    private static let gap: CGFloat = 2
    /// Mesmo teto do `maxWeeks` default de `HeatmapLayout.metrics` — gera o calendário
    /// completo uma vez; os Layouts decidem quantas colunas finais (mais recentes) cabem
    /// na largura disponível.
    private static let totalWeeks = 53

    private struct Day: Identifiable {
        let id: String
        let date: Date
        let tokens: Int?
        let level: Int
        let column: Int
        let row: Int
    }

    private struct MonthLabelEntry: Identifiable {
        let id: Int
        let column: Int
        let label: String
    }

    var body: some View {
        let days = makeAllDays()
        let totalColumns = (days.map(\.column).max() ?? -1) + 1
        VStack(alignment: .leading, spacing: 3) {
            HeatmapMonthLabelsLayout(gap: Self.gap, totalColumns: totalColumns) {
                ForEach(monthLabelEntries(days: days, totalColumns: totalColumns)) { entry in
                    Text(entry.label)
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                        .layoutValue(key: HeatmapColumnKey.self, value: entry.column)
                }
            }
            HeatmapGridLayout(gap: Self.gap, totalColumns: totalColumns) {
                ForEach(days) { day in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color(level: day.level))
                        .help(tooltip(day))
                        .layoutValue(key: HeatmapColumnRowKey.self, value: (day.column, day.row))
                }
            }
            legend
        }
    }

    /// Legenda "menos → mais", ausente na versão antiga.
    private var legend: some View {
        HStack(spacing: Theme.Space.xs) {
            Spacer()
            Text(L("menos")).font(.system(size: 8)).foregroundStyle(.tertiary)
            ForEach(0...4, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color(level: level))
                    .frame(width: 8, height: 8)
            }
            Text(L("mais")).font(.system(size: 8)).foregroundStyle(.tertiary)
        }
    }

    /// Um rótulo por coluna (vazio quando o mês não mudou em relação à coluna anterior),
    /// calculado sobre a sequência completa de `totalColumns`. Como a decisão de quantas
    /// colunas finais aparecem é feita dentro do `Layout` (que só conhece a largura em
    /// tempo de posicionamento), não dá para "reiniciar" a detecção de mudança de mês só
    /// para a primeira coluna visível — o texto já precisa existir antes disso. Efeito
    /// colateral aceito: em larguras que cortam bem no meio de um mês, a primeira coluna
    /// visível pode não ter rótulo (o mês já teria sido anunciado numa coluna oculta).
    private func monthLabelEntries(days: [Day], totalColumns: Int) -> [MonthLabelEntry] {
        let fmt = DateFormatter()
        fmt.locale = Locale.current
        fmt.setLocalizedDateFormatFromTemplate("MMM")
        let calendar = Calendar(identifier: .gregorian)
        var firstDateByColumn: [Int: Date] = [:]
        for day in days where firstDateByColumn[day.column] == nil {
            firstDateByColumn[day.column] = day.date
        }
        var previousMonth = -1
        var entries: [MonthLabelEntry] = []
        for column in 0..<max(0, totalColumns) {
            guard let date = firstDateByColumn[column] else {
                entries.append(MonthLabelEntry(id: column, column: column, label: ""))
                continue
            }
            let month = calendar.component(.month, from: date)
            if month != previousMonth {
                entries.append(MonthLabelEntry(id: column, column: column, label: fmt.string(from: date)))
                previousMonth = month
            } else {
                entries.append(MonthLabelEntry(id: column, column: column, label: ""))
            }
        }
        return entries
    }

    /// Gera o calendário completo (`totalWeeks` semanas, dom–sáb), com `column`/`row` já
    /// atribuídos — `column` cresce do passado (0) para o presente, `row` é o dia da
    /// semana (0 = domingo). Os `Layout`s decidem depois quantas colunas finais mostrar.
    private func makeAllDays() -> [Day] {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())
        let weekdayIndex = calendar.component(.weekday, from: today) - 1 // 0 = domingo
        let weeks = Self.totalWeeks
        guard let firstCell = calendar.date(byAdding: .day, value: -((weeks - 1) * 7 + weekdayIndex), to: today) else {
            return []
        }
        let levels = analytics.heatLevels()
        let tokensByDay = Dictionary(uniqueKeysWithValues: analytics.dailyBuckets.map { ($0.day, $0.tokens) })

        var days: [Day] = []
        for week in 0..<weeks {
            for weekday in 0..<7 {
                guard let date = calendar.date(byAdding: .day, value: week * 7 + weekday, to: firstCell),
                      date <= today else { continue }
                let key = AnalyticsSection.dayKey(date)
                days.append(Day(id: key, date: date, tokens: tokensByDay[key], level: levels[key] ?? 0, column: week, row: weekday))
            }
        }
        return days
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

/// Chaves de `layoutValue` usadas pelos `Layout`s do heatmap para saber em qual
/// coluna/linha cada subview lógica deve ser posicionada — a alternativa a embutir
/// `.frame(width:height:)`/offsets fixos em cada célula.
private struct HeatmapColumnKey: LayoutValueKey {
    static let defaultValue: Int = 0
}

private struct HeatmapColumnRowKey: LayoutValueKey {
    static let defaultValue: (column: Int, row: Int) = (0, 0)
}

/// Posiciona um rótulo de mês por coluna, nas mesmas coordenadas X do `HeatmapGridLayout`
/// correspondente. Sem altura fixa: a altura vem do tamanho natural do texto
/// (`sizeThatFits`). A largura reportada é a proposta pelo pai (para não encolher o
/// `VStack` quando o grid não preenche tudo); internamente as colunas ficam centralizadas
/// se `HeatmapLayout.metrics` travar nos tetos de célula/semanas antes de consumir toda a
/// largura (larguras muito grandes).
private struct HeatmapMonthLabelsLayout: Layout {
    let gap: CGFloat
    let totalColumns: Int

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard totalColumns > 0 else { return .zero }
        let metrics = HeatmapLayout.metrics(availableWidth: proposal.width ?? 0, gap: gap)
        let shown = min(metrics.weeks, totalColumns)
        let gridWidth = CGFloat(shown) * metrics.cell + CGFloat(max(0, shown - 1)) * gap
        let width = proposal.width ?? gridWidth
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard totalColumns > 0, !subviews.isEmpty else { return }
        let metrics = HeatmapLayout.metrics(availableWidth: proposal.width ?? 0, gap: gap)
        let shown = min(metrics.weeks, totalColumns)
        let hidden = totalColumns - shown
        let gridWidth = CGFloat(shown) * metrics.cell + CGFloat(max(0, shown - 1)) * gap
        let leadingInset = max(0, (bounds.width - gridWidth) / 2)
        for subview in subviews {
            let column = subview[HeatmapColumnKey.self]
            guard column >= hidden else {
                // `.fixedSize()` no rótulo ignora o `proposal: .zero` e desenha no tamanho
                // natural mesmo assim — por isso não basta propor zero, é preciso tirar a
                // subview de cena (senão o rótulo de uma coluna oculta sobrepõe o da
                // primeira coluna visível).
                subview.place(at: CGPoint(x: bounds.minX - 10_000, y: bounds.minY), proposal: .zero)
                continue
            }
            let visibleColumn = column - hidden
            let x = bounds.minX + leadingInset + CGFloat(visibleColumn) * (metrics.cell + gap)
            subview.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading, proposal: .unspecified)
        }
    }
}

/// Posiciona as células do grid por (coluna, linha), forçando `cell × cell` em cada uma
/// via o `proposal` passado a `place(...)` — não há `.frame(width:height:)` fixo em
/// nenhuma célula. Altura sempre `7 × cell + 6 × gap` (7 dias da semana), calculada a
/// partir de `metrics.cell`; nunca um valor fixo. Mesma centralização de
/// `HeatmapMonthLabelsLayout` para o caso de largura muito grande.
private struct HeatmapGridLayout: Layout {
    let gap: CGFloat
    let totalColumns: Int
    private let rows = 7

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard totalColumns > 0 else { return .zero }
        let metrics = HeatmapLayout.metrics(availableWidth: proposal.width ?? 0, gap: gap)
        let shown = min(metrics.weeks, totalColumns)
        let gridWidth = CGFloat(shown) * metrics.cell + CGFloat(max(0, shown - 1)) * gap
        let width = proposal.width ?? gridWidth
        let height = CGFloat(rows) * metrics.cell + CGFloat(rows - 1) * gap
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard totalColumns > 0, !subviews.isEmpty else { return }
        let metrics = HeatmapLayout.metrics(availableWidth: proposal.width ?? 0, gap: gap)
        let shown = min(metrics.weeks, totalColumns)
        let hidden = totalColumns - shown
        let gridWidth = CGFloat(shown) * metrics.cell + CGFloat(max(0, shown - 1)) * gap
        let leadingInset = max(0, (bounds.width - gridWidth) / 2)
        for subview in subviews {
            let (column, row) = subview[HeatmapColumnRowKey.self]
            guard column >= hidden else {
                // Mesmo cuidado do HeatmapMonthLabelsLayout: tira a subview de cena em vez
                // de confiar só no proposal zero.
                subview.place(at: CGPoint(x: bounds.minX - 10_000, y: bounds.minY), proposal: .zero)
                continue
            }
            let visibleColumn = column - hidden
            let x = bounds.minX + leadingInset + CGFloat(visibleColumn) * (metrics.cell + gap)
            let y = bounds.minY + CGFloat(row) * (metrics.cell + gap)
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: metrics.cell, height: metrics.cell))
        }
    }
}
