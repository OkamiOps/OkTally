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
            guard let snapshot = appModel.snapshotsByProvider[provider.id],
                  !snapshot.quotas.isEmpty,
                  appModel.errorKindByProvider[provider.id] != .notConfigured
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

    private var totalEstimatedCost: Decimal? {
        let costs = appModel.estimatedCostByProvider.values
        guard !costs.isEmpty else { return nil }
        return costs.reduce(0, +)
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
        HStack(alignment: .top, spacing: Theme.Space.md) {
            if let worst = worstOverall {
                bottleneckHero(worst)
            }
            summaryCard
                .frame(width: 190)
        }
        // Rodapés alinhados nesta faixa (e só nela): os dois blocos têm conteúdo de
        // volume comparável, então terminar juntos é honesto — nenhum dos dois ganha
        // altura de enchimento.
        .fixedSize(horizontal: false, vertical: true)
    }

    /// O único bloco de gradiente saturado da tela.
    ///
    /// Ordem de leitura de cima para baixo, como nas referências: rótulo minúsculo em
    /// caixa alta, quem, número gigante, barra. A primeira versão jogava o rótulo
    /// "GARGALO" no canto superior DIREITO e deixava uns 300pt de gradiente vazio entre
    /// o número e a contagem regressiva — o bloco tinha cor, mas não tinha composição.
    private func bottleneckHero(_ worst: QuotaLedgerEntry) -> some View {
        let remaining = worst.remaining ?? 0
        let danger = QuotaPresentation.color(remaining: remaining)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Theme.Space.sm) {
                SectionHeader(L("Gargalo"), onHero: true)
                Spacer(minLength: Theme.Space.sm)
                if let reset = QuotaPresentation.resetText(worst.window.shape) {
                    Text(reset)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.onHero.opacity(0.85))
                        .lineLimit(1)
                }
            }
            HStack(spacing: Theme.Space.sm) {
                // Chip em off-white com o glifo na cor do bloco, como no herói do
                // popover: chip colorido sobre gradiente colorido vira mancha.
                Text(ProviderPalette.glyph(forId: worst.providerId))
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(danger)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.onHero))
                Text(worst.providerName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.onHero)
                Text("· " + WindowLabelCatalog.displayLabel(worst.window.label))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.onHero.opacity(0.78))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            HStack(alignment: .lastTextBaseline, spacing: Theme.Space.sm) {
                Text("\(Int((remaining * 100).rounded()))%")
                    .font(Theme.Font.metricHero)
                    .monospacedDigit()
                    .foregroundStyle(Theme.onHero)
                Text(L("restante"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.onHero.opacity(0.8))
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            QuotaCapsuleBar(remaining: remaining, color: Theme.onHero, height: 8,
                            track: AnyShapeStyle(Color.black.opacity(0.22)))
        }
        .padding(Theme.Space.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .heroSurface(danger)
    }

    /// Quatro números que, isolados, viravam um card vazio cada um.
    private var summaryCard: some View {
        let tight = allWindows.filter { $0.pressure == .tight }.count
        return DashboardCard(padding: Theme.Space.md, fillsHeight: true) {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                SectionHeader(L("Resumo"))
                summaryLine(L("Provedores"), "\(entries.count)")
                summaryLine(L("Janelas"), "\(allWindows.count)")
                summaryLine(L("Sob pressão"), "\(tight)",
                            tint: tight > 0 ? Theme.Brand.neonMagenta : nil)
                if let cost = totalEstimatedCost {
                    summaryLine(L("Custo 30d"),
                                "$" + String(format: "%.2f", (cost as NSDecimalNumber).doubleValue))
                }
            }
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

// MARK: - Detalhe por provedor

/// Internal (não `private`) só para o `ReadmeAssetRenderer` conseguir fotografar a tela.
///
/// Redesenhada: antes eram oito tiles idênticos com nada dominando — a tela mais fraca do
/// app. Agora tem um herói (a janela mais crítica DESTE provedor, com o gráfico de 7 dias
/// dentro dele), a tabela densa das outras janelas e as estatísticas num objeto só.
struct ProviderDetailScreen: View {
    @ObservedObject var appModel: AppModel
    let provider: UsageProvider
    let snapshot: ProviderSnapshot

    private var identity: Color { ProviderPalette.color(for: provider.id) }

    private var windows: [QuotaLedgerEntry] {
        snapshot.quotas.map {
            QuotaLedgerEntry(providerId: provider.id, providerName: provider.displayName, window: $0)
        }
    }

    /// A janela mais apertada deste provedor. Sem percentual em nenhuma (saldo puro), o
    /// herói é a primeira janela mesmo assim — um saldo é o número dominante da tela de
    /// quem só tem saldo.
    private var hero: QuotaLedgerEntry? {
        windows.filter { $0.remaining != nil }.min { ($0.remaining ?? 1) < ($1.remaining ?? 1) }
            ?? windows.first
    }

    private var others: [QuotaLedgerEntry] {
        guard let hero else { return [] }
        return windows.filter { $0.id != hero.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            header
            if let message = appModel.errorsByProvider[provider.id] {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Theme.Brand.heatOrange)
            }
            if let hero {
                heroBlock(hero)
            }
            if appModel.analyticsLoaders[provider.id] != nil {
                if let analytics = appModel.analyticsByProvider[provider.id] {
                    AnalyticsSection(analytics: analytics)
                } else {
                    Text(L("Carregando estatísticas de uso…"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .task(id: provider.id) {
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
            if let cost = appModel.estimatedCostByProvider[provider.id] {
                VStack(alignment: .trailing, spacing: 1) {
                    SectionHeader(L("Custo 30d"))
                    Text("$" + String(format: "%.2f", (cost as NSDecimalNumber).doubleValue))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .help(L("Estimativa: tokens locais × tabela de preços do OpenRouter"))
            }
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
                    SparklineView(points: history.map(\.usedPercent), color: Theme.onHero, height: 30)
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
