// Sources/OkTally/UI/ProviderPalette.swift
import SwiftUI

/// A distinct identity color per provider so rows are told apart at a glance (the quota
/// bar's own color still encodes danger: green/amber/red by how much remains).
enum ProviderPalette {
    /// Roda de matizes espalhada de propósito: as referências que guiaram o redesenho
    /// são categóricas e multicoloridas, não monocromáticas. As cores foram
    /// harmonizadas com a marca (ancoradas em Volt Cyan / Heat Orange / Neon Magenta) e
    /// subiram de saturação e luminosidade — as antigas eram pastéis de tema claro e
    /// desapareciam contra a base quase preta. Cada par vizinho mantém pelo menos ~20°
    /// de distância de matiz para continuarem distinguíveis entre si.
    static func color(for providerId: String) -> Color {
        switch providerId {
        case "claude":      return Color(hex: 0xFF6A3D) // terracota, vizinho do Heat Orange
        case "mimo":        return Color(hex: 0xFFB020) // âmbar
        case "codex":       return Color(hex: 0x00D69B) // verde-azulado
        case "openrouter":  return Color(hex: 0x00B8F5) // Volt Cyan da marca
        case "antigravity": return Color(hex: 0x3D8BFF) // azul
        case "copilot":     return Color(hex: 0x5B7CFA) // índigo
        case "supergrok":   return Color(hex: 0x9B5CF6) // violeta-azulado
        case "opencode":    return Color(hex: 0xC94DFF) // violeta
        case "minimax":     return Color(hex: 0xFF3D8F) // vizinho do Neon Magenta
        // Cursor era o neutro grafite da roda. Só que ele é justamente quem costuma estar
        // mais apertado (e portanto quem aparece no bloco de destaque), e um cinza no
        // lugar mais visível da tela desmontava a paleta categórica inteira. Lima fecha o
        // único setor vago da roda, entre o âmbar do MiMo e o verde-azulado do Codex.
        case "cursor":      return Color(hex: 0x8FD14F) // lima
        default:            return Theme.accent
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
        case "antigravity": return "A"
        default: return "?"
        }
    }
}
