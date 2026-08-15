// Sources/OkTally/UI/DesignSystem/Components.swift
import SwiftUI

/// Card padrão: substitui as seis cópias do mesmo fundo+borda.
struct DashboardCard<Content: View>: View {
    var padding: CGFloat = Theme.Space.lg
    /// Mesma escotilha do `StatTile.fillsHeight`, e pelo mesmo motivo: um
    /// `.frame(maxHeight: .infinity)` aplicado por fora cresce o frame mas não o
    /// `.background`, que já foi desenhado no tamanho ideal — o card fica pequeno dentro
    /// de uma caixa grande. Grades e colunas de bento ligam isto para todos os cards de
    /// uma linha terminarem na mesma altura, ancorados no topo.
    var fillsHeight: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(Theme.surface()))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).strokeBorder(Theme.border()))
    }
}

/// Métrica com hierarquia: `.hero` é o bloco tingido e grande, `.regular` orbita.
struct StatTile: View {
    enum Emphasis { case regular, hero }

    let title: String
    let value: String
    var caption: String?
    var tint: Color = .accentColor
    var emphasis: Emphasis = .regular
    /// Faz o tile ocupar toda a altura oferecida, com o conteúdo ancorado no topo. É
    /// preciso ser opção interna: um `.frame(maxHeight: .infinity)` aplicado por fora
    /// cresce o frame mas não o `.background`, que já foi desenhado no tamanho ideal —
    /// o card fica pequeno dentro de uma caixa grande. Colunas de bento usam isto para
    /// terminar na mesma linha que o card vizinho.
    var fillsHeight: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title)
            Text(value)
                .font(emphasis == .hero ? Theme.Font.metricHero : Theme.Font.metricLarge)
                .monospacedDigit()
                .foregroundStyle(emphasis == .hero ? tint : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let caption {
                Text(caption)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(Theme.Space.lg)
        .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
        .background {
            let shape = RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
            switch emphasis {
            case .hero: shape.fill(Theme.surfaceAccent(tint))
            case .regular: shape.fill(Theme.surface())
            }
        }
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).strokeBorder(Theme.border()))
    }
}

/// O rótulo maiúsculo com tracking, hoje repetido em quatro telas.
struct SectionHeader: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(Theme.Font.label)
            .tracking(0.5)
            .foregroundStyle(.secondary)
    }
}

/// Variação percentual. `nil` (sem base de comparação) some em vez de mostrar "+∞".
struct DeltaBadge: View {
    let fraction: Double?

    var body: some View {
        if let fraction {
            let up = fraction >= 0
            let tint: Color = abs(fraction) < 0.005 ? .secondary : (up ? .green : .red)
            Label(
                String(format: "%@%.0f%%", up ? "+" : "−", abs(fraction) * 100),
                systemImage: up ? "arrow.up.right" : "arrow.down.right"
            )
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.14)))
        }
    }
}

/// Fatia de participação de um provider.
struct ShareBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(color.gradient)
                    .frame(width: max(3, geo.size.width * Theme.clampFraction(fraction)))
            }
        }
        .frame(height: 6)
    }
}

/// Anel reaproveitável (streak, cota).
struct ProgressRing: View {
    let fraction: Double
    let color: Color
    var lineWidth: CGFloat = 6
    var size: CGFloat = 44
    var label: String?

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: Theme.clampFraction(fraction))
                .stroke(color.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: fraction)
            if let label {
                Text(label)
                    .font(.system(size: size * 0.3, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
            }
        }
        .frame(width: size, height: size)
    }
}
