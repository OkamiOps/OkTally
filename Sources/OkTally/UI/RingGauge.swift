// Sources/OkTally/UI/RingGauge.swift
import SwiftUI

/// Circular remaining-fraction gauge. `remaining` is 0…1; the ring drains clockwise.
struct RingGauge<Content: View>: View {
    let remaining: Double
    let size: CGFloat
    let color: Color
    var lineWidth: CGFloat = 5
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, remaining)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                // Refreshes chegam de 5 em 5 min; sem isso o anel "pisca" para o novo
                // valor em vez de deslizar (padrão do Quotio: .smooth 0.3s).
                .animation(.easeInOut(duration: 0.3), value: remaining)
            content()
        }
        .frame(width: size, height: size)
    }
}
