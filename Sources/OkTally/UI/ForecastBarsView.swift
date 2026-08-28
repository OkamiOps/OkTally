// Sources/OkTally/UI/ForecastBarsView.swift
import Foundation
import SwiftUI

/// Pure display model for the compact, shared-scale forecast card. It deliberately owns
/// copy and fractions only: the forecast engine remains the sole source of the pace
/// calculation, and the view never infers a date that the engine did not provide.
struct UsageForecastPresentation: Equatable {
    let forecast: UsageForecast
    let now: Date

    init(forecast: UsageForecast, now: Date = Date()) {
        self.forecast = forecast
        self.now = now
    }

    var isUnavailable: Bool {
        if case .unavailable = forecast.state { return true }
        return false
    }

    var showsTimeline: Bool {
        guard let resetAt = forecast.resetAt, resetAt > now else { return false }
        switch forecast.state {
        case .slowDown, .onPace, .canAccelerate, .noExhaustion:
            return true
        case .collecting, .unavailable:
            return false
        }
    }

    /// Fraction of the shared timeline occupied by the current consumption pace.
    /// A mature low-consumption series fills the rail: it reaches the renewal without an
    /// invented exhaustion date.
    var paceFraction: Double {
        guard showsTimeline else { return 0 }
        guard let exhaustionAt = forecast.exhaustionAt else { return 1 }
        return fraction(until: exhaustionAt)
    }

    /// Fraction of the shared timeline occupied by the provider's actual renewal.
    var renewalFraction: Double {
        guard showsTimeline, let resetAt = forecast.resetAt else { return 0 }
        return fraction(until: resetAt)
    }

    /// Neutral collection progress. Both minimums must advance, so having six immediate
    /// polls cannot make a card appear ready before the three-hour observation minimum.
    var collectionProgress: Double? {
        guard case let .collecting(observedHours, sampleCount) = forecast.state else { return nil }
        let timeProgress = Theme.clampFraction(observedHours / 3)
        let sampleProgress = Theme.clampFraction(Double(sampleCount) / 6)
        return min(timeProgress, sampleProgress)
    }

    var remainingFraction: Double {
        Theme.clampFraction((100 - forecast.currentUsedPercent) / 100)
    }

    var remainingPercentText: String {
        LF("%d%%", Int((remainingFraction * 100).rounded()))
    }

    var windowLabel: String {
        WindowLabelCatalog.displayLabel(forecast.id.windowLabel)
    }

    var headline: String {
        switch forecast.state {
        case .slowDown:
            guard let gap = forecast.gap else {
                return L("Desacelere · pode acabar antes da renovação")
            }
            return LF("Desacelere · pode acabar %@ antes", Self.durationText(abs(gap)))
        case .onPace:
            return L("No ritmo certo · chega perto da renovação")
        case .canAccelerate:
            guard let gap = forecast.gap else {
                return L("Pode acelerar · chega depois da renovação")
            }
            return LF("Pode acelerar · chega com %@ de folga", Self.durationText(abs(gap)))
        case .noExhaustion:
            return L("Pode acelerar · sem esgotamento previsto neste ritmo")
        case let .collecting(observedHours, _):
            return LF("Coletando ritmo · %@ de histórico", Self.durationText(max(0, observedHours) * 3_600))
        case .unavailable:
            return L("Previsão indisponível para esta janela")
        }
    }

    var paceDuration: String? {
        guard showsTimeline else { return nil }
        guard let exhaustionAt = forecast.exhaustionAt else { return L("Chega à renovação") }
        return Self.durationText(max(0, exhaustionAt.timeIntervalSince(now)))
    }

    var renewalDuration: String? {
        guard showsTimeline, let resetAt = forecast.resetAt else { return nil }
        return Self.durationText(max(0, resetAt.timeIntervalSince(now)))
    }

    var rateSummary: String? {
        guard let ratePerDay = forecast.ratePerDay,
              let safeRatePerDay = forecast.safeRatePerDay,
              ratePerDay.isFinite,
              safeRatePerDay.isFinite else {
            return nil
        }
        return LF(
            "Ritmo 24h: %@%%/dia · Seguro: até %@%%/dia",
            Self.decimal(ratePerDay),
            Self.decimal(safeRatePerDay)
        )
    }

    private func fraction(until event: Date) -> Double {
        guard let resetAt = forecast.resetAt else { return 0 }
        let horizon = max(resetAt, forecast.exhaustionAt ?? resetAt)
        let total = horizon.timeIntervalSince(now)
        guard total.isFinite, total > 0 else { return 0 }
        return Theme.clampFraction(event.timeIntervalSince(now) / total)
    }

    static func durationText(_ interval: TimeInterval) -> String {
        guard interval.isFinite else { return L("agora") }
        let totalMinutes = max(0, Int((interval / 60).rounded(.down)))
        guard totalMinutes > 0 else { return L("agora") }

        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60

        if days > 0, hours > 0 { return LF("%dd %dh", days, hours) }
        if days > 0, minutes > 0 { return LF("%dd %dmin", days, minutes) }
        if days > 0 { return LF("%dd", days) }
        if hours > 0, minutes > 0 { return LF("%dh %dmin", hours, minutes) }
        if hours > 0 { return LF("%dh", hours) }
        return LF("%dmin", minutes)
    }

    static func decimal(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

/// Compact forecast card for use in the popover. `showUnavailable` is an explicit policy
/// supplied by the caller: automatic selection omits unavailable forecasts, while a
/// manually selected window can retain a neutral explanation without fabricated values.
struct ForecastBarsView: View {
    let providerId: String
    let providerName: String
    let forecast: UsageForecast
    let now: Date
    let showUnavailable: Bool

    init(
        providerId: String,
        providerName: String,
        forecast: UsageForecast,
        now: Date = Date(),
        showUnavailable: Bool = false
    ) {
        self.providerId = providerId
        self.providerName = providerName
        self.forecast = forecast
        self.now = now
        self.showUnavailable = showUnavailable
    }

    private var presentation: UsageForecastPresentation {
        UsageForecastPresentation(forecast: forecast, now: now)
    }

    var body: some View {
        Group {
            if !presentation.isUnavailable || showUnavailable {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    header

                    if presentation.isUnavailable {
                        Text(presentation.headline)
                            .font(Theme.Font.body)
                            .foregroundStyle(.secondary)
                    } else if let collectionProgress = presentation.collectionProgress {
                        collection(progress: collectionProgress)
                    } else if presentation.showsTimeline {
                        timeline
                    }
                }
                .padding(Theme.Space.md)
                .cardSurface()
            }
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Space.sm) {
            IconChip(
                glyph: ProviderPalette.glyph(forId: providerId),
                color: ProviderPalette.color(for: providerId),
                size: 22
            )
            Text(LF("%@ · %@", providerName, presentation.windowLabel))
                .font(Theme.Font.body.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: Theme.Space.sm)
            if !presentation.isUnavailable {
                Text(presentation.remainingPercentText)
                    .font(Theme.Font.metricMedium)
                    .foregroundStyle(QuotaPresentation.valueStyle(remaining: presentation.remainingFraction))
            }
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(presentation.headline)
                .font(Theme.Font.body.weight(.semibold))
                .foregroundStyle(.primary)

            ForecastTimelineRow(
                title: L("Seu ritmo"),
                fraction: presentation.paceFraction,
                duration: presentation.paceDuration ?? L("agora"),
                color: QuotaPresentation.color(remaining: presentation.remainingFraction)
            )
            ForecastTimelineRow(
                title: L("Renovação"),
                fraction: presentation.renewalFraction,
                duration: presentation.renewalDuration ?? L("agora"),
                color: ProviderPalette.color(for: providerId)
            )

            if let rateSummary = presentation.rateSummary {
                Text(rateSummary)
                    .font(Theme.Font.label)
                    .foregroundStyle(.secondary)
                    .padding(.top, Theme.Space.xs)
            }
        }
    }

    private func collection(progress: Double) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(presentation.headline)
                .font(Theme.Font.body.weight(.semibold))
                .foregroundStyle(.secondary)
            ProgressView(value: progress)
                .tint(.secondary)
                .accessibilityLabel(L("Coletando ritmo"))
        }
    }
}

/// Dense per-window pace shown inside the provider ledger. The expanded card above still
/// explains the highest-risk target; this strip makes every other renewable model
/// independently scannable without duplicating a full card for each one.
struct ForecastInlinePaceView: View {
    let providerId: String
    let forecast: UsageForecast
    let now: Date
    var onHero: Bool = false

    init(
        providerId: String,
        forecast: UsageForecast,
        now: Date = Date(),
        onHero: Bool = false
    ) {
        self.providerId = providerId
        self.forecast = forecast
        self.now = now
        self.onHero = onHero
    }

    private var presentation: UsageForecastPresentation {
        UsageForecastPresentation(forecast: forecast, now: now)
    }

    private var textStyle: AnyShapeStyle {
        onHero ? AnyShapeStyle(Theme.onHero.opacity(0.82)) : AnyShapeStyle(HierarchicalShapeStyle.secondary)
    }

    private var backgroundStyle: AnyShapeStyle {
        onHero
            ? AnyShapeStyle(Color.black.opacity(0.16))
            : AnyShapeStyle(Theme.track().opacity(0.55))
    }

    @ViewBuilder var body: some View {
        if !presentation.isUnavailable {
            VStack(alignment: .leading, spacing: 5) {
                Text(presentation.headline)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(textStyle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                if let collectionProgress = presentation.collectionProgress {
                    ProgressView(value: collectionProgress)
                        .tint(onHero ? Theme.onHero.opacity(0.75) : .secondary)
                        .accessibilityLabel(L("Coletando ritmo"))
                } else if presentation.showsTimeline {
                    ForecastTimelineRow(
                        title: L("Seu ritmo"),
                        fraction: presentation.paceFraction,
                        duration: presentation.paceDuration ?? L("agora"),
                        color: QuotaPresentation.color(remaining: presentation.remainingFraction),
                        compact: true,
                        onHero: onHero
                    )
                    ForecastTimelineRow(
                        title: L("Renovação"),
                        fraction: presentation.renewalFraction,
                        duration: presentation.renewalDuration ?? L("agora"),
                        color: ProviderPalette.color(for: providerId),
                        compact: true,
                        onHero: onHero
                    )
                    if let rateSummary = presentation.rateSummary {
                        Text(rateSummary)
                            .font(.system(size: 10))
                            .foregroundStyle(textStyle)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(backgroundStyle)
            )
            .accessibilityElement(children: .contain)
        }
    }
}

private struct ForecastTimelineRow: View {
    let title: String
    let fraction: Double
    let duration: String
    let color: Color
    var compact: Bool = false
    var onHero: Bool = false

    private var trackStyle: AnyShapeStyle {
        onHero
            ? AnyShapeStyle(Color.black.opacity(0.24))
            : AnyShapeStyle(Theme.track())
    }

    var body: some View {
        HStack(spacing: compact ? 7 : Theme.Space.sm) {
            Text(title)
                .font(compact ? .system(size: 10, weight: .medium) : Theme.Font.label)
                .foregroundStyle(onHero ? Theme.onHero.opacity(0.72) : .secondary)
                .frame(width: compact ? 58 : 62, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(trackStyle)
                    Capsule()
                        .fill(color)
                        .frame(width: max(2, geometry.size.width * Theme.clampFraction(fraction)))
                }
            }
            .frame(height: 6)
            .accessibilityValue(duration)

            Text(duration)
                .font((compact ? Font.system(size: 10) : Theme.Font.label).monospacedDigit())
                .foregroundStyle(onHero ? Theme.onHero.opacity(0.72) : .secondary)
                .frame(width: compact ? 62 : 48, alignment: .trailing)
        }
    }
}
