// Sources/OkTally/UI/PopoverView.swift
import SwiftUI

struct PopoverView: View {
    @ObservedObject var appModel: AppModel

    private var providers: [UsageProvider] { appModel.orderedProviders }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(providers.enumerated()), id: \.element.id) { index, provider in
                        ProviderRow(
                            provider: provider,
                            snapshot: appModel.snapshotsByProvider[provider.id],
                            errorMessage: appModel.errorsByProvider[provider.id],
                            errorKind: appModel.errorKindByProvider[provider.id],
                            pin: appModel.menuBarPin,
                            onPinWindow: { label in appModel.togglePin(providerId: provider.id, windowLabel: label) }
                        )
                        if index < providers.count - 1 {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(height: 460)
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
        if let pin = appModel.menuBarPin, let p = providers.first(where: { $0.id == pin.providerId }) {
            return "Barra: \(p.displayName) · \(pin.windowLabel)"
        }
        return "Barra: automático"
    }

    private var activeCount: Int {
        providers.filter { appModel.snapshotsByProvider[$0.id]?.quotas.isEmpty == false }.count
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

/// One provider, always visible: identity chip + name on the left, its quota windows stacked
/// on the right as compact bars. No selection — everything is on screen at once.
struct ProviderRow: View {
    let provider: UsageProvider
    let snapshot: ProviderSnapshot?
    let errorMessage: String?
    let errorKind: ProviderErrorPresentation?
    var pin: AppModel.MenuBarPin? = nil
    var onPinWindow: (String) -> Void = { _ in }

    private var identity: Color { ProviderPalette.color(for: provider.id) }
    private var isProviderPinned: Bool { pin?.providerId == provider.id }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            chip
            VStack(alignment: .leading, spacing: 8) {
                Text(provider.displayName)
                    .font(.system(size: 13, weight: .semibold))
                content
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isProviderPinned ? identity.opacity(0.06) : .clear)
    }

    private var chip: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7).fill(identity.opacity(0.16)).frame(width: 26, height: 26)
            Text(ProviderPalette.glyph(for: provider))
                .font(.system(size: 13, weight: .bold)).foregroundStyle(identity)
        }
        .padding(.top, 1)
    }

    @ViewBuilder private var content: some View {
        if let errorMessage {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(errorColor)
                .fixedSize(horizontal: false, vertical: true)
        } else if let snapshot, !snapshot.quotas.isEmpty {
            ForEach(snapshot.quotas, id: \.label) { window in
                CompactQuotaBar(
                    window: window,
                    identity: identity,
                    isPinned: pin?.providerId == provider.id && pin?.windowLabel == window.label,
                    onPin: { onPinWindow(window.label) }
                )
            }
        } else if snapshot != nil {
            Text("Sem dados de cota").font(.caption).foregroundStyle(.tertiary)
        } else {
            Text("Carregando…").font(.caption).foregroundStyle(.tertiary)
        }
    }

    private var errorColor: Color {
        switch errorKind {
        case .notConfigured: return .secondary
        case .needsReauth: return .orange
        default: return .red
        }
    }
}

/// Compact single-line quota: label + reset on top, thin bar with the remaining % inline.
struct CompactQuotaBar: View {
    let window: QuotaWindow
    let identity: Color
    var isPinned: Bool = false
    var onPin: () -> Void = {}

    var body: some View {
        let remaining = QuotaPresentation.remainingFraction(window.shape)
        let danger = QuotaPresentation.color(remaining: remaining)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Button(action: onPin) {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 9))
                        .foregroundStyle(isPinned ? identity : Color.secondary.opacity(0.45))
                }
                .buttonStyle(.plain)
                .help(isPinned ? "Fixado na barra de menu" : "Fixar esta janela na barra de menu")
                Text(window.label)
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(QuotaPresentation.remainingText(window.shape))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(remaining != nil ? danger : .primary)
                if let reset = QuotaPresentation.resetText(window.shape) {
                    Text("· \(reset)").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
            if let remaining {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule().fill(barColor(remaining: remaining, danger: danger))
                            .frame(width: max(3, geo.size.width * remaining))
                    }
                }
                .frame(height: 5)
            }
        }
    }

    // Identity color while healthy, danger color when getting low — keeps rows distinct but
    // still flags trouble.
    private func barColor(remaining: Double, danger: Color) -> Color {
        remaining <= 0.30 ? danger : identity
    }
}
