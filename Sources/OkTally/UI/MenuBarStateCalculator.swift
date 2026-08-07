// Sources/OkTally/UI/MenuBarStateCalculator.swift
import Foundation

struct MenuBarState: Equatable {
    let percent: Double?
    let hasError: Bool
}

enum MenuBarStateCalculator {
    static func worstState(snapshots: [ProviderSnapshot], hasAnyError: Bool) -> MenuBarState {
        let percents = snapshots.flatMap { $0.quotas.compactMap { $0.shape.usedPercent } }
        return MenuBarState(percent: percents.max(), hasError: hasAnyError)
    }

    static func colorName(for state: MenuBarState) -> String {
        guard let percent = state.percent else { return state.hasError ? "gray" : "green" }
        if percent >= 90 { return "red" }
        if percent >= 70 { return "yellow" }
        return "green"
    }

    static func labelText(for state: MenuBarState) -> String {
        guard let percent = state.percent else { return state.hasError ? "!" : "OK" }
        return "\(Int(percent.rounded()))%"
    }
}
