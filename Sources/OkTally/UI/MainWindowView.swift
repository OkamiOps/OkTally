// Sources/OkTally/UI/MainWindowView.swift
import SwiftUI

/// Janela "Visão geral" — o popover continua sendo o vistaço rápido; aqui há espaço para
/// hierarquia bottleneck-first e histórico de 7 dias (estrutura inspirada na janela do
/// Quotio: NavigationSplitView com sidebar de páginas).
struct MainWindowView: View {
    @ObservedObject var appModel: AppModel

    private enum Pane: Hashable {
        case overview
        case analytics
        case provider(String)
    }

    @State private var pane: Pane = .overview

    private var providersWithData: [(provider: UsageProvider, snapshot: ProviderSnapshot)] {
        appModel.orderedProviders.compactMap { provider in
            let snapshot = appModel.snapshotsByProvider[provider.id]
            guard ProviderPresentationPolicy.showsSnapshot(
                snapshot,
                errorKind: appModel.errorKindByProvider[provider.id]
            ), let snapshot
            else { return nil }
            return (provider, snapshot)
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $pane) {
                Label(L("Visão geral"), systemImage: "square.grid.2x2")
                    .tag(Pane.overview)
                Label(L("Análise"), systemImage: "chart.bar.xaxis")
                    .tag(Pane.analytics)
                Section(L("Provedores")) {
                    ForEach(providersWithData, id: \.provider.id) { entry in
                        sidebarRow(entry.provider, snapshot: entry.snapshot)
                            .tag(Pane.provider(entry.provider.id))
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            ScrollView {
                Group {
                    switch pane {
                    case .overview:
                        OverviewScreen(appModel: appModel, entries: providersWithData) { providerId in
                            pane = .provider(providerId)
                        }
                    case .analytics:
                        AnalyticsDashboardView(appModel: appModel)
                    case .provider(let id):
                        if let entry = providersWithData.first(where: { $0.provider.id == id }) {
                            ProviderDetailScreen(appModel: appModel, provider: entry.provider, snapshot: entry.snapshot)
                        } else {
                            Text(L("Sem dados para este provedor."))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toolbar {
                Button {
                    Task { await appModel.refreshNow() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(L("Atualizar todos os provedores"))
            }
        }
        .navigationTitle("OkTally")
        .frame(minWidth: 700, minHeight: 460)
    }

    private func sidebarRow(_ provider: UsageProvider, snapshot: ProviderSnapshot) -> some View {
        ProviderSidebarRow(
            providerId: provider.id,
            name: provider.displayName,
            statusColor: QuotaPresentation.providerColor(snapshot)
        )
    }
}

// MARK: - Visão geral

/// Duas peças, nesta ordem: o bloco de destaque (o gargalo, com o resumo numérico ao
/// lado) e a tabela densa com TODAS as janelas agrupadas por pressão.
///
/// A grade de cards por provedor saiu inteira. Ela era a origem do defeito de rodapé
/// irregular — cards de conteúdo desigual numa `LazyVGrid`, com buracos de até 200pt ao
/// lado de quem só tem saldo — e nenhuma variação de alinhamento resolvia isso sem
/// esticar card vazio, que já foi reprovado quatro vezes. Trocando a unidade da tela
/// (provedor → janela de cota), o problema some por construção e a tela ganha densidade:
/// o que antes eram ~1900pt de rolagem viram ~600pt com a mesma informação.
struct OverviewScreen: View {
    @ObservedObject var appModel: AppModel
    let entries: [(provider: UsageProvider, snapshot: ProviderSnapshot)]
    let onSelect: (String) -> Void

    /// Todas as janelas de todos os provedores, achatadas — a matéria-prima da tabela.
    private var allWindows: [QuotaLedgerEntry] {
        entries.flatMap { entry in
            entry.snapshot.quotas.map {
                QuotaLedgerEntry(providerId: entry.provider.id,
                                 providerName: entry.provider.displayName,
                                 window: $0)
            }
        }
    }

    /// Pior janela entre todos os provedores, para o bloco de destaque.
    private var worstOverall: QuotaLedgerEntry? {
        allWindows
            .filter { $0.remaining != nil }
            .min { ($0.remaining ?? 1) < ($1.remaining ?? 1) }
    }

    /// A tabela não repete a janela que já está gigante no destaque — é a mesma regra do
    /// popover, onde o provedor do herói não volta como linha. Repetir o número seria o
    /// mesmo defeito do card do OpenRouter, que imprimia "19.82 USD" duas vezes.
    private var ledgerEntries: [QuotaLedgerEntry] {
        guard let worstOverall else { return allWindows }
        return allWindows.filter { $0.id != worstOverall.id }
    }

    private var totalKnownCost: AnalyticsCostSummary? {
        AnalyticsCostSummary.aggregate(entries.compactMap { appModel.costSummary(for: $0.provider.id) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            if entries.isEmpty {
                Text(L("Nenhum provedor com dados ainda — conecte contas nas Preferências."))
                    .foregroundStyle(.secondary)
            } else {
                heroRow
                QuotaLedgerCard(title: L("Todas as cotas"),
                                entries: ledgerEntries,
                                onSelect: onSelect)
            }
        }
    }

    /// O destaque e o resumo dividem a primeira faixa. O resumo à direita existe porque o
    /// destaque sozinho, na largura inteira da janela, deixava um vazio de uns 300pt no
    /// meio dele — e a versão anterior tapava esse vazio com um tile "Provedores 8" que
    /// era 90% ar. Aqui a coluna estreita carrega quatro números de verdade.
    private var heroRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Theme.Space.md) {
                if let worst = worstOverall {
                    bottleneckHero(worst)
                }
                summaryCard
                    .frame(width: 190)
            }
            // Rodapés alinhados nesta faixa larga: os dois blocos têm conteúdo de volume
            // comparável, então terminar juntos é honesto — nenhum ganha altura de enchimento.
            .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: Theme.Space.md) {
                if let worst = worstOverall {
                    bottleneckHero(worst)
                }
                summaryCard
            }
        }
    }

    /// O único bloco de gradiente saturado da tela.
    ///
    /// Ordem de leitura de cima para baixo, como nas referências: rótulo minúsculo em
    /// caixa alta, quem, número gigante, barra. A primeira versão jogava o rótulo
    /// "GARGALO" no canto superior DIREITO e deixava uns 300pt de gradiente vazio entre
    /// o número e a contagem regressiva — o bloco tinha cor, mas não tinha composição.
    private func bottleneckHero(_ worst: QuotaLedgerEntry) -> some View {
        let remaining = worst.remaining ?? 0
        // `heroTint` porque o glifo do chip é escrito NESTA cor sobre off-white — ver
        // a nota gêmea no herói do popover.
        let danger = Theme.heroTint(QuotaPresentation.color(remaining: remaining))

        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: Theme.Space.xl) {
                bottleneckIdentity(worst, danger: danger)
                bottleneckUsage(worst)
            }
            // Em janelas estreitas o HStack esmagava o centro até o rótulo quebrar uma
            // letra por linha. O fallback vertical mantém o mesmo conteúdo sem inventar
            // largura mínima para a janela inteira.
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                bottleneckIdentity(worst, danger: danger)
                bottleneckUsage(worst)
            }
        }
        .padding(Theme.Space.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .heroSurface(danger)
    }

    /// Identidade e número do gargalo — a coluna esquerda no layout largo, o topo no
    /// compacto. Ela tem largura contida de propósito: antes o número ficava no canto e
    /// todo o centro do gradiente era vazio.
    private func bottleneckIdentity(_ worst: QuotaLedgerEntry, danger: Color) -> some View {
        let remaining = worst.remaining ?? 0
        return VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(spacing: Theme.Space.sm) {
                Text(ProviderPalette.glyph(forId: worst.providerId))
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(danger)
                    .frame(width: 25, height: 25)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.onHero))
                VStack(alignment: .leading, spacing: 1) {
                    Text(worst.providerName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.onHero)
                        .lineLimit(1)
                    Text(WindowLabelCatalog.displayLabel(worst.window.label))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.onHero.opacity(0.72))
                        .lineLimit(1)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(Int((remaining * 100).rounded()))")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.onHero)
                Text("%")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.onHero.opacity(0.82))
            }
            Text(L("restante"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.onHero.opacity(0.78))
        }
        .frame(minWidth: 150, maxWidth: 170, alignment: .leading)
    }

    /// Estado, barra e comportamento recente. É esta parte — não um Spacer — que absorve
    /// a largura extra da janela.
    private func bottleneckUsage(_ worst: QuotaLedgerEntry) -> some View {
        let remaining = worst.remaining ?? 0
        let history = appModel.history(providerId: worst.providerId, hours: 7 * 24)
        let pressureText: String
        if remaining <= 0.10 {
            pressureText = L("limite praticamente alcançado")
        } else if remaining <= 0.30 {
            pressureText = L("janela sob pressão")
        } else {
            pressureText = L("menor folga da frota")
        }

        let historyRange = (history.map(\.usedPercent).max() ?? 0) - (history.map(\.usedPercent).min() ?? 0)
        let hasMeaningfulHistory = history.count >= 2 && historyRange > 0.5

        return VStack(alignment: .leading, spacing: Theme.Space.md) {
            HStack(spacing: Theme.Space.sm) {
                SectionHeader(L("Gargalo"), onHero: true)
                Text(pressureText)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.onHero.opacity(0.86))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(0.20)))
                Spacer(minLength: Theme.Space.sm)
                if let reset = QuotaPresentation.resetText(worst.window.shape) {
                    Text(reset)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.onHero.opacity(0.9))
                        .lineLimit(1)
                }
            }
            QuotaCapsuleBar(remaining: remaining, color: Theme.onHero, height: 10,
                            track: AnyShapeStyle(Color.black.opacity(0.24)))
            if hasMeaningfulHistory {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("Uso nos últimos 7 dias"))
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(Theme.labelTracking)
                        .foregroundStyle(Theme.onHero.opacity(0.68))
                    SparklineView(
                        points: history.map(\.usedPercent),
                        color: Theme.onHero,
                        height: 34,
                        dates: history.map(\.date),
                        hover: true
                    )
                }
            } else {
                Text(L(history.count >= 2 ? "Quota praticamente estável nos últimos 7 dias." : "O histórico local desta janela aparece aqui depois das próximas atualizações."))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.onHero.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Resumo da frota em um objeto só: o anel dá a leitura instantânea e os números
    /// exatos ficam ao lado quando há largura, ou em lista quando o card está na coluna
    /// estreita. Assim o fallback vertical da faixa principal não vira um cartão alto e
    /// vazio atravessando a tela inteira.
    private var summaryCard: some View {
        let tight = allWindows.filter { $0.pressure == .tight }.count
        let remainingValues = allWindows.compactMap(\.remaining)
        let averageRemaining = remainingValues.isEmpty ? 0 : remainingValues.reduce(0, +) / Double(remainingValues.count)
        let costText = totalKnownCost.map(TokenAnalytics.costLabel)

        return DashboardCard(padding: Theme.Space.md, fillsHeight: true) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Space.lg) {
                    summaryHead(averageRemaining: averageRemaining)
                    Rectangle().fill(Theme.border()).frame(width: 1, height: 44)
                    summaryMetric(L("Provedores"), "\(entries.count)")
                    summaryMetric(L("Janelas"), "\(allWindows.count)")
                    summaryMetric(L("Sob pressão"), "\(tight)", tint: tight > 0 ? QuotaPressure.tight.tint : nil)
                    if let costText { summaryMetric(L("Custo conhecido"), costText) }
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    summaryHead(averageRemaining: averageRemaining)
                    Rectangle().fill(Theme.border()).frame(height: 1)
                    summaryLine(L("Provedores"), "\(entries.count)")
                    summaryLine(L("Janelas"), "\(allWindows.count)")
                    summaryLine(L("Sob pressão"), "\(tight)",
                                tint: tight > 0 ? QuotaPressure.tight.tint : nil)
                    if let costText { summaryLine(L("Custo conhecido"), costText) }
                }
            }
        }
    }

    private func summaryHead(averageRemaining: Double) -> some View {
        HStack(spacing: Theme.Space.sm) {
            ProgressRing(
                fraction: averageRemaining,
                color: QuotaPresentation.color(remaining: averageRemaining),
                size: 46,
                label: "\(Int((averageRemaining * 100).rounded()))%"
            )
            VStack(alignment: .leading, spacing: 2) {
                SectionHeader(L("Resumo"))
                Text(L("folga média"))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func summaryMetric(_ label: String, _ value: String, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            SectionHeader(label)
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint ?? .primary)
                .lineLimit(1)
        }
    }

    private func summaryLine(_ label: String, _ value: String, tint: Color? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: Theme.Space.sm)
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint ?? .primary)
        }
    }
}

/// Estado explícito de ausência de analytics. É propositalmente um card neutro e curto:
/// o usuário deve entender que a ausência é uma limitação da fonte, não um loading que
/// ficou preso nem um zero inventado.
private struct AnalyticsUnavailableCard: View {
    let message: String

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                SectionHeader(L("Estatísticas de uso"))
                Label(L("Dados de token indisponíveis"), systemImage: "chart.xyaxis.line")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Detalhe por provedor
// MARK: - Detalhe por provedor

/// Internal (não `private`) só para o `ReadmeAssetRenderer` conseguir fotografar a tela.
///
/// Redesenhada: antes eram oito tiles idênticos com nada dominando — a tela mais fraca do
/// app. Agora tem um herói (a janela representativa DESTE provedor, com o gráfico de 7 dias
/// dentro dele), a tabela densa das outras janelas e as estatísticas num objeto só.
struct ProviderDetailScreen: View {
    @ObservedObject var appModel: AppModel
    let provider: UsageProvider
    let snapshot: ProviderSnapshot

    private var identity: Color { ProviderPalette.color(for: provider.id) }

    @State private var quotaUsageStatistics: QuotaUsageStatistics?
    @State private var quotaUsageChecked = false

    private var windows: [QuotaLedgerEntry] {
        PopoverLayout.orderedWindows(snapshot.quotas, providerId: provider.id,
                                     preferredLabel: appModel.primaryWindowLabel(forProviderId: provider.id)).map {
            QuotaLedgerEntry(providerId: provider.id, providerName: provider.displayName, window: $0)
        }
    }

    /// A janela representativa deste provedor. A ordem compartilhada com o popover
    /// mantém o Weekly geral do Codex à frente dos limites específicos do Spark.
    private var hero: QuotaLedgerEntry? {
        windows.first
    }

    private var others: [QuotaLedgerEntry] {
        guard let hero else { return [] }
        return windows.filter { $0.id != hero.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            header
            if let note = snapshot.connectionNote {
                Text(note).font(.callout).foregroundStyle(.secondary)
            }
            if let message = appModel.errorsByProvider[provider.id] {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Theme.Brand.heatOrange)
            }
            if let hero {
                heroBlock(hero)
            }
            let forecasts = appModel.forecasts(providerId: provider.id)
            if !forecasts.isEmpty {
                ForecastDetailView(
                    providerId: provider.id,
                    forecasts: forecasts
                )
            }
            if let analytics = appModel.analyticsByProvider[provider.id] {
                AnalyticsSection(analytics: analytics)
            } else if let quotaUsageStatistics {
                QuotaUsageSection(statistics: quotaUsageStatistics, tint: identity)
            } else if appModel.analyticsLoaders[provider.id] != nil {
                if appModel.analyticsUnavailableProviderIds.contains(provider.id), quotaUsageChecked {
                    AnalyticsUnavailableCard(
                        message: L("A fonte de analytics existe, mas não retornou contadores utilizáveis nesta máquina no momento. O histórico local de quota ainda não tem consumo suficiente para um gráfico.")
                    )
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: Theme.Space.sm) {
                            ProgressView().controlSize(.small)
                            Text(L("Carregando estatísticas de uso…"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(L("O primeiro scan local pode levar alguns segundos; depois o cache incremental é usado."))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            } else if quotaUsageChecked {
                AnalyticsUnavailableCard(
                    message: L("Este provedor não expõe contadores de token utilizáveis e ainda não há histórico local suficiente para derivar consumo. A cota acima continua medida; o OkTally não inventa tokens a partir dela.")
                )
            }
        }
        .task(id: provider.id) {
            if let hero {
                quotaUsageStatistics = appModel.quotaUsageStatistics(providerId: provider.id, windowLabel: hero.window.label, days: 56)
            }
            quotaUsageChecked = true
            await appModel.loadAnalyticsIfStale(providerId: provider.id)
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Space.md) {
            IconChip(glyph: ProviderPalette.glyph(for: provider), color: identity, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Space.sm) {
                    Text(provider.displayName).font(.system(size: 17, weight: .bold))
                    if let plan = snapshot.planLabel {
                        PlanBadge(label: plan)
                    }
                }
                Text(LF("Atualizado %@", Self.relative(snapshot.fetchedAt)))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            // O custo estimado era um `Label` solto no meio da coluna; como par
            // rótulo/número no cabeçalho ele vira informação de contexto e para de
            // parecer um rodapé perdido.
            if let cost = appModel.costSummary(for: provider.id) {
                VStack(alignment: .trailing, spacing: 1) {
                    SectionHeader(costHeaderLabel(cost))
                    Text(TokenAnalytics.costLabel(cost))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .help(costHelp(cost))
            }
        }
    }

    private func costHeaderLabel(_ cost: AnalyticsCostSummary) -> String {
        switch cost.period {
        case .last30Days: return L("Custo 30d")
        case .billingCycle: return L("Custo do ciclo")
        case .mixed: return L("Custo conhecido")
        }
    }

    private func costHelp(_ cost: AnalyticsCostSummary) -> String {
        switch cost.kind {
        case .metered: return L("Custo medido/reportado pelo provedor ou pelo banco local oficial")
        case .apiEquivalent: return L("Estimativa: tokens locais × tabela de preços do OpenRouter")
        case .mixed: return L("Combina custos medidos e equivalência de API; não é uma fatura")
        }
    }

    /// O bloco dominante da tela.
    ///
    /// A cor é a IDENTIDADE do provedor, não a escala de perigo — é a página dele, e com
    /// a escala de perigo toda página folgada saía ciano, inclusive a do Claude, que é
    /// terracota em todo o resto do app. A exceção é a cota apertada: aí o bloco vira
    /// magenta e a página inteira grita, que é justamente quando a cor semântica vale
    /// mais que a identidade.
    private func heroBlock(_ entry: QuotaLedgerEntry) -> some View {
        let remaining = entry.remaining
        let tight = (remaining ?? 1) <= 0.30
        let tint = tight ? QuotaPresentation.color(remaining: remaining) : identity
        let history = appModel.history(providerId: provider.id, hours: 7 * 24)
        return VStack(alignment: .leading, spacing: 6) {
            SectionHeader(WindowLabelCatalog.displayLabel(entry.window.label), onHero: true)
            // Número à esquerda, contagem regressiva à direita, na MESMA linha: com o
            // "reseta em" lá em cima o corpo do bloco ficava com o lado direito vazio.
            HStack(alignment: .lastTextBaseline, spacing: Theme.Space.sm) {
                Text(QuotaPresentation.remainingValueText(entry.window.shape))
                    .font(Theme.Font.metricHero)
                    .monospacedDigit()
                    .foregroundStyle(Theme.onHero)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if remaining != nil {
                    Text(L("restante"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.onHero.opacity(0.8))
                }
                Spacer(minLength: Theme.Space.sm)
                if let reset = QuotaPresentation.resetText(entry.window.shape) {
                    Text(reset)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.onHero.opacity(0.85))
                        .lineLimit(1)
                }
            }
            if let remaining {
                QuotaCapsuleBar(remaining: remaining, color: Theme.onHero, height: 8,
                                track: AnyShapeStyle(Color.black.opacity(0.22)))
            }
            // As outras janelas do provedor moram DENTRO do herói, como no popover (que
            // foi aprovado com esse desenho). Num card ao lado elas viravam uma linha só
            // num retângulo esticado até a altura do herói — o mesmo "enchimento" que já
            // foi reprovado. Aqui elas ocupam a largura inteira do bloco e ainda dão ao
            // herói o conteúdo que faltava na metade direita.
            if !others.isEmpty {
                VStack(spacing: 0) {
                    ForEach(others) { other in
                        QuotaLedgerRow(entry: other, onHero: true)
                    }
                }
                .padding(.top, Theme.Space.xs)
            }
            // Faixa de 7 dias como RODAPÉ do herói, não como card próprio. Sozinha num
            // card ela era um traço de 20pt no meio de um retângulo de 60 — o "filete
            // perdido" que o relatório anterior já apontava. Aqui ela é a base do bloco,
            // com o rótulo na mesma linha, e a escala fixa 0–100 passa a ser lida como
            // "uso baixo e estável" em vez de linha colada na borda de lugar nenhum.
            if history.count >= 2 {
                HStack(spacing: Theme.Space.sm) {
                    SectionHeader(L("Uso — 7 dias"), onHero: true)
                    SparklineView(
                        points: history.map(\.usedPercent),
                        color: Theme.onHero,
                        height: 30,
                        dates: history.map(\.date),
                        hover: true
                    )
                }
                .padding(.top, Theme.Space.xs)
            }
        }
        .padding(Theme.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .heroSurface(tint)
        .help(entry.window.shape.isEstimated
              ? L("Estimativa local, não confirmada pelo provedor") : "")
    }

    private static func relative(_ date: Date) -> String {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .short
        return fmt.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Barra de cota

/// Barra em cápsula do RESTANTE (mesma convenção do anel): cheia = folga, vazia = limite.
struct QuotaCapsuleBar: View {
    let remaining: Double
    let color: Color
    var height: CGFloat = 8
    /// Trilho alternativo para quando a barra vive DENTRO do bloco-herói: sobre um
    /// gradiente saturado o trilho padrão (branco a 9% sobre quase preto) some, e a barra
    /// perde a referência de "quanto falta".
    var track: AnyShapeStyle?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track ?? AnyShapeStyle(Theme.track()))
                Capsule()
                    .fill(color.gradient)
                    .frame(width: max(height, geo.size.width * Theme.clampFraction(remaining)))
                    .animation(.easeInOut(duration: 0.3), value: remaining)
            }
        }
        .frame(height: height)
    }
}
