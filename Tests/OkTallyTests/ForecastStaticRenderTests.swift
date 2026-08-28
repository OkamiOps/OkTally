import AppKit
import SwiftUI
import XCTest
@testable import OkTally

/// O `Chart` precisa passar pelo ciclo de layout do AppKit: `ImageRenderer` não dá a
/// mesma garantia para marcas e eixos do Swift Charts. Estes renders não abrem nem
/// ativam uma janela; a `NSWindow` existe apenas para hospedar a árvore offscreen antes
/// do `cacheDisplay(in:to:)`.
@MainActor
final class ForecastStaticRenderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func test_forecastChartRendersInBothSchemesAtNormalAndNarrowWidths() throws {
        let cases: [(name: String, scheme: ColorScheme, size: CGSize)] = [
            ("dark-normal", .dark, CGSize(width: 680, height: 280)),
            ("dark-narrow", .dark, CGSize(width: 320, height: 280)),
            ("light-normal", .light, CGSize(width: 680, height: 280)),
            ("light-narrow", .light, CGSize(width: 320, height: 280))
        ]

        for renderCase in cases {
            let bitmap = try render(scheme: renderCase.scheme, size: renderCase.size, name: renderCase.name)
            assertChartIsVisibleAndUnclipped(bitmap, named: renderCase.name)
        }
    }

    private var forecast: UsageForecast {
        let hour: TimeInterval = 3_600
        return UsageForecast(
            id: ForecastWindowID(providerId: "claude", windowLabel: "weekly"),
            cadence: .weekly,
            currentUsedPercent: 56,
            samples: [
                UsageHistoryPoint(date: now.addingTimeInterval(-24 * hour), usedPercent: 28),
                UsageHistoryPoint(date: now.addingTimeInterval(-18 * hour), usedPercent: 35),
                UsageHistoryPoint(date: now.addingTimeInterval(-12 * hour), usedPercent: 41),
                UsageHistoryPoint(date: now.addingTimeInterval(-6 * hour), usedPercent: 49),
                UsageHistoryPoint(date: now, usedPercent: 56)
            ],
            ratePerDay: 28,
            safeRatePerDay: 14,
            exhaustionAt: now.addingTimeInterval(16 * hour),
            resetAt: now.addingTimeInterval(24 * hour),
            gap: 8 * hour,
            state: .slowDown
        )
    }

    private func render(scheme: ColorScheme, size: CGSize, name: String) throws -> NSBitmapImageRep {
        let view = ZStack {
            Rectangle().fill(Theme.pageBackground)
            ForecastChartView(
                forecast: forecast,
                providerColor: ProviderPalette.color(for: forecast.id.providerId),
                now: now
            )
            .padding(Theme.Space.md)
        }
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, scheme)

        let host = NSHostingView(rootView: AnyView(view))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = host
        host.frame = window.contentView?.bounds ?? NSRect(origin: .zero, size: size)
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        window.display()

        // Dá ao Swift Charts um giro do run loop para concluir a árvore de marcas antes
        // de congelar o bitmap. A janela continua fora da tela o tempo todo.
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds), "sem bitmap para \(name)")
        host.cacheDisplay(in: host.bounds, to: bitmap)

        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]), "falha ao codificar \(name)")
        let artifactURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OkTally-ForecastChart-\(name).png")
        try png.write(to: artifactURL, options: .atomic)
        print("forecast chart render: \(artifactURL.path)")

        return bitmap
    }

    private func assertChartIsVisibleAndUnclipped(_ bitmap: NSBitmapImageRep, named name: String) {
        XCTAssertGreaterThan(bitmap.pixelsWide, 0, "\(name): bitmap sem largura")
        XCTAssertGreaterThan(bitmap.pixelsHigh, 0, "\(name): bitmap sem altura")

        guard let background = bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB) else {
            return XCTFail("\(name): não foi possível ler o fundo")
        }

        var inkCount = 0
        var bounds: NSRect?
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let differsFromBackground = max(
                    abs(pixel.redComponent - background.redComponent),
                    abs(pixel.greenComponent - background.greenComponent),
                    abs(pixel.blueComponent - background.blueComponent)
                ) > 0.05
                guard differsFromBackground else { continue }

                inkCount += 1
                let point = NSRect(x: x, y: y, width: 1, height: 1)
                bounds = bounds.map { $0.union(point) } ?? point
            }
        }

        XCTAssertGreaterThan(inkCount, 300, "\(name): o gráfico não desenhou pixels suficientes")
        guard let bounds else { return }

        XCTAssertGreaterThan(bounds.width, CGFloat(bitmap.pixelsWide) * 0.35, "\(name): gráfico estreito demais")
        XCTAssertGreaterThan(bounds.height, CGFloat(bitmap.pixelsHigh) * 0.25, "\(name): gráfico baixo demais")
        XCTAssertGreaterThan(bounds.minX, 1, "\(name): conteúdo cortado à esquerda")
        XCTAssertGreaterThan(bounds.minY, 1, "\(name): conteúdo cortado na base")
        XCTAssertLessThan(bounds.maxX, CGFloat(bitmap.pixelsWide - 1), "\(name): conteúdo cortado à direita")
        XCTAssertLessThan(bounds.maxY, CGFloat(bitmap.pixelsHigh - 1), "\(name): conteúdo cortado no topo")

        let cyan = NSColor(Theme.accent).usingColorSpace(.sRGB) ?? .cyan
        let provider = NSColor(ProviderPalette.color(for: forecast.id.providerId)).usingColorSpace(.sRGB) ?? .orange
        XCTAssertGreaterThan(
            pixelCount(in: bitmap, near: cyan),
            8,
            "\(name): histórico/projeção em ciano ausente"
        )
        XCTAssertGreaterThan(
            pixelCount(in: bitmap, near: provider),
            8,
            "\(name): ritmo seguro na cor do provider ausente"
        )
    }

    private func pixelCount(in bitmap: NSBitmapImageRep, near target: NSColor) -> Int {
        var count = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let distance = max(
                    abs(pixel.redComponent - target.redComponent),
                    abs(pixel.greenComponent - target.greenComponent),
                    abs(pixel.blueComponent - target.blueComponent)
                )
                if distance < 0.18 { count += 1 }
            }
        }
        return count
    }
}
