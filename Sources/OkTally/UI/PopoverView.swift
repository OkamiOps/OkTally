// Sources/OkTally/UI/PopoverView.swift
import SwiftUI

struct PopoverView: View {
    @ObservedObject var appModel: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                PopoverContentView(appModel: appModel)
            }
            // Fixed height, not maxHeight: inside a MenuBarExtra window the ScrollView
            // gets no height proposal and collapses to zero with only a max constraint.
            .frame(height: 480)
            Divider()
            footer
        }
        .frame(width: 360)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("OkTally").font(.system(size: 14, weight: .bold))
            if let update = appModel.availableUpdate {
                Button {
                    NSWorkspace.shared.open(update.url)
                } label: {
                    Label(LF("%@ disponível", update.version), systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange.opacity(0.15)))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .help(L("Abrir a página da nova versão no GitHub"))
            }
            Spacer()
            Text(pinnedHint).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        // Cromo, não conteúdo: o vidro fica atrás do título e do chip de update, nunca
        // atrás de número ou gráfico. `Rectangle` porque a faixa encosta nas bordas.
        .glassChrome(in: Rectangle())
    }

    private var pinnedHint: String {
        let count = appModel.menuBarPins.count
        switch count {
        case 0: return L("Barra: automático")
        case 1: return L("Barra: 1 fixado")
        default: return LF("Barra: %d fixados", count)
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button(L("Atualizar")) { Task { await appModel.refreshNow() } }
            Button(L("Visão geral")) {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            Spacer()
            SettingsLink { Text(L("Preferências")) }
                .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
            Button(L("Encerrar")) { NSApplication.shared.terminate(nil) }
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassChrome(in: Rectangle())
    }
}

// MARK: - Content

/// The scrollable body of the popover, separate from `PopoverView` so it can also be
/// rendered directly (e.g. offscreen for README assets — ScrollView contents don't
/// survive `ImageRenderer`).
struct PopoverContentView: View {
    @ObservedObject var appModel: AppModel

    private var providers: [UsageProvider] { appModel.orderedProviders }

    /// Providers that produced at least one quota window → gauge cards. A provider whose
    /// latest refresh failed keeps showing its last good snapshot (freshly fetched or
    /// restored from disk) — the failure is still listed in the problems section below,
    /// but usage the owner is tracking must not vanish because one poll errored. Only
    /// `.notConfigured` hides the card: the owner signed out, so old numbers are noise.
    private var withData: [(provider: UsageProvider, snapshot: ProviderSnapshot)] {
        providers.compactMap { provider in
            guard let snapshot = appModel.snapshotsByProvider[provider.id],
                  !snapshot.quotas.isEmpty,
                  appModel.errorKindByProvider[provider.id] != .notConfigured
            else { return nil }
            return (provider, snapshot)
        }
    }

    /// Everything else: errors, unconfigured, still loading — quiet rows at the bottom.
    private var problems: [(provider: UsageProvider, message: String, kind: ProviderErrorPresentation?)] {
        providers.compactMap { provider in
            if let message = appModel.errorsByProvider[provider.id] {
                return (provider, message, appModel.errorKindByProvider[provider.id])
            }
            if appModel.snapshotsByProvider[provider.id] == nil {
                return (provider, L("Carregando…"), nil)
            }
            if appModel.snapshotsByProvider[provider.id]?.quotas.isEmpty == true {
                return (provider, L("Sem dados de cota"), nil)
            }
            return nil
        }
    }

    /// Most critical window overall: smallest remaining fraction; ties → nearest reset.
    private var hero: (provider: UsageProvider, window: QuotaWindow, remaining: Double)? {
        var best: (UsageProvider, QuotaWindow, Double)?
        for (provider, snapshot) in withData {
            for window in snapshot.quotas {
                guard let remaining = QuotaPresentation.remainingFraction(window.shape) else { continue }
                if let (_, currentWindow, currentRemaining) = best {
                    if remaining < currentRemaining ||
                        (remaining == currentRemaining &&
                         (window.shape.resetAt ?? .distantFuture) < (currentWindow.shape.resetAt ?? .distantFuture)) {
                        best = (provider, window, remaining)
                    }
                } else {
                    best = (provider, window, remaining)
                }
            }
        }
        return best
    }

    /// Volume de hoje + 14 dias, antes das cotas. Fix round 1: a versão original (label +
    /// valor empilhados + gráfico de 28pt) tomava ~100pt e derrubava uma linha inteira de
    /// cards de cota para fora dos 480pt visíveis sem rolar — reprovada em revisão. Esta
    /// versão é uma única linha (~30pt): rótulo, valor e o gráfico viram um traço fino de
    /// fundo em vez de um bloco com altura própria. A cota continua tendo prioridade: se
    /// mesmo compacta ela ainda espremer os cards, o caminho é remover a faixa, não a
    /// cota — ver relatório da task.
    @ViewBuilder private var todayStrip: some View {
        if let analytics = appModel.aggregatedAnalytics {
            let totals = TrendSeries.dailyTotals(analytics, lastDays: 14)
            // Cronológico: hoje é o último elemento.
            let today = totals.last?.tokens ?? 0
            if today > 0 {
                HStack(spacing: Theme.Space.sm) {
                    Text(L("Hoje"))
                        .font(Theme.Font.label)
                        .foregroundStyle(.secondary)
                    Text(TokenAnalytics.compactTokens(today))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    DailyTokensAreaChart(points: totals, color: .accentColor)
                        .frame(height: 18)
                }
                .padding(.horizontal, Theme.Space.md)
                .padding(.vertical, Theme.Space.xs)
                .glassChrome()
                .padding(.horizontal, Theme.Space.md)
            }
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            if withData.isEmpty && !problems.isEmpty && problems.allSatisfy({ $0.kind == .notConfigured || $0.kind == nil }) {
                OnboardingEmptyState()
            }
            todayStrip
            if let hero {
                HeroCard(
                    provider: hero.provider,
                    window: hero.window,
                    remaining: hero.remaining,
                    isPinned: appModel.isPinned(providerId: hero.provider.id, windowLabel: hero.window.label),
                    onPin: { appModel.togglePin(providerId: hero.provider.id, windowLabel: hero.window.label) }
                )
            }
            // `alignment: .top` no `GridItem`: sem ele o grid centraliza verticalmente os
            // cards de uma linha e o card mais curto flutua no meio.
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10, alignment: .top),
                                GridItem(.flexible(), spacing: 10, alignment: .top)],
                      spacing: 10) {
                ForEach(withData, id: \.provider.id) { entry in
                    ProviderGaugeCard(
                        provider: entry.provider,
                        snapshot: entry.snapshot,
                        history: appModel.historyByProvider[entry.provider.id] ?? [],
                        estimatedCost: appModel.estimatedCostByProvider[entry.provider.id],
                        isPinned: { appModel.isPinned(providerId: entry.provider.id, windowLabel: $0) },
                        onPin: { appModel.togglePin(providerId: entry.provider.id, windowLabel: $0) }
                    )
                }
            }
            if !problems.isEmpty {
                ProblemsSection(problems: problems, onOpenPreferences: { providerId in
                    appModel.requestedPreferencesPane = providerId
                })
            }
        }
        .padding(12)
        .task { await appModel.loadAllAnalyticsIfStale() }
    }
}

// MARK: - Hero

/// Spotlight on the window closest to running out. The provider still appears in the
/// grid below — this is a highlight, not a move.
private struct HeroCard: View {
    let provider: UsageProvider
    let window: QuotaWindow
    let remaining: Double
    let isPinned: Bool
    let onPin: () -> Void

    private var danger: Color { QuotaPresentation.color(remaining: remaining) }
    private var identity: Color { ProviderPalette.color(for: provider.id) }

    var body: some View {
        HStack(spacing: 14) {
            RingGauge(remaining: remaining, size: 56, color: danger, lineWidth: 6) {
                Text("\(Int((remaining * 100).rounded()))")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(danger)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(ProviderPalette.glyph(for: provider))
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(identity)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5).fill(identity.opacity(0.16)))
                    Text("\(provider.displayName) · \(WindowLabelCatalog.displayLabel(window.label))")
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(QuotaPresentation.remainingText(window.shape))
                    .font(.system(size: 15, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(danger)
                if let reset = QuotaPresentation.resetText(window.shape) {
                    Text(reset).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            PinButton(isPinned: isPinned, identity: identity, onPin: onPin)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(danger.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(danger.opacity(0.25)))
        .help(window.shape.isEstimated ? L("Estimativa local, não confirmada pelo provedor") : "")
    }
}

// MARK: - Provider card

private struct ProviderGaugeCard: View {
    let provider: UsageProvider
    let snapshot: ProviderSnapshot
    let history: [UsageHistoryPoint]
    let estimatedCost: Decimal?
    let isPinned: (String) -> Bool
    let onPin: (String) -> Void

    private var identity: Color { ProviderPalette.color(for: provider.id) }

    /// The provider's worst percent window drives the card's ring; balance-only
    /// providers show their value instead.
    private var worst: (window: QuotaWindow, remaining: Double)? {
        snapshot.quotas
            .compactMap { w in QuotaPresentation.remainingFraction(w.shape).map { (w, $0) } }
            .min { $0.1 < $1.1 }
    }

    var body: some View {
        DashboardCard(padding: Theme.Space.sm) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(ProviderPalette.glyph(for: provider))
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(identity)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5).fill(identity.opacity(0.16)))
                    Text(provider.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    if let plan = snapshot.planLabel {
                        PlanBadge(label: plan)
                    }
                    Spacer(minLength: 0)
                }
                HStack {
                    Spacer(minLength: 0)
                    if let worst {
                        RingGauge(remaining: worst.remaining,
                                  size: 44,
                                  color: QuotaPresentation.color(remaining: worst.remaining),
                                  lineWidth: 5) {
                            Text("\(Int((worst.remaining * 100).rounded()))")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(QuotaPresentation.color(remaining: worst.remaining))
                        }
                    } else if let balance = snapshot.quotas.first {
                        Text(QuotaPresentation.remainingText(balance.shape))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                            .frame(height: 44)
                    }
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(snapshot.quotas, id: \.label) { window in
                        QuotaLine(
                            window: window,
                            identity: identity,
                            isPinned: isPinned(window.label),
                            onPin: { onPin(window.label) }
                        )
                    }
                }
                if history.count >= 2 {
                    SparklineView(
                        points: history.map(\.usedPercent),
                        color: worst.map { QuotaPresentation.color(remaining: $0.remaining) } ?? identity
                    )
                    .help(L("Uso nas últimas 24h"))
                }
                if let estimatedCost {
                    Label(LF("Custo est.: $%@ (30d)", Self.costText(estimatedCost)), systemImage: "dollarsign.circle")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .help(L("Estimativa: tokens locais × tabela de preços do OpenRouter"))
                }
                if let staleness = Self.stalenessText(fetchedAt: snapshot.fetchedAt) {
                    Label(staleness, systemImage: "clock")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .help(L("Última atualização bem-sucedida — a busca mais recente falhou ou ainda não rodou"))
                }
            }
        }
    }

    static func costText(_ value: Decimal) -> String {
        String(format: "%.2f", (value as NSDecimalNumber).doubleValue)
    }

    /// "Atualizado há 25min" once the snapshot is older than any provider's normal poll
    /// cadence — i.e. only when the data on screen is genuinely a survivor (app just
    /// relaunched, or refreshes have been failing). Fresh cards stay caption-free.
    static func stalenessText(fetchedAt: Date, now: Date = Date()) -> String? {
        let age = now.timeIntervalSince(fetchedAt)
        guard age > 15 * 60 else { return nil }
        let fmt = DateComponentsFormatter()
        fmt.unitsStyle = .abbreviated
        fmt.allowedUnits = [.day, .hour, .minute]
        fmt.maximumUnitCount = 2
        guard let s = fmt.string(from: age) else { return nil }
        return LF("Atualizado há %@", s)
    }
}

/// One compact line per quota window inside a card.
private struct QuotaLine: View {
    let window: QuotaWindow
    let identity: Color
    let isPinned: Bool
    let onPin: () -> Void

    var body: some View {
        let remaining = QuotaPresentation.remainingFraction(window.shape)
        HStack(spacing: 4) {
            PinButton(isPinned: isPinned, identity: identity, onPin: onPin)
            Text(WindowLabelCatalog.displayLabel(window.label))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 2)
            VStack(alignment: .trailing, spacing: 0) {
                Text(QuotaPresentation.remainingText(window.shape))
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(remaining != nil ? QuotaPresentation.color(remaining: remaining) : .primary)
                    .lineLimit(1)
                if let reset = QuotaPresentation.resetText(window.shape) {
                    Text(reset).font(.system(size: 9)).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
        }
        .help(window.shape.isEstimated ? L("Estimativa local, não confirmada pelo provedor") : "")
    }
}

private struct PinButton: View {
    let isPinned: Bool
    let identity: Color
    let onPin: () -> Void

    var body: some View {
        Button(action: onPin) {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(.system(size: 9))
                .foregroundStyle(isPinned ? identity : Color.secondary.opacity(0.45))
        }
        .buttonStyle(.plain)
        .help(isPinned ? L("Remover da barra de menu") : L("Fixar esta janela na barra de menu"))
    }
}

// MARK: - Problems

private struct ProblemsSection: View {
    let problems: [(provider: UsageProvider, message: String, kind: ProviderErrorPresentation?)]
    let onOpenPreferences: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(problems, id: \.provider.id) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(ProviderPalette.glyph(for: entry.provider))
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(ProviderPalette.color(for: entry.provider.id).opacity(0.7))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 4)
                            .fill(ProviderPalette.color(for: entry.provider.id).opacity(0.10)))
                    Text(entry.provider.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(entry.message)
                        .font(.system(size: 10))
                        .foregroundStyle(color(for: entry.kind))
                        .lineLimit(2)
                        .help(entry.message)
                    Spacer(minLength: 0)
                    if let action = actionTitle(for: entry.kind) {
                        OpenSettingsButton(beforeOpen: { onOpenPreferences(entry.provider.id) }) {
                            Text(action)
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(color(for: entry.kind).opacity(0.14)))
                                .foregroundStyle(color(for: entry.kind))
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.03)))
    }

    /// Reconexão e configuração inicial têm remédio nas Preferências; erro genérico
    /// (rede, HTTP 500) não tem botão porque não há nada para o dono clicar lá.
    private func actionTitle(for kind: ProviderErrorPresentation?) -> String? {
        switch kind {
        case .needsReauth: return L("Reconectar")
        case .notConfigured: return L("Configurar")
        default: return nil
        }
    }

    private func color(for kind: ProviderErrorPresentation?) -> Color {
        switch kind {
        case .notConfigured: return .secondary
        case .needsReauth: return .orange
        case .error: return .red
        case nil: return .secondary
        }
    }
}

// MARK: - Empty state

/// Cold start com nada configurado: em vez de 8 linhas cinzas, uma chamada única para a
/// primeira conexão (padrão Quotio: ícone + headline + CTA).
private struct OnboardingEmptyState: View {
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.12)).frame(width: 56, height: 56)
                Image(systemName: "gauge.with.needle")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.accentColor)
            }
            Text(L("Conecte seu primeiro provedor"))
                .font(.system(size: 13, weight: .semibold))
            Text(L("Claude, Codex, Cursor, Copilot e outros — cotas e saldos num lugar só."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            OpenSettingsButton(beforeOpen: {}) {
                Text(L("Abrir Preferências"))
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(Color.accentColor))
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}

/// Botão reutilizável que abre a janela de Ajustes via `SettingsLink`, executando
/// `beforeOpen` primeiro — usado para deep-link do pane.
private struct OpenSettingsButton<L: View>: View {
    let beforeOpen: () -> Void
    @ViewBuilder let label: () -> L

    var body: some View {
        SettingsLink { label() }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded {
                beforeOpen()
                NSApp.activate(ignoringOtherApps: true)
            })
    }
}
