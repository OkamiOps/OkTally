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
                        AnalyticsScreen(appModel: appModel)
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
        let identity = ProviderPalette.color(for: provider.id)
        return HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 5).fill(identity.opacity(0.16)).frame(width: 20, height: 20)
                Text(ProviderPalette.glyph(for: provider))
                    .font(.system(size: 10, weight: .heavy)).foregroundStyle(identity)
            }
            Text(provider.displayName).font(.system(size: 12))
            Spacer()
            Circle()
                .fill(QuotaPresentation.providerColor(snapshot))
                .frame(width: 7, height: 7)
        }
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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], alignment: .leading, spacing: 14) {
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
        HStack(spacing: 14) {
            KPICard(title: L("Provedores"), value: "\(entries.count)", caption: L("com dados"), color: .accentColor)
            if let worst = worstOverall {
                KPICard(
                    title: L("Gargalo"),
                    value: "\(Int((worst.remaining * 100).rounded()))%",
                    caption: "\(worst.provider.displayName) · \(WindowLabelCatalog.displayLabel(worst.window.label))",
                    color: QuotaPresentation.color(remaining: worst.remaining)
                )
            }
            if let cost = totalEstimatedCost {
                KPICard(
                    title: L("Custo estimado"),
                    value: "$" + String(format: "%.2f", (cost as NSDecimalNumber).doubleValue),
                    caption: L("últimos 30 dias"),
                    color: .secondary
                )
            }
            Spacer(minLength: 0)
        }
    }
}

private struct KPICard: View {
    let title: String
    let value: String
    let caption: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
            Text(caption)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(minWidth: 130, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
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

    private var others: [QuotaWindow] {
        snapshot.quotas.filter { $0.label != worst?.window.label }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(ProviderPalette.glyph(for: provider))
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(identity)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(identity.opacity(0.16)))
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
                SparklineView(
                    points: history.map(\.usedPercent),
                    color: worst.map { QuotaPresentation.color(remaining: $0.remaining) } ?? identity
                )
                .help(L("Uso nos últimos 7 dias"))
            }
            if let estimatedCost {
                Label(LF("Custo est.: $%@ (30d)", String(format: "%.2f", (estimatedCost as NSDecimalNumber).doubleValue)),
                      systemImage: "dollarsign.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
    }

    private func heroBlock(_ window: QuotaWindow, remaining: Double) -> some View {
        let danger = QuotaPresentation.color(remaining: remaining)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(WindowLabelCatalog.displayLabel(window.label))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(QuotaPresentation.remainingText(window.shape))
                    .font(.system(size: 15, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(danger)
            }
            QuotaCapsuleBar(remaining: remaining, color: danger, height: 8)
            if let reset = QuotaPresentation.resetText(window.shape) {
                Label(reset, systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(danger.opacity(0.08)))
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
                .foregroundStyle(remaining != nil ? QuotaPresentation.color(remaining: remaining) : .primary)
        }
    }
}

// MARK: - Análise agregada

/// Aba "Análise": soma o uso em tokens de todas as fontes disponíveis (Codex via API,
/// Claude Code e OpenCode via dados locais) num painel único, com o recorte por
/// provedor logo abaixo.
private struct AnalyticsScreen: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let aggregated = appModel.aggregatedAnalytics {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("TODOS OS PROVEDORES"))
                        .font(.system(size: 9, weight: .semibold)).tracking(0.5)
                        .foregroundStyle(.secondary)
                    AnalyticsSection(analytics: aggregated)
                }
                breakdown
            } else if appModel.analyticsProviderIds.isEmpty {
                Text(L("Nenhuma fonte de análise disponível — conecte Codex, Claude Code ou OpenCode."))
                    .foregroundStyle(.secondary)
            } else {
                Text(L("Carregando estatísticas de uso…"))
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            await appModel.loadAllAnalyticsIfStale()
        }
    }

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("POR PROVEDOR"))
                .font(.system(size: 9, weight: .semibold)).tracking(0.5)
                .foregroundStyle(.secondary)
            ForEach(appModel.analyticsProviderIds, id: \.self) { providerId in
                let identity = ProviderPalette.color(for: providerId)
                HStack(spacing: 8) {
                    Text(ProviderPalette.glyph(forId: providerId))
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(identity)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5).fill(identity.opacity(0.16)))
                    Text(providerName(providerId))
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    if let analytics = appModel.analyticsByProvider[providerId] {
                        if let lifetime = analytics.effectiveLifetimeTokens {
                            Text(TokenAnalytics.compactTokens(lifetime))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .monospacedDigit()
                        }
                        Text(LF("· %@ em 30d", TokenAnalytics.compactTokens(analytics.tokensLast30Days)))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    } else {
                        Text(L("Sem dados"))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.045)))
            }
            Text(L("Codex: estatísticas da conta (API). Claude Code e OpenCode: estimativa local dos transcritos/banco desta máquina, incluindo tokens de cache."))
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }

    private func providerName(_ id: String) -> String {
        appModel.orderedProviders.first { $0.id == id }?.displayName ?? id
    }
}

// MARK: - Detalhe por provedor

private struct ProviderDetailScreen: View {
    @ObservedObject var appModel: AppModel
    let provider: UsageProvider
    let snapshot: ProviderSnapshot

    private var identity: Color { ProviderPalette.color(for: provider.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(identity.opacity(0.16)).frame(width: 36, height: 36)
                    Text(ProviderPalette.glyph(for: provider))
                        .font(.system(size: 16, weight: .heavy)).foregroundStyle(identity)
                }
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
                    .foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(snapshot.quotas, id: \.label) { window in
                    windowRow(window)
                }
            }
            let history = appModel.history(providerId: provider.id, hours: 7 * 24)
            if history.count >= 2 {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("USO — 7 DIAS"))
                        .font(.system(size: 9, weight: .semibold)).tracking(0.5)
                        .foregroundStyle(.secondary)
                    SparklineView(points: history.map(\.usedPercent), color: identity)
                        .frame(height: 48)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.045)))
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
        return VStack(alignment: .leading, spacing: 6) {
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
                    .foregroundStyle(remaining != nil ? danger : .primary)
            }
            if let remaining {
                QuotaCapsuleBar(remaining: remaining, color: danger, height: 8)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.045)))
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

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(color.gradient)
                    .frame(width: max(height, geo.size.width * max(0, min(1, remaining))))
                    .animation(.easeInOut(duration: 0.3), value: remaining)
            }
        }
        .frame(height: height)
    }
}
