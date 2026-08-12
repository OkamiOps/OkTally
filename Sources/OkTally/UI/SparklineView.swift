// Sources/OkTally/UI/SparklineView.swift
import SwiftUI

/// Minimal 24h trend line for a provider card: a normalized polyline with a soft fill
/// underneath. No axes/labels — the ring and quota lines above carry the numbers; this
/// only answers "subindo ou estável?" at a glance.
struct SparklineView: View {
    /// Used-percent values (0…100) in chronological order.
    let points: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let normalized = normalizedPoints(in: geo.size)
            if normalized.count >= 2 {
                ZStack {
                    fillPath(normalized, size: geo.size)
                        .fill(color.opacity(0.12))
                    linePath(normalized)
                        .stroke(color.opacity(0.75), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .frame(height: 20)
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard points.count >= 2, size.width > 0, size.height > 0 else { return [] }
        let stepX = size.width / CGFloat(points.count - 1)
        // Fixed 0…100 vertical scale so cards are comparable and a flat low line reads
        // as "quase nada usado" instead of being stretched to full height.
        return points.enumerated().map { index, value in
            let clamped = max(0, min(100, value))
            return CGPoint(x: CGFloat(index) * stepX, y: size.height * (1 - CGFloat(clamped / 100)))
        }
    }

    private func linePath(_ pts: [CGPoint]) -> Path {
        Path { path in
            path.move(to: pts[0])
            for p in pts.dropFirst() { path.addLine(to: p) }
        }
    }

    private func fillPath(_ pts: [CGPoint], size: CGSize) -> Path {
        Path { path in
            path.move(to: CGPoint(x: pts[0].x, y: size.height))
            for p in pts { path.addLine(to: p) }
            path.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: size.height))
            path.closeSubpath()
        }
    }
}
