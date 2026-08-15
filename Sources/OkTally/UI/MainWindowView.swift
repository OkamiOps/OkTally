// Sources/OkTally/UI/MainWindowView.swift
import SwiftUI

/// Janela "Visão geral" — o popover continua sendo o vistaço rápido; aqui há espaço para
/// hierarquia bottleneck-first por provider e histórico de 7 dias (estrutura inspirada na
/// janela do Quotio: NavigationSplitView com sidebar de páginas).
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

struct OverviewScreen: View {
    @ObservedObject var appModel: AppModel
    let entries: [(provider: UsageProvider, snapshot: ProviderSnapshot)]
    let onSelect: (String) -> Void

    /// Pior janela entre todos os provedores, para o KPI de "gargalo".
    private var worstOverall: (provider: UsageProvider, window: QuotaWindow, remaining: Double)? {
        var best: (UsageProvider, QuotaWindow, Double)?
        for (provider, snapshot) in entries {
            for window in snapshot.quotas {
                guard let remaining = QuotaPresentation.remainingFraction(window.shape) else { continue }
                if best == nil || remaining < best!.2 { best = (provider, window, remaining) }
            }
        }
        return best
    }

    private var totalEstimatedCost: Decimal? {
        let costs = appModel.estimatedCostByProvider.values
        guard !costs.isEmpty else { return nil }
        return costs.reduce(0, +)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if entries.isEmpty {
                Text(L("Nenhum provedor com dados ainda — conecte contas nas Preferências."))
                    .foregroundStyle(.secondary)
            } else {
                kpiRow
                // `LazyVGrid` centraliza os itens de uma linha verticalmente — o
                // `alignment:` do próprio grid só governa o eixo horizontal. Quem ancora
                // no topo é o `alignment:` do `GridItem`, que vale para a célula. Os cards
                // ficam com a altura do próprio conteúdo: esticar todos até o mais alto
                // encheria de vazio o card de quem só tem saldo (OpenRouter), o mesmo
                // "enchimento" que o dono reprovou no herói da aba Análise.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14, alignment: .top)], alignment: .leading, spacing: 14) {
                    ForEach(entries, id: \.provider.id) { entry in
                        ProviderOverviewCard(
                            provider: entry.provider,
                            snapshot: entry.snapshot,
                            history: appModel.history(providerId: entry.provider.id, hours: 7 * 24),
                            estimatedCost: appModel.estimatedCostByProvider[entry.provider.id]
                        )
                        .onTapGesture { onSelect(entry.provider.id) }
                    }
                }
            }
        }
    }

    private var kpiRow: some View {
        HStack(spacing: Theme.Space.md) {
            StatTile(title: L("Provedores"), value: "\(entries.count)", caption: L("com dados"),
                     fillsHeight: true)
                .frame(width: 150)
            if let worst = worstOverall {
                bottleneckTile(worst)
            }
            if let cost = totalEstimatedCost {
                StatTile(
                    title: L("Custo estimado"),
                    value: "$" + String(format: "%.2f", (cost as NSDecimalNumber).doubleValue),
                    caption: L("últimos 30 dias"),
                    fillsHeight: true
                )
                .frame(width: 170)
            }
        }
        // Rodapés alinhados: os tiles laterais esticam até a altura do herói em vez de
        // flutuarem no topo de uma linha alta, e a linha inteira mede o conteúdo mais
        // alto — sem nenhuma altura fixa.
        .fixedSize(horizontal: false, vertical: true)
    }

    /// O único bloco de gradiente saturado da tela. Antes era um `StatTile` limitado a
    /// 300pt: o número ficava num canto, sobrava metade da largura da janela vazia à
    /// direita dele e a linha de KPIs terminava no meio do nada. Agora ele ocupa a folga
    /// e a preenche com conteúdo de verdade — quem, qual janela, quanto falta e quando
    /// volta — que é o que justifica ser o maior bloco da tela.
    private func bottleneckTile(_ worst: (provider: UsageProvider, window: QuotaWindow, remaining: Double)) -> some View {
        let danger = QuotaPresentation.color(remaining: worst.remaining)
        return VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(spacing: Theme.Space.sm) {
                SectionHeader(L("Gargalo"), onHero: true)
                Spacer(minLength: 0)
                if let reset = QuotaPresentation.resetText(worst.window.shape) {
                    Text(reset)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.onHero.opacity(0.8))
                }
            }
            HStack(alignment: .lastTextBaseline, spacing: Theme.Space.sm) {
                Text("\(Int((worst.remaining * 100).rounded()))%")
                    .font(Theme.Font.metricHero)
                    .monospacedDigit()
                    .foregroundStyle(Theme.onHero)
                Text(L("restante"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.onHero.opacity(0.8))
                Spacer(minLength: Theme.Space.sm)
                Text("\(worst.provider.displayName) · \(WindowLabelCatalog.displayLabel(worst.window.label))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.onHero.opacity(0.85))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            QuotaCapsuleBar(remaining: worst.remaining, color: Theme.onHero, height: 8,
                            track: AnyShapeStyle(Color.black.opacity(0.22)))
        }
        .padding(Theme.Space.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .heroSurface(danger)
    }
}

/// Card bottleneck-first (padrão do Quotio): a pior janela vira bloco-herói com fundo
/// tingido; as demais colapsam em linhas compactas.
private struct ProviderOverviewCard: View {
    let provider: UsageProvider
    let snapshot: ProviderSnapshot
    let history: [UsageHistoryPoint]
    let estimatedCost: Decimal?

    private var identity: Color { ProviderPalette.color(for: provider.id) }

    private var worst: (window: QuotaWindow, remaining: Double)? {
        snapshot.quotas
            .compactMap { w in QuotaPresentation.remainingFraction(w.shape).map { (w, $0) } }
            .min { $0.1 < $1.1 }
    }

    /// Janelas que NÃO estão no bloco de destaque do card. Quando não há percentual
    /// (OpenRouter só tem saldo), `worst` é nil e o filtro por rótulo não removia nada —
    /// o card imprimia "19.82 USD" grande e repetia "Balance 19.82 USD" na linha de baixo.
    /// Sem `worst`, quem ocupa o destaque é a primeira janela, então é ela que sai daqui.
    private var others: [QuotaWindow] {
        guard let worst else { return Array(snapshot.quotas.dropFirst()) }
        return snapshot.quotas.filter { $0.label != worst.window.label }
    }

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    IconChip(glyph: ProviderPalette.glyph(for: provider), color: identity)
                    Text(provider.displayName).font(.system(size: 13, weight: .semibold))
                    if let plan = snapshot.planLabel {
                        PlanBadge(label: plan)
                    }
                    Spacer(minLength: 0)
                }
                if let worst {
                    heroBlock(worst.window, remaining: worst.remaining)
                } else if let balance = snapshot.quotas.first {
                    Text(QuotaPresentation.remainingText(balance.shape))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                ForEach(others, id: \.label) { window in
                    compactRow(window)
                }
                if history.count >= 2 {
                    SparklineView(points: history.map(\.usedPercent), color: identity)
                    .help(L("Uso nos últimos 7 dias"))
                }
                if let estimatedCost {
                    Label(LF("Custo est.: $%@ (30d)", String(format: "%.2f", (estimatedCost as NSDecimalNumber).doubleValue)),
                          systemImage: "dollarsign.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func heroBlock(_ window: QuotaWindow, remaining: Double) -> some View {
        let danger = QuotaPresentation.color(remaining: remaining)
        // Rótulo minúsculo em caixa alta + número grande, na mesma proporção do herói do
        // popover. A versão anterior era uma linha só, com o rótulo e o valor no mesmo
        // corpo de 11–15pt: sem contraste de tamanho, o card não tinha o que ler primeiro
        // e virava uma tabela.
        return VStack(alignment: .leading, spacing: 6) {
            SectionHeader(WindowLabelCatalog.displayLabel(window.label))
            HStack(alignment: .lastTextBaseline, spacing: 5) {
                Text(QuotaPresentation.remainingValueText(window.shape))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(QuotaPresentation.valueColor(remaining: remaining))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(L("restante"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if let reset = QuotaPresentation.resetCompactText(window.shape) {
                    Text(reset)
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
            // Barra na cor de IDENTIDADE (o número já carrega o perigo): é o que dá à
            // grade a paleta categórica das referências em vez de oito barras iguais.
            QuotaCapsuleBar(remaining: remaining, color: identity, height: 8)
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
            .fill(Theme.surfaceRaised()))
    }

    private func compactRow(_ window: QuotaWindow) -> some View {
        let remaining = QuotaPresentation.remainingFraction(window.shape)
        return HStack(spacing: 6) {
            Text(WindowLabelCatalog.displayLabel(window.label))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let reset = QuotaPresentation.resetText(window.shape) {
                Text(reset).font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            Text(QuotaPresentation.remainingText(window.shape))
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(QuotaPresentation.valueColor(remaining: remaining))
        }
    }
}

// MARK: - Detalhe por provedor

/// Internal (não `private`) só para o `ReadmeAssetRenderer` conseguir fotografar a tela —
/// era a única das quatro sem PNG, e justamente a que carregava a inconsistência de
/// cromo com a aba Análise.
struct ProviderDetailScreen: View {
    @ObservedObject var appModel: AppModel
    let provider: UsageProvider
    let snapshot: ProviderSnapshot

    private var identity: Color { ProviderPalette.color(for: provider.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                IconChip(glyph: ProviderPalette.glyph(for: provider), color: identity, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(provider.displayName).font(.system(size: 16, weight: .bold))
                        if let plan = snapshot.planLabel {
                            PlanBadge(label: plan)
                        }
                    }
                    Text(LF("Atualizado %@", Self.relative(snapshot.fetchedAt)))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if let message = appModel.errorsByProvider[provider.id] {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Theme.Brand.heatOrange)
            }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(snapshot.quotas, id: \.label) { window in
                    windowRow(window)
                }
            }
            let history = appModel.history(providerId: provider.id, hours: 7 * 24)
            if history.count >= 2 {
                DashboardCard {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionHeader(L("Uso — 7 dias"))
                        // Sem `.frame(height:)`: a `SparklineView` já fixa 20pt por
                        // dentro, e os 48 viravam 28pt de vazio — além de divergir do
                        // card da Visão geral, que não passa frame nenhum.
                        SparklineView(points: history.map(\.usedPercent), color: identity)
                    }
                }
            }
            if let cost = appModel.estimatedCostByProvider[provider.id] {
                Label(LF("Custo estimado: $%@ nos últimos 30 dias", String(format: "%.2f", (cost as NSDecimalNumber).doubleValue)),
                      systemImage: "dollarsign.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    private func windowRow(_ window: QuotaWindow) -> some View {
        let remaining = QuotaPresentation.remainingFraction(window.shape)
        let danger = QuotaPresentation.color(remaining: remaining)
        return DashboardCard(padding: Theme.Space.md) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(WindowLabelCatalog.displayLabel(window.label))
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    if let reset = QuotaPresentation.resetText(window.shape) {
                        Text(reset).font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                    Text(QuotaPresentation.remainingText(window.shape))
                        .font(.system(size: 12, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(QuotaPresentation.valueColor(remaining: remaining))
                }
                if let remaining {
                    QuotaCapsuleBar(remaining: remaining, color: identity, height: 8)
                }
            }
        }
        .help(window.shape.isEstimated ? L("Estimativa local, não confirmada pelo provedor") : "")
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
