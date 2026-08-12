// Sources/OkTally/UI/WindowLabelCatalog.swift
import Foundation

/// Maps the raw window labels providers emit ("5h", "weekly", "balance", …) to friendly
/// Portuguese display names. DISPLAY-ONLY: raw labels are the persistence key for menu
/// bar pins (`AppModel.MenuBarPin.stored`) and the lookup key for alert thresholds, so
/// they must never be rewritten at the data layer — translate at the last moment, in the
/// view. (Pattern borrowed from Quotio's `displayName` switch over ~80 raw quota keys.)
enum WindowLabelCatalog {
    private static let table: [String: String] = [
        "5h": "Sessão 5h",
        "weekly": "Semanal",
        "weekly-opus": "Opus semanal",
        "semanal": "Semanal",
        "uso": "Uso",
        "balance": "Saldo",
        "percent": "Ciclo",
        "mensal": "Mensal",
        "monthly": "Mensal",
        "plano": "Plano",
        "chat": "Chat",
        "completions": "Autocomplete",
        "premium": "Premium",
    ]

    static func displayLabel(_ raw: String) -> String {
        if let mapped = table[raw] { return L(mapped) }
        // Codex emits dynamic labels like "GPT-5.3-Codex-Spark (weekly)" — keep the model
        // name, translate only the parenthesized window kind.
        if raw.hasSuffix(")"), let open = raw.lastIndex(of: "("), open > raw.startIndex {
            let inner = String(raw[raw.index(after: open)..<raw.index(before: raw.endIndex)])
            if let mapped = table[inner] {
                return "\(raw[..<open])(\(L(mapped)))"
            }
        }
        return raw
    }
}
