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
            BrandMark(size: 15)
            Text("OkTally").font(.system(size: 14, weight: .bold))
            if let update = appModel.availableUpdate {
                Button {
                    NSWorkspace.shared.open(update.url)
                } label: {
                    Label(LF("%@ disponível", update.version), systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.Brand.heatOrange.opacity(0.18)))
                        .foregroundStyle(Theme.Brand.heatOrange)
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

    /// Providers that produced at least one quota window → hero or list row. A provider whose
    /// latest refresh failed keeps showing its last good snapshot (freshly fetched or
    /// restored from disk) — the failure is still listed in the problems section below,
    /// but usage the owner is tracking must not vanish because one poll errored. Only
    /// `.notConfigured` hides the row: the owner signed out, so old numbers are noise.
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
    /// linha inteira de cota para fora dos 480pt visíveis sem rolar — reprovada em revisão. Esta
    /// versão é uma única linha (~30pt): rótulo, valor e o gráfico viram um traço fino de
    /// fundo em vez de um bloco com altura própria. A cota continua tendo prioridade: se
    /// mesmo compacta ela ainda espremer as cotas, o caminho é remover a faixa, não a
    /// cota — ver relatório da task.
    @ViewBuilder private var todayStrip: some View {
        if let analytics = appModel.aggregatedAnalytics {
            let totals = TrendSeries.dailyTotals(analytics, lastDays: 14)
            // Cronológico: hoje é o último elemento.
            let today = totals.last?.tokens ?? 0
            if today > 0 {
                HStack(spacing: Theme.Space.sm) {
                    SectionHeader(L("Hoje"))
                    Text(TokenAnalytics.compactTokens(today))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    DailyTokensAreaChart(points: totals, color: Theme.accent)
                        .frame(height: 18)
                }
                .padding(.horizontal, Theme.Space.md)
                .padding(.vertical, Theme.Space.xs)
                .glassChrome()
                .padding(.horizontal, Theme.Space.md)
            }
        }
    }

    /// Everyone except the hero's provider: the hero already spends the top of the
    /// popover on it, and repeating it as a row below burns a line of a 480pt fold to
    /// say nothing new. Its other windows ride along inside the hero block.
    private var listed: [(provider: UsageProvider, snapshot: ProviderSnapshot)] {
        guard let heroId = hero?.provider.id else { return withData }
        return withData.filter { $0.provider.id != heroId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if withData.isEmpty && !problems.isEmpty && problems.allSatisfy({ $0.kind == .notConfigured || $0.kind == nil }) {
                OnboardingEmptyState()
            }
            if let hero {
                HeroBlock(
                    provider: hero.provider,
                    window: hero.window,
                    remaining: hero.remaining,
                    others: PopoverLayout.orderedWindows(
                        appModel.snapshotsByProvider[hero.provider.id]?.quotas ?? []
                    ).filter { $0.label != hero.window.label },
                    isPinned: { appModel.isPinned(providerId: hero.provider.id, windowLabel: $0) },
                    onPin: { appModel.togglePin(providerId: hero.provider.id, windowLabel: $0) }
                )
            }
            // Abaixo do herói, não acima: a posição mais valiosa da tela é o topo, e ela
            // pertence ao número dominante. Com a faixa em cima, a primeira coisa que o
            // olho encontrava era uma tira de vidro cinza. A faixa continua existindo,
            // com o mesmo conteúdo e o mesmo `glassChrome` — só deixou de disputar o topo.
            todayStrip
            if !listed.isEmpty {
                // As linhas agora moram DENTRO de um card, não soltas sobre a página.
                // É o agrupamento por proximidade das referências: o bloco-herói (cor
                // cheia) e a lista (superfície neutra) viram dois objetos, em vez de um
                // retângulo colorido seguido de texto flutuando no vazio.
                VStack(alignment: .leading, spacing: 11) {
                    SectionHeader(L("Outras cotas"))
                    ForEach(listed, id: \.provider.id) { entry in
                        ProviderQuotaRow(
                            provider: entry.provider,
                            snapshot: entry.snapshot,
                            estimatedCost: appModel.estimatedCostByProvider[entry.provider.id],
                            isPinned: { appModel.isPinned(providerId: entry.provider.id, windowLabel: $0) },
                            onPin: { appModel.togglePin(providerId: entry.provider.id, windowLabel: $0) }
                        )
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()
            }
            if !problems.isEmpty {
                ProblemsSection(problems: problems, onOpenPreferences: { providerId in
                    appModel.requestedPreferencesPane = providerId
                })
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Base quase preta explícita: é o chão contra o qual os cards são "um degrau
        // mais claros". Sem ela o popover herda o cinza da janela e todo o contraste de
        // superfície que o resto do desenho supõe deixa de existir.
        .background(Theme.pageBackground)
        .task { await appModel.loadAllAnalyticsIfStale() }
    }
}

// MARK: - Layout helpers

/// Pure ordering rules for the popover, kept out of the views so they can be tested.
enum PopoverLayout {
    /// Windows of one provider, tightest first. Windows without a percentage (pure
    /// balances) have no "tightness" to compare, so they sink to the end instead of
    /// being compared against 0. Stable for equal remainings: original order wins.
    static func orderedWindows(_ quotas: [QuotaWindow]) -> [QuotaWindow] {
        quotas.enumerated().sorted { lhs, rhs in
            let l = QuotaPresentation.remainingFraction(lhs.element.shape)
            let r = QuotaPresentation.remainingFraction(rhs.element.shape)
            switch (l, r) {
            case let (l?, r?):
                if l != r { return l < r }
                return lhs.offset < rhs.offset
            case (nil, .some): return false
            case (.some, nil): return true
            case (nil, nil): return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }
}

// MARK: - Pin

private struct PinButton: View {
    let isPinned: Bool
    let identity: Color
    /// Sobre o gradiente do herói o estado "não fixado" não pode ser `.secondary` (cinza
    /// do sistema, invisível sobre cor saturada) — vira off-white rebaixado.
    var onHero: Bool = false
    let onPin: () -> Void

    var body: some View {
        Button(action: onPin) {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(.system(size: 9))
                .foregroundStyle(isPinned ? identity : (onHero ? Theme.onHero.opacity(0.5) : Color.secondary.opacity(0.45)))
        }
        .buttonStyle(.plain)
        .help(isPinned ? L("Remover da barra de menu") : L("Fixar esta janela na barra de menu"))
    }
}

// MARK: - Identity chip

/// The provider's colored initial. The only place the identity color is loud; it is what
/// tells two rows apart at a glance, since the danger color is reserved for the numbers.
private struct IdentityChip: View {
    let provider: UsageProvider
    var size: CGFloat = 22

    var body: some View {
        IconChip(glyph: ProviderPalette.glyph(for: provider),
                 color: ProviderPalette.color(for: provider.id),
                 size: size)
    }
}

// MARK: - Hero

/// The one window closest to running out, and the only block in the popover that gets
/// display-size type. Everything else is a row — that is what makes this read as the
/// answer to "what is about to hurt?" instead of one of nine equal gauges.
///
/// No ring here on purpose: a ring drawn around the number repeats it (the old hero had
/// a "26" inside the ring *and* "26% left" beside it). One number, one bar.
private struct HeroBlock: View {
    let provider: UsageProvider
    let window: QuotaWindow
    let remaining: Double
    /// The hero provider's remaining windows — it is excluded from the list below, so
    /// they would otherwise disappear.
    let others: [QuotaWindow]
    let isPinned: (String) -> Bool
    let onPin: (String) -> Void

    private var danger: Color { QuotaPresentation.color(remaining: remaining) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // Chip em off-white sobre a cor do bloco: a identidade do provedor já
                // está dita pela linha abaixo, e um chip colorido sobre gradiente
                // colorido vira mancha.
                Text(ProviderPalette.glyph(for: provider))
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(danger)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.onHero))
                Text(provider.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.onHero)
                Text("· " + WindowLabelCatalog.displayLabel(window.label))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.onHero.opacity(0.75))
                    .lineLimit(1)
                Spacer(minLength: 4)
                PinButton(isPinned: isPinned(window.label),
                          identity: Theme.onHero,
                          onHero: true,
                          onPin: { onPin(window.label) })
            }
            // Número dominante do popover: 44pt contra rótulos de 9–11pt. É o contraste
            // de TAMANHO que cria a hierarquia — o bloco poderia ser monocromático e
            // ainda assim se leria primeiro.
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(QuotaPresentation.remainingValueText(window.shape))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.onHero)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(L("restante"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.onHero.opacity(0.8))
                Spacer(minLength: 6)
                if let reset = QuotaPresentation.resetText(window.shape) {
                    Text(reset)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.onHero.opacity(0.8))
                        .lineLimit(1)
                }
            }
            QuotaCapsuleBar(remaining: remaining, color: Theme.onHero, height: 8,
                            track: AnyShapeStyle(Color.black.opacity(0.22)))
            ForEach(others, id: \.label) { other in
                SecondaryWindowLine(window: other,
                                    identity: Theme.onHero,
                                    onHero: true,
                                    isPinned: isPinned(other.label),
                                    onPin: { onPin(other.label) })
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .heroSurface(danger)
        .help(window.shape.isEstimated ? L("Estimativa local, não confirmada pelo provedor") : "")
    }
}

// MARK: - Provider row

/// One provider per row, constant vertical rhythm. Replaces the two-column grid of
/// natural-height gauge cards: at 360pt wide those columns never ended on the same line
/// and left holes of up to 200pt beside a short card.
///
/// Reading order across the row is fixed — identity, who, which window, when it comes
/// back, how much is left — so the eye scans one column of percentages down the list.
private struct ProviderQuotaRow: View {
    let provider: UsageProvider
    let snapshot: ProviderSnapshot
    let estimatedCost: Decimal?
    let isPinned: (String) -> Bool
    let onPin: (String) -> Void

    private var identity: Color { ProviderPalette.color(for: provider.id) }
    private var windows: [QuotaWindow] { PopoverLayout.orderedWindows(snapshot.quotas) }

    var body: some View {
        let primary = windows.first
        let remaining = primary.flatMap { QuotaPresentation.remainingFraction($0.shape) }
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                IdentityChip(provider: provider)
                Text(provider.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .layoutPriority(1)
                if let primary {
                    Text("· " + WindowLabelCatalog.displayLabel(primary.label))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let plan = snapshot.planLabel { PlanBadge(label: plan) }
                Spacer(minLength: 4)
                if let primary {
                    if let reset = QuotaPresentation.resetCompactText(primary.shape) {
                        Text(reset)
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                    // Fixed *minimum* width, trailing-aligned: the percentages line up
                    // in one column down the list so the eye scans them without
                    // re-anchoring. A balance ("19.82 USD") simply spills to the left.
                    Text(QuotaPresentation.remainingValueText(primary.shape))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(QuotaPresentation.valueColor(remaining: remaining))
                        .frame(minWidth: 44, alignment: .trailing)
                        .layoutPriority(2)
                    PinButton(isPinned: isPinned(primary.label), identity: identity,
                              onPin: { onPin(primary.label) })
                }
            }
            // Identity color on the bar, danger color on the number: the row says whose
            // quota it is and how bad it is with two different channels, instead of
            // painting the whole popover green.
            // Indented to the text column, not full-bleed: a bar that ran edge to edge
            // read as a rule *between* rows and stole the following secondary line.
            if let remaining {
                QuotaCapsuleBar(remaining: remaining, color: identity, height: 4)
                    // 30 = chip (22) + o spacing (7) da HStack acima, arredondado: a barra
                    // começa na coluna do NOME, não na do chip.
                    .padding(.leading, 30)
                    // Asymmetric on purpose: the bar hugs the line it measures and keeps
                    // its distance from the provider's secondary window below.
                    .padding(.bottom, 2)
            }
            ForEach(windows.dropFirst(), id: \.label) { window in
                SecondaryWindowLine(window: window, identity: identity,
                                    isPinned: isPinned(window.label),
                                    onPin: { onPin(window.label) })
            }
            if let meta = metaText {
                Text(meta)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .help(L("Estimativa: tokens locais × tabela de preços do OpenRouter"))
            }
        }
        .help(snapshot.quotas.contains(where: \.shape.isEstimated)
              ? L("Estimativa local, não confirmada pelo provedor") : "")
    }

    /// Cost estimate and staleness share one tertiary line — both are footnotes, and two
    /// separate labeled rows per provider was most of the old cards' dead space.
    private var metaText: String? {
        var parts: [String] = []
        if let estimatedCost {
            parts.append(LF("Custo est.: $%@ (30d)", Self.costText(estimatedCost)))
        }
        if let staleness = Self.stalenessText(fetchedAt: snapshot.fetchedAt) {
            parts.append(staleness)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func costText(_ value: Decimal) -> String {
        String(format: "%.2f", (value as NSDecimalNumber).doubleValue)
    }

    /// "Atualizado há 25min" once the snapshot is older than any provider's normal poll
    /// cadence — i.e. only when the data on screen is genuinely a survivor (app just
    /// relaunched, or refreshes have been failing). Fresh rows stay caption-free.
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

/// A provider's second (and third…) window: same columns as the row above it, one step
/// quieter, and no bar — the bar belongs to the window that is actually at risk.
private struct SecondaryWindowLine: View {
    let window: QuotaWindow
    let identity: Color
    var onHero: Bool = false
    let isPinned: Bool
    let onPin: () -> Void

    var body: some View {
        let remaining = QuotaPresentation.remainingFraction(window.shape)
        HStack(spacing: 6) {
            Text(WindowLabelCatalog.displayLabel(window.label))
                .font(.system(size: 10))
                .foregroundStyle(onHero ? AnyShapeStyle(Theme.onHero.opacity(0.75)) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                .lineLimit(1)
            Spacer(minLength: 4)
            if let reset = QuotaPresentation.resetCompactText(window.shape) {
                Text(reset)
                    .font(.system(size: 9))
                    .monospacedDigit()
                    .foregroundStyle(onHero ? AnyShapeStyle(Theme.onHero.opacity(0.6)) : AnyShapeStyle(HierarchicalShapeStyle.tertiary))
                    .layoutPriority(1)
            }
            Text(QuotaPresentation.remainingValueText(window.shape))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(onHero ? Theme.onHero : QuotaPresentation.valueColor(remaining: remaining))
                .frame(minWidth: 44, alignment: .trailing)
                .layoutPriority(2)
            PinButton(isPinned: isPinned, identity: identity, onHero: onHero, onPin: onPin)
        }
        // Deeper than the provider name's column: the extra step is what says this
        // window hangs off the row above instead of starting a new provider.
        .padding(.leading, 30)
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
                    IconChip(glyph: ProviderPalette.glyph(for: entry.provider),
                             color: ProviderPalette.color(for: entry.provider.id).opacity(0.55),
                             size: 16)
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
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
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
        case .needsReauth: return Theme.Brand.heatOrange
        case .error: return Theme.Brand.neonMagenta
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
                Circle().fill(Theme.accent.opacity(0.16)).frame(width: 56, height: 56)
                Image(systemName: "gauge.with.needle")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.accent)
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
                    .background(Capsule().fill(Theme.accent))
                    .foregroundStyle(Theme.Brand.charcoal)
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
