// Sources/OkTally/UI/PopoverView.swift
import SwiftUI

struct PopoverView: View {
    @ObservedObject var appModel: AppModel

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
        HStack {
            Text("OkTally").font(.system(size: 14, weight: .bold))
            Spacer()
            Text(pinnedHint).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var pinnedHint: String {
        let count = appModel.menuBarPins.count
        switch count {
        case 0: return "Barra: automático"
        case 1: return "Barra: 1 fixado"
        default: return "Barra: \(count) fixados"
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button("Atualizar") { Task { await appModel.refreshNow() } }
            Spacer()
            if #available(macOS 14.0, *) {
                SettingsLink { Text("Preferências") }
                    .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
            } else {
                Button("Preferências") {
                    NSApp.activate(ignoringOtherApps: true)
                    DispatchQueue.main.async { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) }
                }
            }
            Button("Sair") { NSApplication.shared.terminate(nil) }
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
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
                return (provider, "Carregando…", nil)
            }
            if appModel.snapshotsByProvider[provider.id]?.quotas.isEmpty == true {
                return (provider, "Sem dados de cota", nil)
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

    var body: some View {
        VStack(spacing: 10) {
            if let hero {
                HeroCard(
                    provider: hero.provider,
                    window: hero.window,
                    remaining: hero.remaining,
                    isPinned: appModel.isPinned(providerId: hero.provider.id, windowLabel: hero.window.label),
                    onPin: { appModel.togglePin(providerId: hero.provider.id, windowLabel: hero.window.label) }
                )
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                      spacing: 10) {
                ForEach(withData, id: \.provider.id) { entry in
                    ProviderGaugeCard(
                        provider: entry.provider,
                        snapshot: entry.snapshot,
                        isPinned: { appModel.isPinned(providerId: entry.provider.id, windowLabel: $0) },
                        onPin: { appModel.togglePin(providerId: entry.provider.id, windowLabel: $0) }
                    )
                }
            }
            if !problems.isEmpty {
                ProblemsSection(problems: problems)
            }
        }
        .padding(12)
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
        .help(window.shape.isEstimated ? "Estimativa local, não confirmada pelo provedor" : "")
    }
}

// MARK: - Provider card

private struct ProviderGaugeCard: View {
    let provider: UsageProvider
    let snapshot: ProviderSnapshot
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
                            .foregroundStyle(QuotaPresentation.color(remaining: worst.remaining))
                    }
                } else if let balance = snapshot.quotas.first {
                    Text(QuotaPresentation.remainingText(balance.shape))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
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
            if let staleness = Self.stalenessText(fetchedAt: snapshot.fetchedAt) {
                Label(staleness, systemImage: "clock")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .help("Última atualização bem-sucedida — a busca mais recente falhou ou ainda não rodou")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.07)))
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
        return "Atualizado há \(s)"
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
                    .foregroundStyle(remaining != nil ? QuotaPresentation.color(remaining: remaining) : .primary)
                    .lineLimit(1)
                if let reset = QuotaPresentation.resetText(window.shape) {
                    Text(reset).font(.system(size: 9)).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
        }
        .help(window.shape.isEstimated ? "Estimativa local, não confirmada pelo provedor" : "")
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
        .help(isPinned ? "Remover da barra de menu" : "Fixar esta janela na barra de menu")
    }
}

// MARK: - Problems

private struct ProblemsSection: View {
    let problems: [(provider: UsageProvider, message: String, kind: ProviderErrorPresentation?)]

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
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.03)))
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
