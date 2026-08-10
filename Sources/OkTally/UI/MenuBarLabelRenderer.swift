// Sources/OkTally/UI/MenuBarLabelRenderer.swift
import SwiftUI
import AppKit

/// `MenuBarExtra` renders text labels as template (monochrome), discarding any
/// `foregroundStyle` — the only way color survives in the menu bar is a non-template
/// `NSImage`. This renders the segments to one.
enum MenuBarLabelRenderer {
    @MainActor
    static func image(for segments: [MenuBarSegment]) -> NSImage {
        let renderer = ImageRenderer(content: MenuBarLabelView(segments: segments))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return NSImage() }
        image.isTemplate = false
        return image
    }
}

struct MenuBarLabelView: View {
    let segments: [MenuBarSegment]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                HStack(spacing: 2) {
                    if let glyph = segment.glyph, let id = segment.providerId {
                        Text(glyph)
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundStyle(ProviderPalette.color(for: id))
                    }
                    Text(segment.text)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(color(for: segment.danger))
                }
            }
        }
        .padding(.horizontal, 1)
        .fixedSize()
    }

    // Explicit colors, not .primary: the image is rendered outside the menu bar's
    // appearance context, so semantic colors would bake in the app appearance and could
    // vanish against the opposite menu bar. Mid-gray is legible on both.
    private func color(for danger: DangerLevel) -> Color {
        switch danger {
        case .ok: return Color(red: 0.22, green: 0.78, blue: 0.42)
        case .warn: return .orange
        case .critical: return Color(red: 0.98, green: 0.26, blue: 0.27)
        case .neutral: return Color(white: 0.62)
        }
    }
}
