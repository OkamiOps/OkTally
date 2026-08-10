// Tests/OkTallyTests/ReadmeAssetRenderer.swift
//
// Not a test of behavior: renders the real SwiftUI views with demo data into
// docs/assets/*.png for the README. Runs only when RENDER_README_ASSETS=1 so the
// normal suite stays fast:
//
//   RENDER_README_ASSETS=1 swift test --filter ReadmeAssetRenderer
//
import XCTest
import SwiftUI
@testable import OkTally

@MainActor
final class ReadmeAssetRenderer: XCTestCase {
    private var assetsDir: URL {
        // Tests run from the package root.
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/assets")
    }

    func test_renderReadmeAssets() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RENDER_README_ASSETS"] == "1")
        try FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)

        let model = try await demoModel()
        try write(view: PopoverContentView(appModel: model)
                    .frame(width: 360)
                    .background(Color(nsColor: .windowBackgroundColor)),
                  to: "popover.png")
        try write(view: menuBarStrip(model), to: "menubar.png")
    }

    // MARK: - Demo data (fictitious but realistic)

    private func demoModel() async throws -> AppModel {
        let now = Date()
        func rolling(_ usedPercent: Double, hours: Double) -> QuotaShape {
            .rollingWindow(used: usedPercent, limit: 100, windowStart: now,
                           resetAt: now.addingTimeInterval(hours * 3600))
        }

        let registry = PluginRegistry()
        let entries: [(String, String, [QuotaWindow])] = [
            ("claude", "Claude Code", [
                QuotaWindow(label: "5h", shape: rolling(22, hours: 2.7)),
                QuotaWindow(label: "weekly", shape: rolling(53, hours: 41))
            ]),
            ("codex", "Codex", [
                QuotaWindow(label: "semanal", shape: rolling(14, hours: 126)),
                QuotaWindow(label: "GPT-5.3-Codex-Spark (semanal)", shape: rolling(0, hours: 168))
            ]),
            ("openrouter", "OpenRouter", [
                QuotaWindow(label: "balance", shape: .creditBalance(remaining: Decimal(19.82), currency: "USD"))
            ]),
            ("minimax", "MiniMax", [
                QuotaWindow(label: "5h", shape: rolling(1, hours: 0.1)),
                QuotaWindow(label: "weekly", shape: rolling(1, hours: 0.1))
            ]),
            ("cursor", "Cursor", [
                QuotaWindow(label: "percent", shape: rolling(74, hours: 15.4))
            ]),
            ("mimo", "MiMo", [
                QuotaWindow(label: "mensal", shape: rolling(6, hours: 500))
            ])
        ]
        for (id, name, quotas) in entries {
            let provider = FakeUsageProvider(id: id, displayName: name)
            provider.snapshotToReturn = ProviderSnapshot(providerId: id, fetchedAt: now, quotas: quotas, usageDetail: nil)
            registry.register(provider)
        }

        let defaults = UserDefaults(suiteName: "ReadmeAssetRenderer")!
        defaults.removePersistentDomain(forName: "ReadmeAssetRenderer")
        let scheduler = Scheduler(
            registry: registry,
            storage: FakeStorage(),
            alertEngine: AlertEngine(),
            alertDispatcher: AlertDispatcher(sender: FakeNotificationSender())
        )
        let model = AppModel(registry: registry, scheduler: scheduler, defaults: defaults)
        await model.refreshNow()
        try await Task.sleep(nanoseconds: 200_000_000) // let onResult callbacks land
        model.menuBarPins = [
            .init(providerId: "claude", windowLabel: "5h"),
            .init(providerId: "codex", windowLabel: "semanal"),
            .init(providerId: "cursor", windowLabel: "percent")
        ]
        return model
    }

    /// The menu bar label on a dark menu-bar-like strip.
    private func menuBarStrip(_ model: AppModel) -> some View {
        MenuBarLabelView(segments: model.menuBarSegments)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.12)))
            .padding(8)
    }

    // MARK: - Rendering

    private func write<V: View>(view: V, to filename: String) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("failed to render \(filename)")
            return
        }
        let url = assetsDir.appendingPathComponent(filename)
        try png.write(to: url)
        print("wrote \(url.path)")
    }
}
