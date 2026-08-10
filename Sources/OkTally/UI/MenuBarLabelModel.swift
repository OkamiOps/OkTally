// Sources/OkTally/UI/MenuBarLabelModel.swift
import Foundation

enum DangerLevel: Equatable { case ok, warn, critical, neutral }

struct MenuBarSegment: Equatable {
    let glyph: String?
    let providerId: String?
    let text: String
    let danger: DangerLevel
}

/// Pure computation of what the menu bar shows — kept out of the view/renderer so the
/// pin → segment rules are unit-testable. The bar shows *remaining* percent, matching
/// the dropdown's "X% restante" copy (the pre-redesign bar showed used percent).
enum MenuBarLabelModel {
    static func segments(pins: [AppModel.MenuBarPin], snapshots: [String: ProviderSnapshot], hasAnyError: Bool) -> [MenuBarSegment] {
        let pinned = pins.compactMap { pin -> MenuBarSegment? in
            guard let snapshot = snapshots[pin.providerId],
                  let window = snapshot.quotas.first(where: { $0.label == pin.windowLabel })
            else { return nil }
            return segment(providerId: pin.providerId, shape: window.shape)
        }
        if !pinned.isEmpty { return pinned }

        let remainings = snapshots.values
            .flatMap(\.quotas)
            .compactMap { QuotaPresentation.remainingFraction($0.shape) }
        guard let worst = remainings.min() else {
            return [MenuBarSegment(glyph: nil, providerId: nil,
                                   text: hasAnyError ? "!" : "OK", danger: .neutral)]
        }
        return [MenuBarSegment(glyph: nil, providerId: nil,
                               text: String(Int((worst * 100).rounded())), danger: danger(remaining: worst))]
    }

    /// Same thresholds as `QuotaPresentation.color(remaining:)`.
    static func danger(remaining: Double) -> DangerLevel {
        if remaining <= 0.10 { return .critical }
        if remaining <= 0.30 { return .warn }
        return .ok
    }

    private static func segment(providerId: String, shape: QuotaShape) -> MenuBarSegment {
        let glyph = ProviderPalette.glyph(forId: providerId)
        if let remaining = QuotaPresentation.remainingFraction(shape) {
            return MenuBarSegment(glyph: glyph, providerId: providerId,
                                  text: String(Int((remaining * 100).rounded())),
                                  danger: danger(remaining: remaining))
        }
        switch shape {
        case .creditBalance(let remaining, _):
            let value = NSDecimalNumber(decimal: remaining).doubleValue
            return MenuBarSegment(glyph: glyph, providerId: providerId,
                                  text: String(format: "%.1f$", value), danger: .neutral)
        case .meteredOnly(let cost):
            let value = NSDecimalNumber(decimal: cost).doubleValue
            return MenuBarSegment(glyph: glyph, providerId: providerId,
                                  text: String(format: "%.1f$", value), danger: .neutral)
        default:
            return MenuBarSegment(glyph: glyph, providerId: providerId, text: "–", danger: .neutral)
        }
    }
}
