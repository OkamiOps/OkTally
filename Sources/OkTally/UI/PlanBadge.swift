// Sources/OkTally/UI/PlanBadge.swift
import SwiftUI

/// Cápsula compacta com o plano da conta ("Pro", "Free", "Business"…), na paleta do
/// Quotio: preenchimento a 12% da cor do tier.
struct PlanBadge: View {
    let label: String

    private var tint: Color {
        switch label.lowercased() {
        case "enterprise", "business": return .red
        case "pro", "pro+": return .purple
        case "plus", "team": return .blue
        case "free": return .secondary
        default: return .teal
        }
    }

    var body: some View {
        Text(label)
            .font(.system(size: 8, weight: .semibold, design: .rounded))
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .background(Capsule().fill(tint.opacity(0.12)))
            .foregroundStyle(tint)
            .lineLimit(1)
    }
}
