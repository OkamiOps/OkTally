// Sources/OkTally/UI/ProviderPalette.swift
import SwiftUI

/// A distinct identity color per provider so rows are told apart at a glance (the quota
/// bar's own color still encodes danger: green/amber/red by how much remains).
enum ProviderPalette {
    static func color(for providerId: String) -> Color {
        switch providerId {
        case "claude":    return Color(red: 0.85, green: 0.47, blue: 0.30) // terracotta
        case "codex":     return Color(red: 0.20, green: 0.70, blue: 0.55) // teal-green
        case "supergrok": return Color(red: 0.40, green: 0.45, blue: 0.95) // indigo
        case "cursor":    return Color(red: 0.55, green: 0.55, blue: 0.60) // graphite
        case "openrouter":return Color(red: 0.35, green: 0.60, blue: 0.95) // blue
        case "minimax":   return Color(red: 0.90, green: 0.35, blue: 0.55) // pink
        case "opencode":  return Color(red: 0.60, green: 0.45, blue: 0.90) // violet
        case "mimo":      return Color(red: 0.95, green: 0.62, blue: 0.20) // amber
        case "copilot":   return Color(red: 0.45, green: 0.40, blue: 0.75) // slate-violet
        default:          return .accentColor
        }
    }

    /// One or two letters for the identity chip.
    static func glyph(for provider: UsageProvider) -> String {
        glyph(forId: provider.id)
    }

    /// Short distinct glyph per provider id (displayName initials collide:
    /// Claude/Codex/Cursor all start with "C").
    static func glyph(forId id: String) -> String {
        switch id {
        case "claude": return "C"
        case "codex": return "X"
        case "supergrok": return "G"
        case "cursor": return "▹"
        case "openrouter": return "O"
        case "minimax": return "M"
        case "opencode": return "◇"
        case "mimo": return "K"
        case "copilot": return "P"
        default: return "?"
        }
    }
}
