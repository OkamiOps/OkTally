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
        .frame(width: 410)
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

    /// `popoverProviders`, não `orderedProviders`: é o único filtro do "Mostrar no
    /// menu" das Preferências — pinos, notch e alertas continuam enxergando todo mundo.
    private var providers: [UsageProvider] { appModel.popoverProviders }

    /// Providers that produced at least one quota window → hero or list row. A provider whose
    /// latest refresh failed keeps showing its last good snapshot (freshly fetched or
    /// restored from disk) — the failure is still listed in the problems section below,
    /// but usage the owner is tracking must not vanish because one poll errored. Only
    /// `.notConfigured` hides the row: the owner signed out, so old numbers are noise.
    private var withData: [(provider: UsageProvider, snapshot: ProviderSnapshot)] {
        providers.compactMap { provider in
            let snapshot = appModel.snapshotsByProvider[provider.id]
            guard ProviderPresentationPolicy.showsSnapshot(
                snapshot,
                errorKind: appModel.errorKindByProvider[provider.id]
            ), let snapshot
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

    /// O card-herói: a escolha do dono em `appModel.popoverHeroSlot`, ou — em automático,
    /// a janela mais crítica entre as representativas de cada produto (menor fração
    /// restante; empate desempata pelo reset mais próximo). A regra em si mora no
    /// `QuotaSlotResolver`, testável sem tela; aqui só se traduz o `Candidate` de volta
    /// para o `UsageProvider` que a view precisa.
    private var hero: (provider: UsageProvider, window: QuotaWindow, remaining: Double?)? {
        guard let candidate = QuotaSlotResolver.popoverHero(
            slot: appModel.popoverHeroSlot,
            snapshots: Dictionary(uniqueKeysWithValues: withData.map { ($0.provider.id, $0.snapshot) }),
            providerOrder: providers.map(\.id),
            // Do MODELO e não do `AccountDirectoryHolder`: assim o popover recompõe no
            // mesmo quadro em que o dono escolhe outra cota principal.
            preferredLabels: { appModel.primaryWindowLabel(forProviderId: $0) }
        ), let provider = providers.first(where: { $0.id == candidate.providerId }) else {
            return nil
        }
        return (provider, candidate.window, QuotaPresentation.remainingFraction(candidate.window.shape))
    }

    private var forecastProvider: UsageProvider? {
        guard let forecast = appModel.selectedForecast else { return nil }
        return providers.first { $0.id == forecast.id.providerId }
    }

    private var showsUnavailableForecast: Bool {
        if case .window = appModel.forecastSlot { return true }
        return false
    }

    private var expandedForecastID: ForecastWindowID? {
        appModel.selectedForecast?.id
    }

    private func forecast(providerId: String, windowLabel: String) -> UsageForecast? {
        appModel.forecastsByWindow[
            ForecastWindowID(providerId: providerId, windowLabel: windowLabel)
        ]
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
                let shape = RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                HStack(spacing: Theme.Space.sm) {
                    SectionHeader(L("Hoje"))
                    Text(TokenAnalytics.compactTokens(today))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.accent)
                    DailyTokensAreaChart(points: totals, color: Theme.accent)
                        .frame(height: 22)
                }
                .padding(.horizontal, Theme.Space.md)
                .padding(.vertical, Theme.Space.sm)
                // Charcoal + fio de Volt Cyan, e NÃO vidro. A faixa era a única peça do
                // popover que mudava de identidade entre os dois mundos: viva ela era
                // vidro, sob `ImageRenderer` o vidro cai no material e ela virava uma
                // pastilha CINZA — do tamanho de um botão, sem cor, no meio de um
                // dashboard de acento neon. E o próprio comentário do `Theme` já admitia
                // que ela é a exceção do vidro por carregar número e gráfico, ou seja:
                // conteúdo, não cromo. Aqui ela é um objeto declarado, idêntico nos dois
                // mundos: fundo do mesmo degrau dos cards, lavagem ciano dando direção da
                // esquerda para a direita e uma borda neon fina que a separa do fundo sem
                // virar moldura.
                // Ordem importa: o `.background` mais EXTERNO é o que fica mais atrás,
                // então a lavagem ciano vem primeiro (colada no conteúdo) e o charcoal
                // opaco por baixo dela. Invertido, o opaco cobriria a lavagem.
                .background(
                    shape.fill(LinearGradient(
                        colors: [Theme.accent.opacity(0.16), Theme.accent.opacity(0.02)],
                        startPoint: .leading, endPoint: .trailing))
                )
                .background(shape.fill(Theme.surface()))
                .overlay(shape.strokeBorder(Theme.accent.opacity(0.38)))
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
                        appModel.snapshotsByProvider[hero.provider.id]?.quotas ?? [],
                        providerId: hero.provider.id,
                        preferredLabel: appModel.primaryWindowLabel(forProviderId: hero.provider.id)
                    ).filter { $0.label != hero.window.label },
                    preferredLabel: appModel.primaryWindowLabel(forProviderId: hero.provider.id),
                    isPinned: { appModel.isPinned(providerId: hero.provider.id, windowLabel: $0) },
                    onPin: { appModel.togglePin(providerId: hero.provider.id, windowLabel: $0) },
                    onHighlight: { appModel.popoverHeroSlot = .window(providerId: hero.provider.id, windowLabel: $0) },
                    onMakePrimary: { appModel.setPrimaryWindow(providerId: hero.provider.id, windowLabel: $0) },
                    forecast: { forecast(providerId: hero.provider.id, windowLabel: $0) },
                    expandedForecastID: expandedForecastID,
                    onHide: { appModel.popoverHiddenProviders.insert(hero.provider.id) }
                )
            }
            if let forecast = appModel.selectedForecast,
               let provider = forecastProvider {
                ForecastBarsView(
                    providerId: provider.id,
                    providerName: provider.displayName,
                    forecast: forecast,
                    showUnavailable: showsUnavailableForecast
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
                            preferredLabel: appModel.primaryWindowLabel(forProviderId: entry.provider.id),
                            isPinned: { appModel.isPinned(providerId: entry.provider.id, windowLabel: $0) },
                            onPin: { appModel.togglePin(providerId: entry.provider.id, windowLabel: $0) },
                            onHighlight: { appModel.popoverHeroSlot = .window(providerId: entry.provider.id, windowLabel: $0) },
                            onMakePrimary: { appModel.setPrimaryWindow(providerId: entry.provider.id, windowLabel: $0) },
                            forecast: { forecast(providerId: entry.provider.id, windowLabel: $0) },
                            expandedForecastID: expandedForecastID,
                            onHide: { appModel.popoverHiddenProviders.insert(entry.provider.id) }
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
                }, onHide: { providerId in
                    appModel.popoverHiddenProviders.insert(providerId)
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
    /// Windows of one provider, normally tightest first. Windows without a percentage
    /// sink to the end. Stable for equal remainings: original order wins.
    ///
    /// `preferredLabel` é a escolha do dono para esta conta
    /// (`AccountInstance.primaryWindowLabel`): quando a janela existe no snapshot, ela
    /// vai para a frente, seja ela qual for. Escolha que sumiu cai para automático em
    /// silêncio — a mesma regra dos slots do notch, e pela mesma razão: um provedor que
    /// parou de devolver uma janela não pode virar um buraco na tela.
    ///
    /// No automático do Codex, a principal é a mais apertada entre as janelas GERAIS
    /// (a sessão de 5h e a semanal). Antes era sempre a semanal, e numa conta Business
    /// isso escondia justamente a cota que acaba durante o dia. Janelas específicas de
    /// modelo ("GPT-5.3-Codex-Spark (5h)") continuam sem poder ganhar no automático:
    /// elas medem a capacidade de um modelo, não a do plano.
    static func orderedWindows(
        _ quotas: [QuotaWindow],
        providerId: String? = nil,
        preferredLabel: String? = nil
    ) -> [QuotaWindow] {
        let tightestFirst = quotas.enumerated().sorted { lhs, rhs in
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

        guard let primaryIndex = primaryIndex(
            in: tightestFirst, providerId: providerId, preferredLabel: preferredLabel
        ) else { return tightestFirst }
        var ordered = tightestFirst
        ordered.insert(ordered.remove(at: primaryIndex), at: 0)
        return ordered
    }

    static func primaryWindow(
        providerId: String,
        quotas: [QuotaWindow],
        preferredLabel: String? = nil
    ) -> QuotaWindow? {
        orderedWindows(quotas, providerId: providerId, preferredLabel: preferredLabel).first
    }

    /// Qual das janelas já ordenadas por aperto vai para a frente, ou `nil` para deixar a
    /// ordem como está (a mais apertada já é a primeira).
    private static func primaryIndex(
        in tightestFirst: [QuotaWindow],
        providerId: String?,
        preferredLabel: String?
    ) -> Int? {
        if let preferredLabel, !preferredLabel.isEmpty,
           let chosen = tightestFirst.firstIndex(where: { $0.label == preferredLabel }) {
            return chosen
        }
        guard let providerId, AccountID.kind(of: providerId) == .codex else { return nil }
        // `tightestFirst` já está em ordem de aperto, então a PRIMEIRA geral com
        // percentual é a mais apertada entre as gerais.
        return tightestFirst.firstIndex {
            !isModelSpecific($0) && QuotaPresentation.remainingFraction($0.shape) != nil
        }
    }

    /// Janela específica de modelo: o Codex as devolve no formato "Modelo (janela)" —
    /// "GPT-5.3-Codex-Spark (5h)". As gerais do plano ("5h", "weekly", "semanal") não têm
    /// esse prefixo. Reconhecer pela FORMA e não por uma lista de modelos é o que faz a
    /// regra sobreviver ao próximo modelo que a OpenAI lançar.
    static func isModelSpecific(_ window: QuotaWindow) -> Bool {
        let label = window.label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard label.hasSuffix(")"), let open = label.lastIndex(of: "(") else { return false }
        return !label[..<open].trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Quais janelas secundárias ganham uma barra própria no popover.
    ///
    /// Com até duas, todas as que têm percentual ganham: era esse o buraco do relato do
    /// dono — a sessão de 5h da conta Business aparecia só como um textinho ao pé da
    /// linha. Passando disso, só as GERAIS ganham barra e o resto fica compacto: seis
    /// barras empilhadas viram um gráfico acidental e a linha principal deixa de dominar.
    static func barredSecondaryLabels(_ secondaries: [QuotaWindow]) -> [String] {
        let withPercentage = secondaries.filter { QuotaPresentation.remainingFraction($0.shape) != nil }
        guard withPercentage.count > 2 else { return withPercentage.map(\.label) }
        return withPercentage.filter { !isModelSpecific($0) }.map(\.label)
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
    /// Atalho de qualidade: um clique-direito no alfinete oferece "Destacar", que troca
    /// o card-herói para ESTA janela sem passar por Preferências. `nil` quando a linha
    /// já É o herói (destacar o que já está destacado não diz nada novo) — o chamador
    /// decide, não este botão.
    var onHighlight: (() -> Void)? = nil

    var body: some View {
        Button(action: onPin) {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(.system(size: 9))
                .foregroundStyle(isPinned ? identity : (onHero ? Theme.onHero.opacity(0.5) : Color.secondary.opacity(0.45)))
        }
        .buttonStyle(.plain)
        .help(isPinned ? L("Remover da barra de menu") : L("Fixar esta janela na barra de menu"))
        .contextMenu {
            if let onHighlight {
                Button(L("Destacar")) { onHighlight() }
            }
        }
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
    /// `nil` para uma escolha explícita de janela sem percentual (saldo em dólares): o
    /// herói continua mostrando o valor e o nome, só não desenha barra nem tinge o
    /// bloco de perigo — a mesma regra que a lista de baixo já aplica a esse tipo de
    /// janela.
    let remaining: Double?
    /// The hero provider's remaining windows — it is excluded from the list below, so
    /// they would otherwise disappear.
    let others: [QuotaWindow]
    /// A cota principal escolhida para esta conta, ou `nil` = automático.
    let preferredLabel: String?
    let isPinned: (String) -> Bool
    let onPin: (String) -> Void
    let onHighlight: (String) -> Void
    /// Elege esta janela como a cota principal da conta (menu de contexto da linha);
    /// `nil` volta para automático.
    let onMakePrimary: (String?) -> Void
    let forecast: (String) -> UsageForecast?
    let expandedForecastID: ForecastWindowID?
    /// Esconde este provedor do popover (menu de contexto "Ocultar do menu"). Pinos,
    /// notch e alertas continuam intactos — só a lista do menu para de mostrá-lo.
    let onHide: () -> Void

    /// Cor do bloco. Já `heroTint`ada: o glifo do chip é desenhado NELA sobre um chip
    /// off-white, então ele precisa do mesmo escurecimento que o fundo recebe — senão o
    /// amarelo da escala vira uma letra invisível dentro de um selo branco.
    private var danger: Color { Theme.heroTint(QuotaPresentation.color(remaining: remaining)) }

    /// Quais das outras janelas ganham barra própria. Ver
    /// `PopoverLayout.barredSecondaryLabels`.
    private var barredSecondaries: Set<String> {
        Set(PopoverLayout.barredSecondaryLabels(others))
    }

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
            if let remaining {
                QuotaCapsuleBar(remaining: remaining, color: Theme.onHero, height: 8,
                                track: AnyShapeStyle(Color.black.opacity(0.22)))
            }
            if let pace = forecast(window.label), pace.id != expandedForecastID {
                ForecastInlinePaceView(
                    providerId: provider.id,
                    forecast: pace,
                    onHero: true
                )
            }
            ForEach(others, id: \.label) { other in
                VStack(alignment: .leading, spacing: 4) {
                    SecondaryWindowLine(window: other,
                                        identity: Theme.onHero,
                                        onHero: true,
                                        showsBar: barredSecondaries.contains(other.label),
                                        isPinned: isPinned(other.label),
                                        onPin: { onPin(other.label) },
                                        onHighlight: { onHighlight(other.label) },
                                        onMakePrimary: { onMakePrimary(other.label) })
                    if let pace = forecast(other.label), pace.id != expandedForecastID {
                        ForecastInlinePaceView(
                            providerId: provider.id,
                            forecast: pace,
                            onHero: true
                        )
                        .padding(.leading, 30)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .heroSurface(danger)
        .help(window.shape.isEstimated ? L("Estimativa local, não confirmada pelo provedor") : "")
        .contextMenu {
            if preferredLabel != nil {
                Button(L("Cota principal: automático")) { onMakePrimary(nil) }
            }
            Button(L("Ocultar do menu"), action: onHide)
        }
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
    /// A cota principal escolhida para esta conta, ou `nil` = automático.
    let preferredLabel: String?
    let isPinned: (String) -> Bool
    let onPin: (String) -> Void
    let onHighlight: (String) -> Void
    /// Elege esta janela como a cota principal da conta (menu de contexto da linha);
    /// `nil` volta para automático.
    let onMakePrimary: (String?) -> Void
    let forecast: (String) -> UsageForecast?
    let expandedForecastID: ForecastWindowID?
    /// Esconde este provedor do popover (menu de contexto "Ocultar do menu"). Pinos,
    /// notch e alertas continuam intactos — só a lista do menu para de mostrá-lo.
    let onHide: () -> Void

    private var identity: Color { ProviderPalette.color(for: provider.id) }
    private var windows: [QuotaWindow] {
        PopoverLayout.orderedWindows(snapshot.quotas, providerId: provider.id,
                                     preferredLabel: preferredLabel)
    }

    /// Quais secundárias ganham barra própria. Ver `PopoverLayout.barredSecondaryLabels`.
    private var barredSecondaries: Set<String> {
        Set(PopoverLayout.barredSecondaryLabels(Array(windows.dropFirst())))
    }

    var body: some View {
        let primary = windows.first
        let remaining = primary.flatMap { QuotaPresentation.remainingFraction($0.shape) }
        // `spacing: 0` com paddings explícitos, e não um espaçamento único: o ritmo
        // vertical da linha é ASSIMÉTRICO de propósito (ver a barra abaixo), e um
        // espaçamento uniforme distribuía o mesmo ar acima e abaixo da barra — que era
        // justamente o que fazia a barra flutuar entre duas linhas em vez de pertencer a
        // uma delas.
        VStack(alignment: .leading, spacing: 0) {
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
                    // re-anchoring.
                    if remaining == nil {
                        // Provedor só-saldo (OpenRouter): sem porcentagem ele não ganha
                        // barra, e antes a linha inteira ficava órfã — um número solto na
                        // coluna da direita, sem o traço de identidade que todas as
                        // vizinhas tinham. O chip devolve a ele a mesma quantidade de
                        // tinta: a cor do provedor aparece em ÁREA (fundo + fio), no lugar
                        // onde as outras linhas a colocam na barra.
                        BalanceChip(text: QuotaPresentation.remainingValueText(primary.shape),
                                    identity: identity)
                            .layoutPriority(2)
                    } else {
                        Text(QuotaPresentation.remainingValueText(primary.shape))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(QuotaPresentation.valueStyle(remaining: remaining))
                            .frame(minWidth: 44, alignment: .trailing)
                            .layoutPriority(2)
                    }
                    PinButton(isPinned: isPinned(primary.label), identity: identity,
                              onPin: { onPin(primary.label) },
                              onHighlight: { onHighlight(primary.label) })
                }
            }
            // Identity color on the bar, danger color on the number: the row says whose
            // quota it is and how bad it is with two different channels, instead of
            // painting the whole popover green.
            // Indented to the text column, not full-bleed: a bar that ran edge to edge
            // read as a rule *between* rows and stole the following secondary line.
            if let remaining {
                // Mais fina (3pt) e COLADA na linha que ela mede: 2pt acima contra 8pt
                // abaixo. Na versão anterior a barra tinha 4pt e ar quase igual dos dois
                // lados, e aí ela ficava equidistante entre a linha primária e a janela
                // secundária — o olho tinha de decidir de quem ela era, o que custava um
                // batimento de leitura por provedor. Com o ar todo empurrado para baixo a
                // dúvida some: barra e linha de cima são um objeto, e o espaço em branco
                // é que separa esse objeto da janela seguinte.
                QuotaCapsuleBar(remaining: remaining, color: identity, height: 3)
                    // 30 = chip (22) + o spacing (7) da HStack acima, arredondado: a barra
                    // começa na coluna do NOME, não na do chip.
                    .padding(.leading, 30)
                    .padding(.top, 2)
                    .padding(.bottom, 8)
            }
            if let primary,
               let pace = forecast(primary.label),
               pace.id != expandedForecastID {
                ForecastInlinePaceView(providerId: provider.id, forecast: pace)
                    .padding(.leading, 30)
                    .padding(.bottom, 5)
            }
            ForEach(windows.dropFirst(), id: \.label) { window in
                VStack(alignment: .leading, spacing: 4) {
                    SecondaryWindowLine(window: window, identity: identity,
                                        showsBar: barredSecondaries.contains(window.label),
                                        isPinned: isPinned(window.label),
                                        onPin: { onPin(window.label) },
                                        onHighlight: { onHighlight(window.label) },
                                        onMakePrimary: { onMakePrimary(window.label) })
                    if let pace = forecast(window.label), pace.id != expandedForecastID {
                        ForecastInlinePaceView(providerId: provider.id, forecast: pace)
                            .padding(.leading, 30)
                    }
                }
                .padding(.top, 3)
            }
            if let meta = metaText {
                Text(meta)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .padding(.top, 4)
                    .help(L("Estimativa: tokens locais × tabela de preços do OpenRouter"))
            }
        }
        .help(snapshot.quotas.contains(where: \.shape.isEstimated)
              ? L("Estimativa local, não confirmada pelo provedor") : "")
        .contextMenu {
            // O caminho de VOLTA da escolha feita no menu de contexto da linha
            // secundária. Sem ele, desfazer exigiria abrir as Preferências — e o dono
            // teria de descobrir sozinho que foi ali que ele mexeu.
            if preferredLabel != nil {
                Button(L("Cota principal: automático")) { onMakePrimary(nil) }
            }
            Button(L("Ocultar do menu"), action: onHide)
        }
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

/// Saldo em dinheiro numa pastilha da cor do provedor. Existe porque um provedor de
/// crédito puro não tem fração para desenhar — e uma linha sem barra, no meio de uma lista
/// onde todas as outras têm, lê como linha quebrada e não como "este é de outro tipo".
///
/// O número continua neutro (a mesma regra do resto do app: cor é exceção, reservada ao
/// perigo); quem carrega a identidade é a pastilha em volta.
private struct BalanceChip: View {
    let text: String
    let identity: Color

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(identity.opacity(0.18)))
            .overlay(Capsule().strokeBorder(identity.opacity(0.45)))
    }
}

/// A provider's second (and third…) window: same columns as the row above it, one step
/// quieter.
///
/// `showsBar` é a correção do relato do dono. A conta Business do Codex tem duas cotas
/// que importam — a semanal e a sessão de 5h —, e a que acaba durante o dia aparecia só
/// como "5h session 4h 55m 100%" num texto de 9–11pt ao pé da linha: "quase
/// imperceptível". Com a barra, a janela secundária vira um OBJETO com a mesma anatomia
/// da principal (rótulo, reset, número e preenchimento), só que menor — a hierarquia
/// continua existindo, a informação deixa de se esconder. Ver
/// `PopoverLayout.barredSecondaryLabels` para quem ganha barra quando há muitas janelas.
private struct SecondaryWindowLine: View {
    let window: QuotaWindow
    let identity: Color
    var onHero: Bool = false
    /// Desenha a barrinha de sobra abaixo da linha.
    var showsBar: Bool = false
    let isPinned: Bool
    let onPin: () -> Void
    var onHighlight: (() -> Void)? = nil
    /// Elege esta janela como a cota principal da conta. `nil` esconde o item do menu.
    var onMakePrimary: (() -> Void)? = nil

    var body: some View {
        let remaining = QuotaPresentation.remainingFraction(window.shape)
        VStack(alignment: .leading, spacing: 3) {
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
                    .foregroundStyle(onHero ? AnyShapeStyle(Theme.onHero) : QuotaPresentation.valueStyle(remaining: remaining))
                    .frame(minWidth: 44, alignment: .trailing)
                    .layoutPriority(2)
                PinButton(isPinned: isPinned, identity: identity, onHero: onHero, onPin: onPin, onHighlight: onHighlight)
            }
            if showsBar, let remaining {
                // 2pt contra os 3pt da barra principal, e na cor da ESCALA de uso em vez
                // da cor do provedor: a identidade já foi dita pela barra de cima, então
                // aqui a única coisa que a cor ainda pode dizer é o estado desta janela.
                // Dentro do herói a escala sairia como mancha sobre o gradiente saturado
                // — lá a barra é off-white, igual à principal do bloco.
                QuotaCapsuleBar(
                    remaining: remaining,
                    color: onHero ? Theme.onHero.opacity(0.85) : QuotaPresentation.color(remaining: remaining),
                    height: 2,
                    track: onHero ? AnyShapeStyle(Color.black.opacity(0.22)) : nil
                )
                .padding(.trailing, 14)
                .animation(.easeInOut(duration: 0.25), value: remaining)
                .transition(.opacity)
            }
        }
        // Deeper than the provider name's column: the extra step is what says this
        // window hangs off the row above instead of starting a new provider.
        .padding(.leading, 30)
        .animation(.easeInOut(duration: 0.25), value: showsBar)
        .contextMenu {
            if let onMakePrimary {
                Button(L("Usar como principal"), action: onMakePrimary)
            }
            if let onHighlight {
                Button(L("Destacar"), action: onHighlight)
            }
        }
    }
}
// MARK: - Problems

private struct ProblemsSection: View {
    let problems: [(provider: UsageProvider, message: String, kind: ProviderErrorPresentation?)]
    let onOpenPreferences: (String) -> Void
    /// Esconde o provedor da linha do popover (menu de contexto "Ocultar do menu").
    let onHide: (String) -> Void

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
                .contextMenu {
                    Button(L("Ocultar do menu")) { onHide(entry.provider.id) }
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
        switch ProviderPresentationPolicy.recoveryAction(for: kind) {
        case .reconnect: return L("Reconectar")
        case .configure: return L("Configurar")
        case nil: return nil
        }
    }

    private func color(for kind: ProviderErrorPresentation?) -> Color {
        switch kind {
        case .notConfigured: return .secondary
        case .needsReauth: return Theme.Brand.heatOrange
        case .dependencyUnavailable: return .secondary
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
