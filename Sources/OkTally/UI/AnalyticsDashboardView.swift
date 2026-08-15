// Sources/OkTally/UI/AnalyticsDashboardView.swift
import SwiftUI

/// A aba Análise redesenhada como grade bento: herói assimétrico, tendência de largura
/// total, recorte por provedor e faixa de cotas. Substitui a pilha de oito chips iguais,
/// que não dizia o que olhar primeiro.
struct AnalyticsDashboardView: View {
    @ObservedObject var appModel: AppModel

    @State private var window: TrendWindow = .days30
    @State private var showsHeatmap = false

    @Environment(\.isStaticRender) private var isStaticRender

    private var byProvider: [String: TokenAnalytics] {
        appModel.analyticsByProvider
    }

    private var aggregated: TokenAnalytics? { appModel.aggregatedAnalytics }

    private func providerName(_ id: String) -> String {
        appModel.orderedProviders.first { $0.id == id }?.displayName ?? id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            if let aggregated {
                heroRow(aggregated)
                trendCard()
                providerRow()
                quotaStrip()
                footnote
            } else if appModel.analyticsProviderIds.isEmpty {
                Text(L("Nenhuma fonte de análise disponível — conecte Codex, Claude Code ou OpenCode."))
                    .foregroundStyle(.secondary)
            } else {
                Text(L("Carregando estatísticas de uso…"))
                    .foregroundStyle(.secondary)
            }
        }
        .task { await appModel.loadAllAnalyticsIfStale() }
    }

    /// Texto discreto para quando um gráfico ficaria sem nada para desenhar. Os três
    /// gráficos não tratam coleção vazia por conta própria: o donut vira um anel oco e a
    /// escala de cor do empilhado recebe domínio vazio.
    private var emptyPeriod: some View {
        Text(L("Sem dados no período"))
            .font(Theme.Font.body)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Linha 1: herói

    private func heroRow(_ analytics: TokenAnalytics) -> some View {
        let totals = TrendSeries.dailyTotals(analytics, lastDays: 14)
        // `dailyTotals` devolve em ordem cronológica (mais antigo primeiro): hoje é o
        // último elemento, ontem o penúltimo.
        let today = totals.last?.tokens ?? 0
        let yesterday = totals.dropLast().last?.tokens ?? 0
        let hasVolume = totals.contains { $0.tokens > 0 }
        let streak = analytics.effectiveCurrentStreakDays() ?? 0
        let longest = analytics.effectiveLongestStreakDays ?? max(streak, 1)
        return HStack(alignment: .top, spacing: Theme.Space.md) {
            // Ambas as colunas esticam até a altura da linha: quem for mais alta manda, e
            // nenhuma das duas precisa de altura fixa.
            DashboardCard(fillsHeight: true) {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.sm) {
                        SectionHeader(L("Hoje"))
                        DeltaBadge(fraction: TrendSeries.delta(current: today, previous: yesterday))
                        Spacer(minLength: 0)
                    }
                    Text(TokenAnalytics.compactTokens(today))
                        .font(Theme.Font.metricHero)
                        .monospacedDigit()
                    Text(LF("ontem: %@", TokenAnalytics.compactTokens(yesterday)))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: Theme.Space.sm)
                    // Uma área toda em zero desenha uma reta colada no eixo, que parece
                    // um gráfico quebrado; melhor dizer que não houve uso.
                    if hasVolume {
                        DailyTokensAreaChart(points: totals, color: .accentColor)
                            .frame(height: 72)
                    } else {
                        emptyPeriod.frame(height: 72)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: Theme.Space.md) {
                DashboardCard(padding: Theme.Space.md) {
                    HStack(spacing: Theme.Space.md) {
                        ProgressRing(
                            fraction: longest > 0 ? Double(streak) / Double(longest) : 0,
                            color: .orange,
                            size: 42,
                            label: "\(streak)"
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            SectionHeader(L("Streak atual"))
                            Text(LF("recorde: %d dias", longest))
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 0)
                    }
                }
                StatTile(
                    title: L("Pico diário"),
                    value: analytics.effectivePeakDailyTokens.map(TokenAnalytics.compactTokens) ?? "—",
                    caption: analytics.longestRunningTurnSeconds.map { LF("tarefa mais longa: %@", TokenAnalytics.durationLabel($0)) }
                )
                // Terceiro tile: antes a coluna tinha dois cards magros e o "Pico diário"
                // era esticado sozinho até a altura do card da esquerda — mais da metade
                // dele saía vazia. Com um número a mais a coluna se preenche de conteúdo
                // real, e só o último tile absorve a sobra de altura.
                StatTile(
                    title: L("Últimos 30 dias"),
                    value: TokenAnalytics.compactTokens(analytics.tokensLast30Days),
                    caption: analytics.effectiveLifetimeTokens.map { LF("total: %@", TokenAnalytics.compactTokens($0)) },
                    fillsHeight: true
                )
            }
            .frame(width: 230)
        }
    }

    // MARK: - Linha 2: tendência

    private func trendCard() -> some View {
        let points = TrendSeries.points(byProvider: byProvider, window: window)
        return DashboardCard {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                HStack(spacing: Theme.Space.sm) {
                    SectionHeader(L("Tendência de uso"))
                    Spacer()
                    windowPicker
                    Toggle(isOn: $showsHeatmap) {
                        Image(systemName: showsHeatmap ? "square.grid.3x3.fill" : "chart.bar.fill")
                    }
                    .toggleStyle(.button)
                    .help(showsHeatmap ? L("Ver como barras") : L("Ver como heatmap"))
                    .accessibilityLabel(showsHeatmap ? L("Ver como barras") : L("Ver como heatmap"))
                }
                if showsHeatmap, let aggregated {
                    TokenHeatmapView(analytics: aggregated)
                } else if points.isEmpty {
                    emptyPeriod.frame(height: 200)
                } else {
                    StackedProviderBarChart(points: points, providerName: providerName)
                        .frame(height: 200)
                }
            }
        }
    }

    /// Segmentado nativo: é ele que dá semântica de seleção ao VoiceOver, navegação por
    /// setas dentro do grupo e o estilo do sistema. O `ImageRenderer` não sabe desenhar
    /// controles do AppKit, então — e só então — cai num substituto estático; o problema
    /// é do harness de render, não do produto.
    @ViewBuilder
    private var windowPicker: some View {
        if isStaticRender {
            staticWindowPicker
        } else {
            Picker("", selection: $window) {
                ForEach(TrendWindow.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 190)
        }
    }

    /// Desenho equivalente do segmentado, sem interação — existe apenas para os PNGs.
    private var staticWindowPicker: some View {
        HStack(spacing: 2) {
            ForEach(TrendWindow.allCases, id: \.self) { option in
                let selected = option == window
                Text(option.label)
                    .font(.system(size: 11, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, Theme.Space.md)
                    .frame(height: 20)
                    .background {
                        if selected {
                            Capsule().fill(Theme.surfaceRaised())
                        }
                    }
            }
        }
        .padding(2)
        .background(Capsule().fill(Theme.surface()))
        .overlay(Capsule().strokeBorder(Theme.border()))
    }

    // MARK: - Linha 3: por provedor

    private func providerRow() -> some View {
        let share = TrendSeries.share(byProvider: byProvider, lastDays: 30)
        let total = share.reduce(0) { $0 + $1.tokens }
        return HStack(alignment: .top, spacing: Theme.Space.md) {
            DashboardCard {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    SectionHeader(L("Por provedor"))
                    if share.isEmpty {
                        emptyPeriod
                    } else {
                        ForEach(share, id: \.providerId) { entry in
                            providerLine(entry, total: total)
                        }
                    }
                }
            }
            DashboardCard {
                VStack(spacing: Theme.Space.sm) {
                    SectionHeader(L("Participação"))
                    if share.isEmpty {
                        emptyPeriod.frame(height: 150)
                    } else {
                        ProviderShareDonut(share: share)
                            .frame(height: 150)
                    }
                }
            }
            .frame(width: 210)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func providerLine(_ entry: (providerId: String, tokens: Int), total: Int) -> some View {
        let color = ProviderPalette.color(for: entry.providerId)
        // `total` zerado sairia como NaN, e `max(0, min(1, .nan))` é 1.0 em Swift: a
        // barra e o anel apareceriam cheios.
        let fraction = total > 0 ? Double(entry.tokens) / Double(total) : 0
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(spacing: Theme.Space.sm) {
                Text(ProviderPalette.glyph(forId: entry.providerId))
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(color)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(color.opacity(0.16)))
                Text(providerName(entry.providerId)).font(Theme.Font.body)
                Spacer(minLength: Theme.Space.sm)
                if let cost = appModel.estimatedCostByProvider[entry.providerId] {
                    Text("$" + String(format: "%.2f", (cost as NSDecimalNumber).doubleValue))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
                Text(TokenAnalytics.compactTokens(entry.tokens))
                    .font(Theme.Font.metricMedium)
                    .monospacedDigit()
                Text(String(format: "%.0f%%", fraction * 100))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 34, alignment: .trailing)
            }
            HStack(spacing: Theme.Space.sm) {
                ShareBar(fraction: fraction, color: color)
                if let analytics = byProvider[entry.providerId] {
                    DailyTokensAreaChart(
                        points: TrendSeries.dailyTotals(analytics, lastDays: 14),
                        color: color
                    )
                    .frame(width: 70, height: 18)
                }
            }
        }
    }

    // MARK: - Linha 4: cotas

    /// As cinco janelas mais apertadas entre todos os providers. Estava só na aba Visão
    /// geral, embora seja uma das coisas que o dono quer ver primeiro.
    private func quotaStrip() -> some View {
        var worst: [(provider: UsageProvider, window: QuotaWindow, remaining: Double)] = []
        for provider in appModel.orderedProviders {
            guard let snapshot = appModel.snapshotsByProvider[provider.id],
                  appModel.errorKindByProvider[provider.id] != .notConfigured else { continue }
            for window in snapshot.quotas {
                guard let remaining = QuotaPresentation.remainingFraction(window.shape) else { continue }
                worst.append((provider, window, remaining))
            }
        }
        let top = worst.sorted { $0.remaining < $1.remaining }.prefix(5)
        return Group {
            if !top.isEmpty {
                DashboardCard {
                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                        SectionHeader(L("Cotas mais apertadas"))
                        ForEach(Array(top.enumerated()), id: \.offset) { _, entry in
                            let danger = QuotaPresentation.color(remaining: entry.remaining)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: Theme.Space.sm) {
                                    Text("\(entry.provider.displayName) · \(WindowLabelCatalog.displayLabel(entry.window.label))")
                                        .font(.system(size: 11))
                                        .lineLimit(1)
                                    Spacer(minLength: Theme.Space.sm)
                                    if let reset = QuotaPresentation.resetText(entry.window.shape) {
                                        Text(reset).font(.system(size: 9)).foregroundStyle(.tertiary)
                                    }
                                    Text(QuotaPresentation.remainingText(entry.window.shape))
                                        .font(.system(size: 11, weight: .semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(danger)
                                }
                                QuotaCapsuleBar(remaining: entry.remaining, color: danger, height: 6)
                            }
                        }
                    }
                }
            }
        }
    }

    private var footnote: some View {
        Text(L("Codex: estatísticas da conta (API). Claude Code e OpenCode: estimativa local dos transcritos/banco desta máquina, incluindo tokens de cache."))
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
    }
}
