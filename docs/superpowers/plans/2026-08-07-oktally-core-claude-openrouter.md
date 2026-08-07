# OkTally Core + Claude + OpenRouter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the OkTally macOS menu bar app's core architecture (plugin protocol, scheduler, storage, alert engine, pricing engine, menu bar UI) plus the Claude Code and OpenRouter plugins — the two providers with confirmed usage-data endpoints — delivering a working app that solves the primary pain point (advance warning before Claude's 5h/weekly quota is exhausted).

**Architecture:** Swift Package Manager executable target using SwiftUI's `MenuBarExtra` scene for the menu bar shell, wrapped into a proper `.app` bundle via a build script (needed for notifications and `LSUIElement`). Core logic (data model, alert engine, pricing engine, storage, scheduler) is UI-independent and unit-tested with XCTest; plugins talk to real network/Keychain APIs behind protocols so they can be faked in tests.

**Tech Stack:** Swift 5.9+, macOS 13+ (Ventura), SwiftUI + AppKit, GRDB.swift (SQLite), XCTest, Swift Concurrency (async/await, actors).

## Global Constraints

- Platform: macOS 13.0+ only.
- Swift tools version: 5.9.
- No App Sandbox entitlement — needed for unrestricted cross-app Keychain reads (the OS shows a one-time consent prompt instead) and outbound network calls to undocumented endpoints.
- Storage is 100% local — no cloud sync, no telemetry.
- Every task ends with a commit; commit messages use the `feat:`/`test:`/`fix:` prefix convention.
- No third-party UI frameworks — SwiftUI + AppKit only. GRDB.swift is the only non-Apple dependency.

---

### Task 1: Project scaffolding + minimal menu bar shell

**Files:**
- Create: `Package.swift`
- Create: `Sources/OkTally/App/OkTallyApp.swift`
- Create: `Resources/Info.plist`
- Create: `Scripts/build_app.sh`
- Create: `Tests/OkTallyTests/PlaceholderTests.swift`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: a buildable SPM package named `OkTally` with an executable target `OkTally` and a test target `OkTallyTests`, and a runnable menu bar shell.

- [ ] **Step 1: Create the package manifest**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OkTally",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0")
    ],
    targets: [
        .executableTarget(
            name: "OkTally",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "OkTallyTests",
            dependencies: ["OkTally"],
            resources: [.copy("Fixtures")]
        )
    ]
)
```

- [ ] **Step 2: Create a placeholder fixtures directory so the test target resource path resolves**

```bash
mkdir -p Tests/OkTallyTests/Fixtures
touch Tests/OkTallyTests/Fixtures/.gitkeep
```

- [ ] **Step 3: Write a placeholder test so `swift test` has something to run**

```swift
// Tests/OkTallyTests/PlaceholderTests.swift
import XCTest

final class PlaceholderTests: XCTestCase {
    func test_packageBuilds() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 4: Run the test suite to confirm the package resolves and builds**

Run: `swift test`
Expected: `Test Suite 'All tests' passed` with 1 test executed.

- [ ] **Step 5: Write the minimal menu bar app**

```swift
// Sources/OkTally/App/OkTallyApp.swift
import SwiftUI

@main
struct OkTallyApp: App {
    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 8) {
                Text("OkTally")
                    .font(.headline)
                Divider()
                Button("Sair") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(12)
            .frame(width: 200)
        } label: {
            Text("OK")
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 6: Run `swift build` to confirm it compiles**

Run: `swift build`
Expected: build succeeds with no errors.

- [ ] **Step 7: Create the Info.plist for the app bundle**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>OkTally</string>
    <key>CFBundleIdentifier</key>
    <string>com.oktally.app</string>
    <key>CFBundleName</key>
    <string>OkTally</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Personal use.</string>
</dict>
</plist>
```

- [ ] **Step 8: Create the app bundle build script**

```bash
#!/bin/bash
# Scripts/build_app.sh
set -euo pipefail
swift build -c release
APP_NAME="OkTally"
BUILD_DIR=".build/release"
APP_BUNDLE=".build/${APP_NAME}.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP_BUNDLE/Contents/Info.plist"
codesign --force --deep --sign - "$APP_BUNDLE"
echo "Built $APP_BUNDLE"
```

```bash
chmod +x Scripts/build_app.sh
```

- [ ] **Step 9: Build the app bundle and verify manually**

Run: `./Scripts/build_app.sh`
Expected: `Built .build/OkTally.app` printed, no codesign errors.

Run: `open .build/OkTally.app`
Expected: no Dock icon appears (LSUIElement), a menu bar item reading "OK" appears in the menu bar. Click it — a popover with "OkTally" and a "Sair" button appears. Click "Sair" — the app quits and the menu bar item disappears.

- [ ] **Step 10: Commit**

```bash
git add Package.swift Sources/OkTally/App/OkTallyApp.swift Resources/Info.plist Scripts/build_app.sh Tests/OkTallyTests/PlaceholderTests.swift Tests/OkTallyTests/Fixtures/.gitkeep
git commit -m "feat: scaffold OkTally menu bar app shell"
```

---

### Task 2: Core data model

**Files:**
- Create: `Sources/OkTally/Core/QuotaShape.swift`
- Create: `Sources/OkTally/Core/ProviderSnapshot.swift`
- Create: `Sources/OkTally/Core/UsageProvider.swift`
- Test: `Tests/OkTallyTests/QuotaShapeTests.swift`

**Interfaces:**
- Consumes: nothing beyond Foundation.
- Produces: `QuotaShape` (enum, 4 cases: `.rollingWindow`, `.periodicCounter`, `.creditBalance`, `.meteredOnly`), `QuotaShape.usedPercent: Double?`, `QuotaShape.resetAt: Date?`, `QuotaWindow` (struct: `label: String`, `shape: QuotaShape`), `ProviderSnapshot` (struct: `providerId: String`, `fetchedAt: Date`, `quotas: [QuotaWindow]`, `usageDetail: [UsageDetail]?`), `UsageDetail` (struct: `modelId: String`, `promptTokens: Int`, `completionTokens: Int`), `UsageProvider` protocol (`id: String`, `displayName: String`, `authMethod: AuthMethod`, `refreshInterval: TimeInterval`, `isAuthenticated() async -> Bool`, `fetchSnapshot() async throws -> ProviderSnapshot`), `AuthMethod` enum (`.keychain(service: String)`, `.localFile(path: String)`, `.apiKey`, `.oauthSession`). All types used by every later task.

- [ ] **Step 1: Write the failing test for `QuotaShape.usedPercent` and `resetAt`**

```swift
// Tests/OkTallyTests/QuotaShapeTests.swift
import XCTest
@testable import OkTally

final class QuotaShapeTests: XCTestCase {
    func test_rollingWindow_usedPercent() {
        let start = Date()
        let reset = start.addingTimeInterval(3600)
        let shape = QuotaShape.rollingWindow(used: 42, limit: 100, windowStart: start, resetAt: reset)
        XCTAssertEqual(shape.usedPercent, 42)
        XCTAssertEqual(shape.resetAt, reset)
    }

    func test_periodicCounter_usedPercent() {
        let reset = Date()
        let shape = QuotaShape.periodicCounter(used: 30, limit: 60, resetAt: reset)
        XCTAssertEqual(shape.usedPercent, 50)
        XCTAssertEqual(shape.resetAt, reset)
    }

    func test_creditBalance_hasNoPercentOrReset() {
        let shape = QuotaShape.creditBalance(remaining: 12.5, currency: "USD")
        XCTAssertNil(shape.usedPercent)
        XCTAssertNil(shape.resetAt)
    }

    func test_meteredOnly_hasNoPercentOrReset() {
        let shape = QuotaShape.meteredOnly(costAccrued: 3.2)
        XCTAssertNil(shape.usedPercent)
        XCTAssertNil(shape.resetAt)
    }

    func test_rollingWindow_codableRoundTrip() throws {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let reset = Date(timeIntervalSince1970: 1_003_600)
        let original = QuotaShape.rollingWindow(used: 10, limit: 20, windowStart: start, resetAt: reset)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(QuotaShape.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_creditBalance_codableRoundTrip() throws {
        let original = QuotaShape.creditBalance(remaining: 7.75, currency: "USD")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(QuotaShape.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails to compile (types don't exist yet)**

Run: `swift test --filter QuotaShapeTests`
Expected: FAIL — `cannot find type 'QuotaShape' in scope`.

- [ ] **Step 3: Implement `QuotaShape`**

```swift
// Sources/OkTally/Core/QuotaShape.swift
import Foundation

enum QuotaShape: Equatable {
    case rollingWindow(used: Double, limit: Double, windowStart: Date, resetAt: Date)
    case periodicCounter(used: Double, limit: Double, resetAt: Date)
    case creditBalance(remaining: Decimal, currency: String)
    case meteredOnly(costAccrued: Decimal)

    var usedPercent: Double? {
        switch self {
        case .rollingWindow(let used, let limit, _, _):
            guard limit > 0 else { return nil }
            return min(used / limit, 1.0) * 100
        case .periodicCounter(let used, let limit, _):
            guard limit > 0 else { return nil }
            return min(used / limit, 1.0) * 100
        case .creditBalance, .meteredOnly:
            return nil
        }
    }

    var resetAt: Date? {
        switch self {
        case .rollingWindow(_, _, _, let resetAt): return resetAt
        case .periodicCounter(_, _, let resetAt): return resetAt
        case .creditBalance, .meteredOnly: return nil
        }
    }
}

extension QuotaShape: Codable {
    private enum Kind: String, Codable {
        case rollingWindow, periodicCounter, creditBalance, meteredOnly
    }

    private enum CodingKeys: String, CodingKey {
        case kind, used, limit, windowStart, resetAt, remaining, currency, costAccrued
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .rollingWindow:
            self = .rollingWindow(
                used: try container.decode(Double.self, forKey: .used),
                limit: try container.decode(Double.self, forKey: .limit),
                windowStart: try container.decode(Date.self, forKey: .windowStart),
                resetAt: try container.decode(Date.self, forKey: .resetAt)
            )
        case .periodicCounter:
            self = .periodicCounter(
                used: try container.decode(Double.self, forKey: .used),
                limit: try container.decode(Double.self, forKey: .limit),
                resetAt: try container.decode(Date.self, forKey: .resetAt)
            )
        case .creditBalance:
            self = .creditBalance(
                remaining: try container.decode(Decimal.self, forKey: .remaining),
                currency: try container.decode(String.self, forKey: .currency)
            )
        case .meteredOnly:
            self = .meteredOnly(costAccrued: try container.decode(Decimal.self, forKey: .costAccrued))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .rollingWindow(let used, let limit, let windowStart, let resetAt):
            try container.encode(Kind.rollingWindow, forKey: .kind)
            try container.encode(used, forKey: .used)
            try container.encode(limit, forKey: .limit)
            try container.encode(windowStart, forKey: .windowStart)
            try container.encode(resetAt, forKey: .resetAt)
        case .periodicCounter(let used, let limit, let resetAt):
            try container.encode(Kind.periodicCounter, forKey: .kind)
            try container.encode(used, forKey: .used)
            try container.encode(limit, forKey: .limit)
            try container.encode(resetAt, forKey: .resetAt)
        case .creditBalance(let remaining, let currency):
            try container.encode(Kind.creditBalance, forKey: .kind)
            try container.encode(remaining, forKey: .remaining)
            try container.encode(currency, forKey: .currency)
        case .meteredOnly(let costAccrued):
            try container.encode(Kind.meteredOnly, forKey: .kind)
            try container.encode(costAccrued, forKey: .costAccrued)
        }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter QuotaShapeTests`
Expected: PASS, 6 tests executed.

- [ ] **Step 5: Implement the remaining data model types (no dedicated tests — plain data holders exercised by later tasks)**

```swift
// Sources/OkTally/Core/ProviderSnapshot.swift
import Foundation

struct ProviderSnapshot: Codable, Equatable {
    let providerId: String
    let fetchedAt: Date
    let quotas: [QuotaWindow]
    let usageDetail: [UsageDetail]?
}

struct QuotaWindow: Codable, Equatable {
    let label: String
    let shape: QuotaShape
}

struct UsageDetail: Codable, Equatable {
    let modelId: String
    let promptTokens: Int
    let completionTokens: Int
}
```

```swift
// Sources/OkTally/Core/UsageProvider.swift
import Foundation

enum AuthMethod {
    case keychain(service: String)
    case localFile(path: String)
    case apiKey
    case oauthSession
}

protocol UsageProvider {
    var id: String { get }
    var displayName: String { get }
    var authMethod: AuthMethod { get }
    var refreshInterval: TimeInterval { get }

    func isAuthenticated() async -> Bool
    func fetchSnapshot() async throws -> ProviderSnapshot
}
```

- [ ] **Step 6: Run the full test suite to confirm nothing broke**

Run: `swift test`
Expected: all tests pass (7 total: 1 placeholder + 6 `QuotaShapeTests`).

- [ ] **Step 7: Commit**

```bash
git add Sources/OkTally/Core/QuotaShape.swift Sources/OkTally/Core/ProviderSnapshot.swift Sources/OkTally/Core/UsageProvider.swift Tests/OkTallyTests/QuotaShapeTests.swift
git commit -m "feat: add core quota/snapshot data model and UsageProvider protocol"
```

---

### Task 3: Alert thresholds and the Alert Engine

**Files:**
- Create: `Sources/OkTally/Core/AlertThreshold.swift`
- Create: `Sources/OkTally/Core/AlertEvent.swift`
- Create: `Sources/OkTally/Core/AlertEngine.swift`
- Test: `Tests/OkTallyTests/AlertEngineTests.swift`

**Interfaces:**
- Consumes: `QuotaShape`, `QuotaWindow`, `ProviderSnapshot` (Task 2).
- Produces: `AlertThreshold` (enum: `.percentage(Double)`, `.lowBalance(Decimal)`, plus `static let defaultPercentageThresholds: [AlertThreshold]` and `static let defaultLowBalanceThreshold: AlertThreshold`), `AlertEvent` (struct: `providerId: String`, `providerDisplayName: String`, `windowLabel: String`, `threshold: AlertThreshold`, `currentPercent: Double?`, `currentRemaining: Decimal?`, `resetAt: Date?`), `AlertEngine` (struct with `func evaluate(providerId: String, providerDisplayName: String, previous: ProviderSnapshot?, current: ProviderSnapshot, thresholds: [String: [AlertThreshold]]) -> [AlertEvent]` and `static func defaultThresholds(for shape: QuotaShape) -> [AlertThreshold]`). Used by Task 4 (notification formatting) and Task 7 (Scheduler).

- [ ] **Step 1: Write the failing tests for edge-triggered alerting**

```swift
// Tests/OkTallyTests/AlertEngineTests.swift
import XCTest
@testable import OkTally

final class AlertEngineTests: XCTestCase {
    let engine = AlertEngine()

    private func snapshot(percent: Double, label: String = "5h", resetAt: Date = Date()) -> ProviderSnapshot {
        ProviderSnapshot(
            providerId: "claude",
            fetchedAt: Date(),
            quotas: [QuotaWindow(label: label, shape: .rollingWindow(used: percent, limit: 100, windowStart: Date(), resetAt: resetAt))],
            usageDetail: nil
        )
    }

    func test_firstObservationAboveThreshold_firesAlert() {
        let current = snapshot(percent: 75)
        let events = engine.evaluate(providerId: "claude", providerDisplayName: "Claude Code", previous: nil, current: current, thresholds: [:])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.threshold, .percentage(0.7))
        XCTAssertEqual(events.first?.currentPercent, 75)
    }

    func test_stayingAboveThreshold_doesNotRefire() {
        let previous = snapshot(percent: 75)
        let current = snapshot(percent: 78)
        let events = engine.evaluate(providerId: "claude", providerDisplayName: "Claude Code", previous: previous, current: current, thresholds: [:])
        XCTAssertTrue(events.isEmpty)
    }

    func test_crossingMultipleThresholds_firesEachOnce() {
        let previous = snapshot(percent: 60)
        let current = snapshot(percent: 95)
        let events = engine.evaluate(providerId: "claude", providerDisplayName: "Claude Code", previous: previous, current: current, thresholds: [:])
        XCTAssertEqual(Set(events.map { $0.threshold }), Set([.percentage(0.7), .percentage(0.9)]))
    }

    func test_lowBalanceCrossingDownward_firesAlert() {
        let previous = ProviderSnapshot(providerId: "openrouter", fetchedAt: Date(), quotas: [QuotaWindow(label: "balance", shape: .creditBalance(remaining: 10, currency: "USD"))], usageDetail: nil)
        let current = ProviderSnapshot(providerId: "openrouter", fetchedAt: Date(), quotas: [QuotaWindow(label: "balance", shape: .creditBalance(remaining: 3, currency: "USD"))], usageDetail: nil)
        let events = engine.evaluate(providerId: "openrouter", providerDisplayName: "OpenRouter", previous: previous, current: current, thresholds: [:])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.currentRemaining, 3)
    }

    func test_meteredOnly_neverFires() {
        let current = ProviderSnapshot(providerId: "x", fetchedAt: Date(), quotas: [QuotaWindow(label: "spend", shape: .meteredOnly(costAccrued: 999))], usageDetail: nil)
        let events = engine.evaluate(providerId: "x", providerDisplayName: "X", previous: nil, current: current, thresholds: [:])
        XCTAssertTrue(events.isEmpty)
    }

    func test_customThresholdOverridesDefault() {
        let current = snapshot(percent: 55)
        let events = engine.evaluate(providerId: "claude", providerDisplayName: "Claude Code", previous: nil, current: current, thresholds: ["5h": [.percentage(0.5)]])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.threshold, .percentage(0.5))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail to compile**

Run: `swift test --filter AlertEngineTests`
Expected: FAIL — `cannot find type 'AlertThreshold' in scope`.

- [ ] **Step 3: Implement `AlertThreshold` and `AlertEvent`**

```swift
// Sources/OkTally/Core/AlertThreshold.swift
import Foundation

enum AlertThreshold: Codable, Equatable, Hashable {
    case percentage(Double)
    case lowBalance(Decimal)

    static let defaultPercentageThresholds: [AlertThreshold] = [.percentage(0.7), .percentage(0.9), .percentage(1.0)]
    static let defaultLowBalanceThreshold: AlertThreshold = .lowBalance(5.0)
}
```

```swift
// Sources/OkTally/Core/AlertEvent.swift
import Foundation

struct AlertEvent: Equatable {
    let providerId: String
    let providerDisplayName: String
    let windowLabel: String
    let threshold: AlertThreshold
    let currentPercent: Double?
    let currentRemaining: Decimal?
    let resetAt: Date?
}
```

- [ ] **Step 4: Implement `AlertEngine`**

```swift
// Sources/OkTally/Core/AlertEngine.swift
import Foundation

struct AlertEngine {
    func evaluate(
        providerId: String,
        providerDisplayName: String,
        previous: ProviderSnapshot?,
        current: ProviderSnapshot,
        thresholds: [String: [AlertThreshold]]
    ) -> [AlertEvent] {
        var events: [AlertEvent] = []
        for window in current.quotas {
            let previousWindow = previous?.quotas.first { $0.label == window.label }
            let windowThresholds = thresholds[window.label] ?? Self.defaultThresholds(for: window.shape)
            for threshold in windowThresholds {
                if let event = evaluateOne(
                    threshold: threshold,
                    window: window,
                    previousWindow: previousWindow,
                    providerId: providerId,
                    providerDisplayName: providerDisplayName
                ) {
                    events.append(event)
                }
            }
        }
        return events
    }

    private func evaluateOne(
        threshold: AlertThreshold,
        window: QuotaWindow,
        previousWindow: QuotaWindow?,
        providerId: String,
        providerDisplayName: String
    ) -> AlertEvent? {
        switch threshold {
        case .percentage(let pct):
            guard let currentPercent = window.shape.usedPercent else { return nil }
            let thresholdPercent = pct * 100
            let previousPercent = previousWindow?.shape.usedPercent
            let wasBelowOrFirstObservation = previousPercent == nil || previousPercent! < thresholdPercent
            guard wasBelowOrFirstObservation, currentPercent >= thresholdPercent else { return nil }
            return AlertEvent(
                providerId: providerId,
                providerDisplayName: providerDisplayName,
                windowLabel: window.label,
                threshold: threshold,
                currentPercent: currentPercent,
                currentRemaining: nil,
                resetAt: window.shape.resetAt
            )
        case .lowBalance(let limit):
            guard case .creditBalance(let remaining, _) = window.shape else { return nil }
            var previousRemaining: Decimal?
            if case .creditBalance(let r, _) = previousWindow?.shape { previousRemaining = r }
            let wasAboveOrFirstObservation = previousRemaining == nil || previousRemaining! >= limit
            guard wasAboveOrFirstObservation, remaining < limit else { return nil }
            return AlertEvent(
                providerId: providerId,
                providerDisplayName: providerDisplayName,
                windowLabel: window.label,
                threshold: threshold,
                currentPercent: nil,
                currentRemaining: remaining,
                resetAt: nil
            )
        }
    }

    static func defaultThresholds(for shape: QuotaShape) -> [AlertThreshold] {
        switch shape {
        case .rollingWindow, .periodicCounter:
            return AlertThreshold.defaultPercentageThresholds
        case .creditBalance:
            return [AlertThreshold.defaultLowBalanceThreshold]
        case .meteredOnly:
            return []
        }
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter AlertEngineTests`
Expected: PASS, 6 tests executed.

- [ ] **Step 6: Commit**

```bash
git add Sources/OkTally/Core/AlertThreshold.swift Sources/OkTally/Core/AlertEvent.swift Sources/OkTally/Core/AlertEngine.swift Tests/OkTallyTests/AlertEngineTests.swift
git commit -m "feat: add edge-triggered Alert Engine"
```

---

### Task 4: Notification formatting and dispatch

**Files:**
- Create: `Sources/OkTally/Notifications/AlertNotificationFormatter.swift`
- Create: `Sources/OkTally/Notifications/NotificationSending.swift`
- Create: `Sources/OkTally/Notifications/AlertDispatcher.swift`
- Test: `Tests/OkTallyTests/AlertNotificationFormatterTests.swift`
- Test: `Tests/OkTallyTests/AlertDispatcherTests.swift`

**Interfaces:**
- Consumes: `AlertEvent`, `AlertThreshold` (Task 3).
- Produces: `AlertNotificationFormatter.format(_ event: AlertEvent) -> (title: String, body: String)`, `NotificationSending` protocol (`func send(title: String, body: String) async`), `UNNotificationSender: NotificationSending` (real impl), `AlertDispatcher` (struct: `let sender: NotificationSending`, `func dispatch(_ events: [AlertEvent]) async`). Task 7 (Scheduler) constructs an `AlertDispatcher` and calls `dispatch`.

- [ ] **Step 1: Write the failing test for the formatter**

```swift
// Tests/OkTallyTests/AlertNotificationFormatterTests.swift
import XCTest
@testable import OkTally

final class AlertNotificationFormatterTests: XCTestCase {
    func test_percentageEvent_formatsTitleAndBody() {
        let event = AlertEvent(
            providerId: "claude",
            providerDisplayName: "Claude Code",
            windowLabel: "5h",
            threshold: .percentage(0.9),
            currentPercent: 92,
            currentRemaining: nil,
            resetAt: nil
        )
        let (title, body) = AlertNotificationFormatter.format(event)
        XCTAssertEqual(title, "Claude Code — 5h")
        XCTAssertTrue(body.contains("92%"))
    }

    func test_lowBalanceEvent_formatsBody() {
        let event = AlertEvent(
            providerId: "openrouter",
            providerDisplayName: "OpenRouter",
            windowLabel: "balance",
            threshold: .lowBalance(5),
            currentPercent: nil,
            currentRemaining: 3.25,
            resetAt: nil
        )
        let (title, body) = AlertNotificationFormatter.format(event)
        XCTAssertEqual(title, "OpenRouter — balance")
        XCTAssertTrue(body.contains("3.25"))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails to compile**

Run: `swift test --filter AlertNotificationFormatterTests`
Expected: FAIL — `cannot find 'AlertNotificationFormatter' in scope`.

- [ ] **Step 3: Implement the formatter**

```swift
// Sources/OkTally/Notifications/AlertNotificationFormatter.swift
import Foundation

enum AlertNotificationFormatter {
    static func format(_ event: AlertEvent) -> (title: String, body: String) {
        let title = "\(event.providerDisplayName) — \(event.windowLabel)"
        var body: String
        if let percent = event.currentPercent {
            body = "\(Int(percent.rounded()))% da janela \(event.windowLabel)"
            if let resetAt = event.resetAt {
                body += " — reseta \(relativeDateString(resetAt))"
            }
        } else if let remaining = event.currentRemaining {
            body = "Saldo restante: \(remaining)"
        } else {
            body = ""
        }
        return (title, body)
    }

    private static func relativeDateString(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter AlertNotificationFormatterTests`
Expected: PASS, 2 tests executed.

- [ ] **Step 5: Write the failing test for `AlertDispatcher` using a fake sender**

```swift
// Tests/OkTallyTests/AlertDispatcherTests.swift
import XCTest
@testable import OkTally

final class FakeNotificationSender: NotificationSending {
    private(set) var sentMessages: [(title: String, body: String)] = []
    func send(title: String, body: String) async {
        sentMessages.append((title, body))
    }
}

final class AlertDispatcherTests: XCTestCase {
    func test_dispatch_sendsOneNotificationPerEvent() async {
        let sender = FakeNotificationSender()
        let dispatcher = AlertDispatcher(sender: sender)
        let events = [
            AlertEvent(providerId: "claude", providerDisplayName: "Claude Code", windowLabel: "5h", threshold: .percentage(0.7), currentPercent: 71, currentRemaining: nil, resetAt: nil),
            AlertEvent(providerId: "claude", providerDisplayName: "Claude Code", windowLabel: "weekly", threshold: .percentage(0.9), currentPercent: 91, currentRemaining: nil, resetAt: nil)
        ]
        await dispatcher.dispatch(events)
        XCTAssertEqual(sender.sentMessages.count, 2)
        XCTAssertEqual(sender.sentMessages[0].title, "Claude Code — 5h")
        XCTAssertEqual(sender.sentMessages[1].title, "Claude Code — weekly")
    }

    func test_dispatch_withNoEvents_sendsNothing() async {
        let sender = FakeNotificationSender()
        let dispatcher = AlertDispatcher(sender: sender)
        await dispatcher.dispatch([])
        XCTAssertTrue(sender.sentMessages.isEmpty)
    }
}
```

- [ ] **Step 6: Run the test to verify it fails to compile**

Run: `swift test --filter AlertDispatcherTests`
Expected: FAIL — `cannot find type 'NotificationSending' in scope`.

- [ ] **Step 7: Implement `NotificationSending`, `UNNotificationSender`, and `AlertDispatcher`**

```swift
// Sources/OkTally/Notifications/NotificationSending.swift
import UserNotifications

protocol NotificationSending {
    func send(title: String, body: String) async
}

final class UNNotificationSender: NotificationSending {
    func requestAuthorizationIfNeeded() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    func send(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
```

```swift
// Sources/OkTally/Notifications/AlertDispatcher.swift
struct AlertDispatcher {
    let sender: NotificationSending

    func dispatch(_ events: [AlertEvent]) async {
        for event in events {
            let (title, body) = AlertNotificationFormatter.format(event)
            await sender.send(title: title, body: body)
        }
    }
}
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `swift test --filter AlertDispatcherTests`
Expected: PASS, 2 tests executed.

- [ ] **Step 9: Run the full suite**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 10: Commit**

```bash
git add Sources/OkTally/Notifications Tests/OkTallyTests/AlertNotificationFormatterTests.swift Tests/OkTallyTests/AlertDispatcherTests.swift
git commit -m "feat: add notification formatting and dispatch"
```

---

### Task 5: Pricing Engine (OpenRouter model pricing + cost estimation)

**Files:**
- Create: `Sources/OkTally/Pricing/ModelPricing.swift`
- Create: `Sources/OkTally/Pricing/OpenRouterPricingSource.swift`
- Create: `Sources/OkTally/Pricing/PricingEngine.swift`
- Test: `Tests/OkTallyTests/PricingEngineTests.swift`
- Test fixture: `Tests/OkTallyTests/Fixtures/openrouter_models_response.json`

**Interfaces:**
- Consumes: `UsageDetail` (Task 2).
- Produces: `ModelPricing` (struct: `modelId: String`, `promptPricePerToken: Decimal`, `completionPricePerToken: Decimal`), `PricingSource` protocol (`func fetchModelPricing() async throws -> [ModelPricing]`), `OpenRouterPricingSource: PricingSource` (real impl, hits `https://openrouter.ai/api/v1/models`), `PricingEngine` actor (`init(source: PricingSource, cacheTTL: TimeInterval = 3600)`, `func refreshIfStale() async throws`, `func estimatedCost(for usage: UsageDetail) async -> Decimal?`). Task 10 (OpenRouter plugin) and later cost-estimation UI depend on this.

- [ ] **Step 1: Create the fixture file**

```json
// Tests/OkTallyTests/Fixtures/openrouter_models_response.json
{
  "data": [
    {
      "id": "anthropic/claude-3.5-sonnet",
      "pricing": { "prompt": "0.000003", "completion": "0.000015" }
    },
    {
      "id": "openai/gpt-4o",
      "pricing": { "prompt": "0.0000025", "completion": "0.00001" }
    }
  ]
}
```

- [ ] **Step 2: Write the failing test**

```swift
// Tests/OkTallyTests/PricingEngineTests.swift
import XCTest
@testable import OkTally

final class FakePricingSource: PricingSource {
    var pricingToReturn: [ModelPricing] = []
    private(set) var fetchCount = 0
    func fetchModelPricing() async throws -> [ModelPricing] {
        fetchCount += 1
        return pricingToReturn
    }
}

final class PricingEngineTests: XCTestCase {
    func test_refreshIfStale_fetchesOnceThenCaches() async throws {
        let source = FakePricingSource()
        source.pricingToReturn = [ModelPricing(modelId: "m1", promptPricePerToken: 0.000003, completionPricePerToken: 0.000015)]
        let engine = PricingEngine(source: source, cacheTTL: 3600)

        try await engine.refreshIfStale()
        try await engine.refreshIfStale()

        XCTAssertEqual(source.fetchCount, 1)
    }

    func test_estimatedCost_computesPromptPlusCompletion() async throws {
        let source = FakePricingSource()
        source.pricingToReturn = [ModelPricing(modelId: "m1", promptPricePerToken: 0.000003, completionPricePerToken: 0.000015)]
        let engine = PricingEngine(source: source)
        try await engine.refreshIfStale()

        let usage = UsageDetail(modelId: "m1", promptTokens: 1000, completionTokens: 500)
        let cost = await engine.estimatedCost(for: usage)

        XCTAssertEqual(cost, Decimal(0.003) + Decimal(0.0075))
    }

    func test_estimatedCost_unknownModel_returnsNil() async throws {
        let source = FakePricingSource()
        let engine = PricingEngine(source: source)
        try await engine.refreshIfStale()

        let usage = UsageDetail(modelId: "unknown/model", promptTokens: 10, completionTokens: 10)
        let cost = await engine.estimatedCost(for: usage)

        XCTAssertNil(cost)
    }

    func test_openRouterPricingSource_decodesFixture() async throws {
        let fixtureURL = Bundle.module.url(forResource: "openrouter_models_response", withExtension: "json")!
        let data = try Data(contentsOf: fixtureURL)
        URLProtocolStub.stubResponses[URL(string: "https://openrouter.ai/api/v1/models")!] = (data, 200)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: config)

        let source = OpenRouterPricingSource(session: session)
        let pricing = try await source.fetchModelPricing()

        XCTAssertEqual(pricing.count, 2)
        XCTAssertEqual(pricing.first?.modelId, "anthropic/claude-3.5-sonnet")
    }
}
```

- [ ] **Step 3: Add the shared `URLProtocolStub` test helper (used by this and later network tests)**

```swift
// Tests/OkTallyTests/URLProtocolStub.swift
import Foundation

final class URLProtocolStub: URLProtocol {
    static var stubResponses: [URL: (Data, Int)] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let (data, status) = Self.stubResponses[url] else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
```

- [ ] **Step 4: Run the tests to verify they fail to compile**

Run: `swift test --filter PricingEngineTests`
Expected: FAIL — `cannot find type 'ModelPricing' in scope`.

- [ ] **Step 5: Implement `ModelPricing` and `OpenRouterPricingSource`**

```swift
// Sources/OkTally/Pricing/ModelPricing.swift
import Foundation

struct ModelPricing: Equatable {
    let modelId: String
    let promptPricePerToken: Decimal
    let completionPricePerToken: Decimal
}
```

```swift
// Sources/OkTally/Pricing/OpenRouterPricingSource.swift
import Foundation

protocol PricingSource {
    func fetchModelPricing() async throws -> [ModelPricing]
}

enum PricingSourceError: Error {
    case badResponse(Int?)
}

private struct OpenRouterModelsResponse: Codable {
    struct Model: Codable {
        struct Pricing: Codable {
            let prompt: String
            let completion: String
        }
        let id: String
        let pricing: Pricing
    }
    let data: [Model]
}

final class OpenRouterPricingSource: PricingSource {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func fetchModelPricing() async throws -> [ModelPricing] {
        let url = URL(string: "https://openrouter.ai/api/v1/models")!
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw PricingSourceError.badResponse((response as? HTTPURLResponse)?.statusCode)
        }
        let decoded = try JSONDecoder().decode(OpenRouterModelsResponse.self, from: data)
        return decoded.data.compactMap { model in
            guard let prompt = Decimal(string: model.pricing.prompt),
                  let completion = Decimal(string: model.pricing.completion) else { return nil }
            return ModelPricing(modelId: model.id, promptPricePerToken: prompt, completionPricePerToken: completion)
        }
    }
}
```

- [ ] **Step 6: Implement `PricingEngine`**

```swift
// Sources/OkTally/Pricing/PricingEngine.swift
import Foundation

actor PricingEngine {
    private let source: PricingSource
    private let cacheTTL: TimeInterval
    private var cache: [String: ModelPricing] = [:]
    private var lastFetched: Date?

    init(source: PricingSource, cacheTTL: TimeInterval = 3600) {
        self.source = source
        self.cacheTTL = cacheTTL
    }

    func refreshIfStale() async throws {
        if let lastFetched, Date().timeIntervalSince(lastFetched) < cacheTTL { return }
        let pricing = try await source.fetchModelPricing()
        cache = Dictionary(uniqueKeysWithValues: pricing.map { ($0.modelId, $0) })
        lastFetched = Date()
    }

    func estimatedCost(for usage: UsageDetail) -> Decimal? {
        guard let pricing = cache[usage.modelId] else { return nil }
        return pricing.promptPricePerToken * Decimal(usage.promptTokens)
            + pricing.completionPricePerToken * Decimal(usage.completionTokens)
    }
}
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `swift test --filter PricingEngineTests`
Expected: PASS, 4 tests executed.

- [ ] **Step 8: Run the full suite**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 9: Commit**

```bash
git add Sources/OkTally/Pricing Tests/OkTallyTests/PricingEngineTests.swift Tests/OkTallyTests/URLProtocolStub.swift Tests/OkTallyTests/Fixtures/openrouter_models_response.json
git commit -m "feat: add OpenRouter-backed Pricing Engine"
```

---

### Task 6: SQLite storage

**Files:**
- Create: `Sources/OkTally/Storage/StorageManaging.swift`
- Create: `Sources/OkTally/Storage/SQLiteStorage.swift`
- Test: `Tests/OkTallyTests/SQLiteStorageTests.swift`

**Interfaces:**
- Consumes: `ProviderSnapshot`, `QuotaWindow`, `UsageDetail` (Task 2), GRDB (external dependency from Task 1's `Package.swift`).
- Produces: `StorageManaging` protocol (`func save(_ snapshot: ProviderSnapshot) throws`, `func latestSnapshot(providerId: String) throws -> ProviderSnapshot?`, `func snapshots(providerId: String, since: Date) throws -> [ProviderSnapshot]`), `SQLiteStorage: StorageManaging` (`init(path: String) throws`). Task 7 (Scheduler) and Task 13 (AppModel) depend on `StorageManaging`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/OkTallyTests/SQLiteStorageTests.swift
import XCTest
@testable import OkTally

final class SQLiteStorageTests: XCTestCase {
    func test_save_and_latestSnapshot_roundTrips() throws {
        let storage = try SQLiteStorage(path: ":memory:")
        let older = ProviderSnapshot(
            providerId: "claude",
            fetchedAt: Date(timeIntervalSince1970: 1000),
            quotas: [QuotaWindow(label: "5h", shape: .rollingWindow(used: 10, limit: 100, windowStart: Date(timeIntervalSince1970: 0), resetAt: Date(timeIntervalSince1970: 2000)))],
            usageDetail: nil
        )
        let newer = ProviderSnapshot(
            providerId: "claude",
            fetchedAt: Date(timeIntervalSince1970: 2000),
            quotas: [QuotaWindow(label: "5h", shape: .rollingWindow(used: 20, limit: 100, windowStart: Date(timeIntervalSince1970: 0), resetAt: Date(timeIntervalSince1970: 2000)))],
            usageDetail: nil
        )

        try storage.save(older)
        try storage.save(newer)

        let latest = try storage.latestSnapshot(providerId: "claude")
        XCTAssertEqual(latest, newer)
    }

    func test_latestSnapshot_forUnknownProvider_returnsNil() throws {
        let storage = try SQLiteStorage(path: ":memory:")
        XCTAssertNil(try storage.latestSnapshot(providerId: "nope"))
    }

    func test_snapshots_since_returnsAscendingSubset() throws {
        let storage = try SQLiteStorage(path: ":memory:")
        let t0 = ProviderSnapshot(providerId: "claude", fetchedAt: Date(timeIntervalSince1970: 0), quotas: [], usageDetail: nil)
        let t100 = ProviderSnapshot(providerId: "claude", fetchedAt: Date(timeIntervalSince1970: 100), quotas: [], usageDetail: nil)
        let t200 = ProviderSnapshot(providerId: "claude", fetchedAt: Date(timeIntervalSince1970: 200), quotas: [], usageDetail: nil)
        try storage.save(t0)
        try storage.save(t100)
        try storage.save(t200)

        let result = try storage.snapshots(providerId: "claude", since: Date(timeIntervalSince1970: 50))

        XCTAssertEqual(result, [t100, t200])
    }

    func test_save_withUsageDetail_roundTrips() throws {
        let storage = try SQLiteStorage(path: ":memory:")
        let snapshot = ProviderSnapshot(
            providerId: "openrouter",
            fetchedAt: Date(timeIntervalSince1970: 500),
            quotas: [QuotaWindow(label: "balance", shape: .creditBalance(remaining: 12.5, currency: "USD"))],
            usageDetail: [UsageDetail(modelId: "m1", promptTokens: 10, completionTokens: 5)]
        )
        try storage.save(snapshot)
        let latest = try storage.latestSnapshot(providerId: "openrouter")
        XCTAssertEqual(latest, snapshot)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail to compile**

Run: `swift test --filter SQLiteStorageTests`
Expected: FAIL — `cannot find type 'SQLiteStorage' in scope`.

- [ ] **Step 3: Implement `StorageManaging` and `SQLiteStorage`**

```swift
// Sources/OkTally/Storage/StorageManaging.swift
import Foundation

protocol StorageManaging {
    func save(_ snapshot: ProviderSnapshot) throws
    func latestSnapshot(providerId: String) throws -> ProviderSnapshot?
    func snapshots(providerId: String, since: Date) throws -> [ProviderSnapshot]
}
```

```swift
// Sources/OkTally/Storage/SQLiteStorage.swift
import Foundation
import GRDB

private struct SnapshotRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "snapshots"
    var id: Int64?
    var providerId: String
    var fetchedAt: Date
    var quotasJSON: Data
    var usageDetailJSON: Data?

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

final class SQLiteStorage: StorageManaging {
    private let dbQueue: DatabaseQueue

    init(path: String) throws {
        dbQueue = try DatabaseQueue(path: path)
        try dbQueue.write { db in
            try db.create(table: "snapshots", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("providerId", .text).notNull().indexed()
                t.column("fetchedAt", .datetime).notNull()
                t.column("quotasJSON", .blob).notNull()
                t.column("usageDetailJSON", .blob)
            }
        }
    }

    func save(_ snapshot: ProviderSnapshot) throws {
        let quotasJSON = try JSONEncoder().encode(snapshot.quotas)
        let usageDetailJSON = try snapshot.usageDetail.map { try JSONEncoder().encode($0) }
        var record = SnapshotRecord(
            id: nil,
            providerId: snapshot.providerId,
            fetchedAt: snapshot.fetchedAt,
            quotasJSON: quotasJSON,
            usageDetailJSON: usageDetailJSON
        )
        try dbQueue.write { db in
            try record.insert(db)
        }
    }

    func latestSnapshot(providerId: String) throws -> ProviderSnapshot? {
        try dbQueue.read { db in
            guard let record = try SnapshotRecord
                .filter(Column("providerId") == providerId)
                .order(Column("fetchedAt").desc)
                .fetchOne(db) else { return nil }
            return try Self.decode(record)
        }
    }

    func snapshots(providerId: String, since: Date) throws -> [ProviderSnapshot] {
        try dbQueue.read { db in
            let records = try SnapshotRecord
                .filter(Column("providerId") == providerId && Column("fetchedAt") >= since)
                .order(Column("fetchedAt").asc)
                .fetchAll(db)
            return try records.map { try Self.decode($0) }
        }
    }

    private static func decode(_ record: SnapshotRecord) throws -> ProviderSnapshot {
        let quotas = try JSONDecoder().decode([QuotaWindow].self, from: record.quotasJSON)
        let usageDetail = try record.usageDetailJSON.map { try JSONDecoder().decode([UsageDetail].self, from: $0) }
        return ProviderSnapshot(providerId: record.providerId, fetchedAt: record.fetchedAt, quotas: quotas, usageDetail: usageDetail)
    }
}
```

If `mutating func didInsert(_ inserted: InsertionSuccess)` fails to compile against the resolved GRDB version, check the installed GRDB version's `MutablePersistableRecord` documentation for the current `didInsert` signature (it changed between GRDB major versions) and adjust — the rest of the implementation is version-independent.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter SQLiteStorageTests`
Expected: PASS, 4 tests executed.

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/OkTally/Storage Tests/OkTallyTests/SQLiteStorageTests.swift
git commit -m "feat: add GRDB-backed SQLite snapshot storage"
```

---

### Task 7: Plugin Registry and Scheduler

**Files:**
- Create: `Sources/OkTally/Core/PluginRegistry.swift`
- Create: `Sources/OkTally/Core/Scheduler.swift`
- Test: `Tests/OkTallyTests/SchedulerTests.swift`

**Interfaces:**
- Consumes: `UsageProvider` (Task 2), `StorageManaging` (Task 6), `AlertEngine` (Task 3), `AlertDispatcher` (Task 4).
- Produces: `PluginRegistry` (class: `private(set) var providers: [UsageProvider]`, `func register(_ provider: UsageProvider)`), `SchedulerFetchResult` (struct: `providerId: String`, `outcome: Outcome` where `enum Outcome { case success(ProviderSnapshot), failure(Error) }`), `Scheduler` (class: `init(registry:storage:alertEngine:alertDispatcher:thresholdsProvider:)`, `var onResult: ((SchedulerFetchResult) -> Void)?`, `@discardableResult func fetchAll() async -> [SchedulerFetchResult]`, `func startPeriodicLoop()`, `private(set) var lastError: [String: Error]`). Task 13 (AppModel) wires `onResult` and calls `fetchAll()`/`startPeriodicLoop()`.

- [ ] **Step 1: Write the failing test using fake providers and fake storage**

```swift
// Tests/OkTallyTests/SchedulerTests.swift
import XCTest
@testable import OkTally

final class FakeUsageProvider: UsageProvider {
    let id: String
    let displayName: String
    let authMethod: AuthMethod = .apiKey
    let refreshInterval: TimeInterval = 60
    var snapshotToReturn: ProviderSnapshot?
    var errorToThrow: Error?

    init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }

    func isAuthenticated() async -> Bool { true }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        if let errorToThrow { throw errorToThrow }
        return snapshotToReturn!
    }
}

final class FakeStorage: StorageManaging {
    private var byProvider: [String: [ProviderSnapshot]] = [:]
    private(set) var saveCount = 0

    func save(_ snapshot: ProviderSnapshot) throws {
        saveCount += 1
        byProvider[snapshot.providerId, default: []].append(snapshot)
    }

    func latestSnapshot(providerId: String) throws -> ProviderSnapshot? {
        byProvider[providerId]?.last
    }

    func snapshots(providerId: String, since: Date) throws -> [ProviderSnapshot] {
        (byProvider[providerId] ?? []).filter { $0.fetchedAt >= since }
    }
}

enum FakeError: Error { case boom }

final class SchedulerTests: XCTestCase {
    private func snapshot(providerId: String, percent: Double) -> ProviderSnapshot {
        ProviderSnapshot(
            providerId: providerId,
            fetchedAt: Date(),
            quotas: [QuotaWindow(label: "5h", shape: .rollingWindow(used: percent, limit: 100, windowStart: Date(), resetAt: Date()))],
            usageDetail: nil
        )
    }

    func test_fetchAll_savesSnapshotsAndDispatchesAlerts() async {
        let provider = FakeUsageProvider(id: "claude", displayName: "Claude Code")
        provider.snapshotToReturn = snapshot(providerId: "claude", percent: 75)
        let registry = PluginRegistry()
        registry.register(provider)
        let storage = FakeStorage()
        let sender = FakeNotificationSender()
        let scheduler = Scheduler(
            registry: registry,
            storage: storage,
            alertEngine: AlertEngine(),
            alertDispatcher: AlertDispatcher(sender: sender)
        )

        let results = await scheduler.fetchAll()

        XCTAssertEqual(storage.saveCount, 1)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(sender.sentMessages.count, 1)
    }

    func test_fetchAll_oneProviderFailing_doesNotAffectOthers() async {
        let good = FakeUsageProvider(id: "openrouter", displayName: "OpenRouter")
        good.snapshotToReturn = snapshot(providerId: "openrouter", percent: 10)
        let bad = FakeUsageProvider(id: "claude", displayName: "Claude Code")
        bad.errorToThrow = FakeError.boom
        let registry = PluginRegistry()
        registry.register(bad)
        registry.register(good)
        let storage = FakeStorage()
        let scheduler = Scheduler(
            registry: registry,
            storage: storage,
            alertEngine: AlertEngine(),
            alertDispatcher: AlertDispatcher(sender: FakeNotificationSender())
        )

        let results = await scheduler.fetchAll()

        XCTAssertEqual(storage.saveCount, 1)
        XCTAssertNotNil(scheduler.lastError["claude"])
        XCTAssertNil(scheduler.lastError["openrouter"])
        XCTAssertEqual(results.count, 2)
    }

    func test_fetchAll_invokesOnResultCallback() async {
        let provider = FakeUsageProvider(id: "claude", displayName: "Claude Code")
        provider.snapshotToReturn = snapshot(providerId: "claude", percent: 5)
        let registry = PluginRegistry()
        registry.register(provider)
        let scheduler = Scheduler(
            registry: registry,
            storage: FakeStorage(),
            alertEngine: AlertEngine(),
            alertDispatcher: AlertDispatcher(sender: FakeNotificationSender())
        )
        var received: [SchedulerFetchResult] = []
        scheduler.onResult = { received.append($0) }

        _ = await scheduler.fetchAll()

        XCTAssertEqual(received.count, 1)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail to compile**

Run: `swift test --filter SchedulerTests`
Expected: FAIL — `cannot find type 'PluginRegistry' in scope`.

- [ ] **Step 3: Implement `PluginRegistry`**

```swift
// Sources/OkTally/Core/PluginRegistry.swift
final class PluginRegistry {
    private(set) var providers: [UsageProvider] = []

    func register(_ provider: UsageProvider) {
        providers.append(provider)
    }
}
```

- [ ] **Step 4: Implement `Scheduler`**

```swift
// Sources/OkTally/Core/Scheduler.swift
import Foundation

struct SchedulerFetchResult {
    enum Outcome {
        case success(ProviderSnapshot)
        case failure(Error)
    }
    let providerId: String
    let outcome: Outcome
}

final class Scheduler {
    private let registry: PluginRegistry
    private let storage: StorageManaging
    private let alertEngine: AlertEngine
    private let alertDispatcher: AlertDispatcher
    private let thresholdsProvider: (String) -> [String: [AlertThreshold]]

    var onResult: ((SchedulerFetchResult) -> Void)?
    private(set) var lastError: [String: Error] = [:]

    init(
        registry: PluginRegistry,
        storage: StorageManaging,
        alertEngine: AlertEngine,
        alertDispatcher: AlertDispatcher,
        thresholdsProvider: @escaping (String) -> [String: [AlertThreshold]] = { _ in [:] }
    ) {
        self.registry = registry
        self.storage = storage
        self.alertEngine = alertEngine
        self.alertDispatcher = alertDispatcher
        self.thresholdsProvider = thresholdsProvider
    }

    @discardableResult
    func fetchAll() async -> [SchedulerFetchResult] {
        var results: [SchedulerFetchResult] = []
        for provider in registry.providers {
            results.append(await fetchOne(provider))
        }
        return results
    }

    func startPeriodicLoop() {
        for provider in registry.providers {
            Task {
                while !Task.isCancelled {
                    _ = await fetchOne(provider)
                    try? await Task.sleep(nanoseconds: UInt64(provider.refreshInterval * 1_000_000_000))
                }
            }
        }
    }

    private func fetchOne(_ provider: UsageProvider) async -> SchedulerFetchResult {
        do {
            let previous = try? storage.latestSnapshot(providerId: provider.id)
            let snapshot = try await provider.fetchSnapshot()
            try storage.save(snapshot)
            let thresholds = thresholdsProvider(provider.id)
            let events = alertEngine.evaluate(
                providerId: provider.id,
                providerDisplayName: provider.displayName,
                previous: previous,
                current: snapshot,
                thresholds: thresholds
            )
            await alertDispatcher.dispatch(events)
            lastError[provider.id] = nil
            let result = SchedulerFetchResult(providerId: provider.id, outcome: .success(snapshot))
            onResult?(result)
            return result
        } catch {
            lastError[provider.id] = error
            let result = SchedulerFetchResult(providerId: provider.id, outcome: .failure(error))
            onResult?(result)
            return result
        }
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter SchedulerTests`
Expected: PASS, 3 tests executed.

- [ ] **Step 6: Run the full suite**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/OkTally/Core/PluginRegistry.swift Sources/OkTally/Core/Scheduler.swift Tests/OkTallyTests/SchedulerTests.swift
git commit -m "feat: add PluginRegistry and Scheduler"
```

---

### Task 8: Claude credential provider (Keychain + file fallback)

**Files:**
- Create: `Sources/OkTally/Plugins/Claude/ClaudeCredentials.swift`
- Create: `Sources/OkTally/Plugins/Claude/ClaudeCredentialProvider.swift`
- Test: `Tests/OkTallyTests/ClaudeCredentialProviderTests.swift`

**Interfaces:**
- Consumes: nothing beyond Foundation/Security.
- Produces: `ClaudeCredentials` (struct: `accessToken: String`, `refreshToken: String?`, `expiresAt: Date?`), `ClaudeCredentialError` (enum: `.notFound`, `.malformed`), `CredentialStoreReading` protocol (`func readClaudeCredentialsJSON() -> Data?`), `KeychainCredentialReader: CredentialStoreReading` (real impl), `ClaudeCredentialProvider` (class: `init(keychainReader: CredentialStoreReading = KeychainCredentialReader(), fileURL: URL = ...)`, `func loadCredentials() throws -> ClaudeCredentials`). Task 9 (`ClaudeUsageProvider`) depends on `ClaudeCredentialProvider`.

Note: the exact JSON shape of `~/.claude/.credentials.json` (and the Keychain item's payload, which is the same JSON) is based on third-party documentation of Claude Code's credential format (a top-level `claudeAiOauth` object wrapping `accessToken`/`refreshToken`/`expiresAt`). `loadCredentials()` is written defensively to also accept a flat (unwrapped) shape, and Step 8 below has the engineer confirm the real shape against their own machine before moving to Task 9.

- [ ] **Step 1: Write the failing test for the file-fallback and decoding paths**

```swift
// Tests/OkTallyTests/ClaudeCredentialProviderTests.swift
import XCTest
@testable import OkTally

final class FakeCredentialStoreReading: CredentialStoreReading {
    var dataToReturn: Data?
    func readClaudeCredentialsJSON() -> Data? { dataToReturn }
}

final class ClaudeCredentialProviderTests: XCTestCase {
    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    }

    func test_keychainHit_decodesWrappedShape() throws {
        let keychain = FakeCredentialStoreReading()
        keychain.dataToReturn = """
        {"claudeAiOauth":{"accessToken":"abc123","refreshToken":"r1","expiresAt":1700000000000}}
        """.data(using: .utf8)
        let provider = ClaudeCredentialProvider(keychainReader: keychain, fileURL: tempFileURL())

        let credentials = try provider.loadCredentials()

        XCTAssertEqual(credentials.accessToken, "abc123")
    }

    func test_keychainMiss_fallsBackToFile() throws {
        let keychain = FakeCredentialStoreReading()
        keychain.dataToReturn = nil
        let fileURL = tempFileURL()
        try """
        {"claudeAiOauth":{"accessToken":"fromfile","refreshToken":null,"expiresAt":null}}
        """.data(using: .utf8)!.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let provider = ClaudeCredentialProvider(keychainReader: keychain, fileURL: fileURL)

        let credentials = try provider.loadCredentials()

        XCTAssertEqual(credentials.accessToken, "fromfile")
    }

    func test_keychainMissAndNoFile_throwsNotFound() {
        let keychain = FakeCredentialStoreReading()
        keychain.dataToReturn = nil
        let provider = ClaudeCredentialProvider(keychainReader: keychain, fileURL: tempFileURL())

        XCTAssertThrowsError(try provider.loadCredentials()) { error in
            XCTAssertEqual(error as? ClaudeCredentialError, .notFound)
        }
    }

    func test_malformedJSON_throwsMalformed() {
        let keychain = FakeCredentialStoreReading()
        keychain.dataToReturn = "not json".data(using: .utf8)
        let provider = ClaudeCredentialProvider(keychainReader: keychain, fileURL: tempFileURL())

        XCTAssertThrowsError(try provider.loadCredentials()) { error in
            XCTAssertEqual(error as? ClaudeCredentialError, .malformed)
        }
    }

    func test_flatShape_alsoDecodes() throws {
        let keychain = FakeCredentialStoreReading()
        keychain.dataToReturn = """
        {"accessToken":"flat123","refreshToken":null,"expiresAt":null}
        """.data(using: .utf8)
        let provider = ClaudeCredentialProvider(keychainReader: keychain, fileURL: tempFileURL())

        let credentials = try provider.loadCredentials()

        XCTAssertEqual(credentials.accessToken, "flat123")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail to compile**

Run: `swift test --filter ClaudeCredentialProviderTests`
Expected: FAIL — `cannot find type 'ClaudeCredentials' in scope`.

- [ ] **Step 3: Implement `ClaudeCredentials`**

```swift
// Sources/OkTally/Plugins/Claude/ClaudeCredentials.swift
import Foundation

struct ClaudeCredentials: Codable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
}
```

- [ ] **Step 4: Implement `ClaudeCredentialProvider`**

```swift
// Sources/OkTally/Plugins/Claude/ClaudeCredentialProvider.swift
import Foundation
import Security

enum ClaudeCredentialError: Error, Equatable {
    case notFound
    case malformed
}

protocol CredentialStoreReading {
    func readClaudeCredentialsJSON() -> Data?
}

final class KeychainCredentialReader: CredentialStoreReading {
    func readClaudeCredentialsJSON() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecAttrAccount as String: NSUserName(),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return data
    }
}

final class ClaudeCredentialProvider {
    private let keychainReader: CredentialStoreReading
    private let fileURL: URL

    init(
        keychainReader: CredentialStoreReading = KeychainCredentialReader(),
        fileURL: URL = URL(fileURLWithPath: NSHomeDirectory() + "/.claude/.credentials.json")
    ) {
        self.keychainReader = keychainReader
        self.fileURL = fileURL
    }

    func loadCredentials() throws -> ClaudeCredentials {
        guard let data = keychainReader.readClaudeCredentialsJSON() ?? (try? Data(contentsOf: fileURL)) else {
            throw ClaudeCredentialError.notFound
        }
        guard let credentials = Self.decode(data) else {
            throw ClaudeCredentialError.malformed
        }
        return credentials
    }

    private static func decode(_ data: Data) -> ClaudeCredentials? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        struct Wrapper: Codable { let claudeAiOauth: ClaudeCredentials }
        if let wrapper = try? decoder.decode(Wrapper.self, from: data) {
            return wrapper.claudeAiOauth
        }
        return try? decoder.decode(ClaudeCredentials.self, from: data)
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter ClaudeCredentialProviderTests`
Expected: PASS, 5 tests executed.

- [ ] **Step 6: Run the full suite**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/OkTally/Plugins/Claude/ClaudeCredentials.swift Sources/OkTally/Plugins/Claude/ClaudeCredentialProvider.swift Tests/OkTallyTests/ClaudeCredentialProviderTests.swift
git commit -m "feat: add Claude Keychain/file credential provider"
```

- [ ] **Step 8: Confirm the real credential shape on your machine (manual, informs Task 9)**

Run:
```bash
security find-generic-password -s "Claude Code-credentials" -a "$USER" -w
```
Expected: prints a JSON blob. Compare its shape against the `claudeAiOauth`-wrapped shape assumed above — if it differs (different key names, no wrapper, camelCase vs snake_case), note the real field names now; Task 9's manual verification step reuses this same command.

---

### Task 9: Claude usage API client and plugin

**Files:**
- Create: `Sources/OkTally/Plugins/Claude/ClaudeUsageAPIClient.swift`
- Create: `Sources/OkTally/Plugins/Claude/ClaudeUsageProvider.swift`
- Test: `Tests/OkTallyTests/ClaudeUsageProviderTests.swift`

**Interfaces:**
- Consumes: `ClaudeCredentialProvider`, `ClaudeCredentials` (Task 8), `UsageProvider`, `ProviderSnapshot`, `QuotaWindow`, `QuotaShape` (Task 2).
- Produces: `ClaudeUsageWindow` (struct: `utilization: Double`, `resetsAt: Date`), `ClaudeUsageResponse` (struct: `fiveHour: ClaudeUsageWindow`, `sevenDay: ClaudeUsageWindow`, `sevenDayOpus: ClaudeUsageWindow?`), `ClaudeUsageFetching` protocol (`func fetchUsage(accessToken: String) async throws -> ClaudeUsageResponse`), `ClaudeUsageAPIClient: ClaudeUsageFetching`, `ClaudeUsageProvider: UsageProvider` (`id = "claude"`). Registered into `PluginRegistry` in Task 14.

Note: `api.anthropic.com/api/oauth/usage`'s exact response field names are not publicly documented — third-party research confirms it returns a utilization percentage, a reset time, and weekly limits per window, but not the literal JSON keys. Step 1 below has the engineer call the real endpoint with their own token to confirm/correct the field names in `CodingKeys` before the fixture-based tests are trusted as representative.

- [ ] **Step 1: Confirm the real response shape (manual)**

Run (reusing the token extraction pattern from Task 8, Step 8):
```bash
TOKEN=$(security find-generic-password -s "Claude Code-credentials" -a "$USER" -w | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("claudeAiOauth",d).get("accessToken",""))')
curl -s https://api.anthropic.com/api/oauth/usage \
  -H "Authorization: Bearer $TOKEN" \
  -H "anthropic-beta: oauth-2025-04-20" \
  -H "User-Agent: Claude-Code/1.0" | python3 -m json.tool
```
Expected: a 200 response with JSON containing 5-hour, weekly, and (if on a plan with a model-tier cap) weekly-per-tier usage data. If you get a 429, the endpoint is known to be sensitive to the `User-Agent` header — try a few realistic values (e.g. mimicking the installed Claude Code CLI's own UA) and retry no more than once every ~180 seconds to avoid tripping the rate limit further. Once you see real field names, update the `CodingKeys` in Step 3 below (and the fixture in Step 2) to match reality before trusting the tests as representative of production behavior.

- [ ] **Step 2: Create the fixture file (adjust field names per Step 1's findings before relying on this test)**

```json
// Tests/OkTallyTests/Fixtures/claude_usage_response.json
{
  "five_hour": { "utilization": 42.5, "resets_at": "2026-08-07T18:00:00Z" },
  "seven_day": { "utilization": 61.0, "resets_at": "2026-08-11T00:00:00Z" },
  "seven_day_opus": { "utilization": 15.0, "resets_at": "2026-08-11T00:00:00Z" }
}
```

- [ ] **Step 3: Write the failing test**

```swift
// Tests/OkTallyTests/ClaudeUsageProviderTests.swift
import XCTest
@testable import OkTally

final class FakeClaudeUsageFetching: ClaudeUsageFetching {
    var responseToReturn: ClaudeUsageResponse!
    func fetchUsage(accessToken: String) async throws -> ClaudeUsageResponse { responseToReturn }
}

final class ClaudeUsageProviderTests: XCTestCase {
    func test_fetchSnapshot_mapsThreeWindows() async throws {
        let credentialProvider = ClaudeCredentialProvider(
            keychainReader: FakeCredentialStoreReadingWithToken(token: "tok"),
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("unused.json")
        )
        let fetcher = FakeClaudeUsageFetching()
        fetcher.responseToReturn = ClaudeUsageResponse(
            fiveHour: ClaudeUsageWindow(utilization: 42.5, resetsAt: Date(timeIntervalSince1970: 2_000_000)),
            sevenDay: ClaudeUsageWindow(utilization: 61.0, resetsAt: Date(timeIntervalSince1970: 2_500_000)),
            sevenDayOpus: ClaudeUsageWindow(utilization: 15.0, resetsAt: Date(timeIntervalSince1970: 2_500_000))
        )
        let provider = ClaudeUsageProvider(credentialProvider: credentialProvider, apiClient: fetcher)

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.providerId, "claude")
        XCTAssertEqual(snapshot.quotas.count, 3)
        XCTAssertEqual(snapshot.quotas.first { $0.label == "5h" }?.shape.usedPercent, 42.5)
        XCTAssertEqual(snapshot.quotas.first { $0.label == "weekly" }?.shape.usedPercent, 61.0)
        XCTAssertEqual(snapshot.quotas.first { $0.label == "weekly-opus" }?.shape.usedPercent, 15.0)
    }

    func test_fetchSnapshot_withoutOpusWindow_returnsTwoWindows() async throws {
        let credentialProvider = ClaudeCredentialProvider(
            keychainReader: FakeCredentialStoreReadingWithToken(token: "tok"),
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("unused.json")
        )
        let fetcher = FakeClaudeUsageFetching()
        fetcher.responseToReturn = ClaudeUsageResponse(
            fiveHour: ClaudeUsageWindow(utilization: 10, resetsAt: Date()),
            sevenDay: ClaudeUsageWindow(utilization: 20, resetsAt: Date()),
            sevenDayOpus: nil
        )
        let provider = ClaudeUsageProvider(credentialProvider: credentialProvider, apiClient: fetcher)

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.quotas.count, 2)
    }

    func test_isAuthenticated_falseWhenNoCredentials() async {
        let credentialProvider = ClaudeCredentialProvider(
            keychainReader: FakeCredentialStoreReading(),
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        let provider = ClaudeUsageProvider(credentialProvider: credentialProvider, apiClient: FakeClaudeUsageFetching())

        let isAuthenticated = await provider.isAuthenticated()

        XCTAssertFalse(isAuthenticated)
    }

    func test_apiClient_decodesFixture() async throws {
        let fixtureURL = Bundle.module.url(forResource: "claude_usage_response", withExtension: "json")!
        let data = try Data(contentsOf: fixtureURL)
        URLProtocolStub.stubResponses[URL(string: "https://api.anthropic.com/api/oauth/usage")!] = (data, 200)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: config)

        let client = ClaudeUsageAPIClient(session: session)
        let response = try await client.fetchUsage(accessToken: "tok")

        XCTAssertEqual(response.fiveHour.utilization, 42.5)
        XCTAssertEqual(response.sevenDayOpus?.utilization, 15.0)
    }
}

private final class FakeCredentialStoreReadingWithToken: CredentialStoreReading {
    let token: String
    init(token: String) { self.token = token }
    func readClaudeCredentialsJSON() -> Data? {
        try? JSONEncoder().encode(["accessToken": token])
    }
}
```

- [ ] **Step 4: Run the tests to verify they fail to compile**

Run: `swift test --filter ClaudeUsageProviderTests`
Expected: FAIL — `cannot find type 'ClaudeUsageResponse' in scope`.

- [ ] **Step 5: Implement `ClaudeUsageAPIClient`**

```swift
// Sources/OkTally/Plugins/Claude/ClaudeUsageAPIClient.swift
import Foundation

struct ClaudeUsageWindow: Codable, Equatable {
    let utilization: Double
    let resetsAt: Date

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

struct ClaudeUsageResponse: Codable, Equatable {
    let fiveHour: ClaudeUsageWindow
    let sevenDay: ClaudeUsageWindow
    let sevenDayOpus: ClaudeUsageWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
    }
}

protocol ClaudeUsageFetching {
    func fetchUsage(accessToken: String) async throws -> ClaudeUsageResponse
}

enum ClaudeUsageError: Error {
    case badResponse(Int?)
}

final class ClaudeUsageAPIClient: ClaudeUsageFetching {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func fetchUsage(accessToken: String) async throws -> ClaudeUsageResponse {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("Claude-Code/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ClaudeUsageError.badResponse((response as? HTTPURLResponse)?.statusCode)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ClaudeUsageResponse.self, from: data)
    }
}
```

- [ ] **Step 6: Implement `ClaudeUsageProvider`**

```swift
// Sources/OkTally/Plugins/Claude/ClaudeUsageProvider.swift
import Foundation

final class ClaudeUsageProvider: UsageProvider {
    let id = "claude"
    let displayName = "Claude Code"
    let authMethod: AuthMethod = .keychain(service: "Claude Code-credentials")
    let refreshInterval: TimeInterval = 60

    private let credentialProvider: ClaudeCredentialProvider
    private let apiClient: ClaudeUsageFetching

    init(
        credentialProvider: ClaudeCredentialProvider = ClaudeCredentialProvider(),
        apiClient: ClaudeUsageFetching = ClaudeUsageAPIClient()
    ) {
        self.credentialProvider = credentialProvider
        self.apiClient = apiClient
    }

    func isAuthenticated() async -> Bool {
        (try? credentialProvider.loadCredentials()) != nil
    }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        let credentials = try credentialProvider.loadCredentials()
        let usage = try await apiClient.fetchUsage(accessToken: credentials.accessToken)

        var quotas = [
            QuotaWindow(label: "5h", shape: .rollingWindow(
                used: usage.fiveHour.utilization, limit: 100,
                windowStart: usage.fiveHour.resetsAt.addingTimeInterval(-5 * 3600),
                resetAt: usage.fiveHour.resetsAt
            )),
            QuotaWindow(label: "weekly", shape: .rollingWindow(
                used: usage.sevenDay.utilization, limit: 100,
                windowStart: usage.sevenDay.resetsAt.addingTimeInterval(-7 * 24 * 3600),
                resetAt: usage.sevenDay.resetsAt
            ))
        ]
        if let opus = usage.sevenDayOpus {
            quotas.append(QuotaWindow(label: "weekly-opus", shape: .rollingWindow(
                used: opus.utilization, limit: 100,
                windowStart: opus.resetsAt.addingTimeInterval(-7 * 24 * 3600),
                resetAt: opus.resetsAt
            )))
        }
        return ProviderSnapshot(providerId: id, fetchedAt: Date(), quotas: quotas, usageDetail: nil)
    }
}
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `swift test --filter ClaudeUsageProviderTests`
Expected: PASS, 4 tests executed.

- [ ] **Step 8: Run the full suite**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 9: Commit**

```bash
git add Sources/OkTally/Plugins/Claude/ClaudeUsageAPIClient.swift Sources/OkTally/Plugins/Claude/ClaudeUsageProvider.swift Tests/OkTallyTests/ClaudeUsageProviderTests.swift Tests/OkTallyTests/Fixtures/claude_usage_response.json
git commit -m "feat: add Claude usage API client and plugin"
```

---

### Task 10: OpenRouter usage plugin

**Files:**
- Create: `Sources/OkTally/Plugins/OpenRouter/OpenRouterAPIClient.swift`
- Create: `Sources/OkTally/Plugins/OpenRouter/OpenRouterUsageProvider.swift`
- Test: `Tests/OkTallyTests/OpenRouterUsageProviderTests.swift`
- Test fixture: `Tests/OkTallyTests/Fixtures/openrouter_credits_response.json`

**Interfaces:**
- Consumes: `UsageProvider`, `ProviderSnapshot`, `QuotaWindow`, `QuotaShape` (Task 2), `URLProtocolStub` (Task 5).
- Produces: `OpenRouterCreditsResponse` (struct decoding `{"data": {"total_credits": Double, "total_usage": Double}}`), `OpenRouterCreditsFetching` protocol (`func fetchCredits(apiKey: String) async throws -> OpenRouterCreditsResponse`), `OpenRouterAPIClient: OpenRouterCreditsFetching`, `OpenRouterError` (enum: `.badResponse(Int?)`, `.missingAPIKey`), `OpenRouterUsageProvider: UsageProvider` (`id = "openrouter"`, `init(apiKeyProvider: @escaping () -> String?, creditsClient: OpenRouterCreditsFetching = OpenRouterAPIClient())`). Registered into `PluginRegistry` in Task 14, `apiKeyProvider` supplied by `PreferencesStore` (Task 11).

- [ ] **Step 1: Create the fixture file**

```json
// Tests/OkTallyTests/Fixtures/openrouter_credits_response.json
{ "data": { "total_credits": 50.0, "total_usage": 12.5 } }
```

- [ ] **Step 2: Write the failing test**

```swift
// Tests/OkTallyTests/OpenRouterUsageProviderTests.swift
import XCTest
@testable import OkTally

final class FakeOpenRouterCreditsFetching: OpenRouterCreditsFetching {
    var responseToReturn: OpenRouterCreditsResponse!
    func fetchCredits(apiKey: String) async throws -> OpenRouterCreditsResponse { responseToReturn }
}

final class OpenRouterUsageProviderTests: XCTestCase {
    func test_fetchSnapshot_computesRemainingBalance() async throws {
        let fetcher = FakeOpenRouterCreditsFetching()
        fetcher.responseToReturn = OpenRouterCreditsResponse(data: .init(totalCredits: 50, totalUsage: 12.5))
        let provider = OpenRouterUsageProvider(apiKeyProvider: { "key123" }, creditsClient: fetcher)

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.providerId, "openrouter")
        XCTAssertEqual(snapshot.quotas.count, 1)
        guard case .creditBalance(let remaining, let currency) = snapshot.quotas[0].shape else {
            return XCTFail("expected creditBalance shape")
        }
        XCTAssertEqual(remaining, 37.5)
        XCTAssertEqual(currency, "USD")
    }

    func test_fetchSnapshot_withoutAPIKey_throwsMissingAPIKey() async {
        let provider = OpenRouterUsageProvider(apiKeyProvider: { nil }, creditsClient: FakeOpenRouterCreditsFetching())

        do {
            _ = try await provider.fetchSnapshot()
            XCTFail("expected to throw")
        } catch OpenRouterError.missingAPIKey {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func test_isAuthenticated_reflectsAPIKeyPresence() async {
        let withKey = OpenRouterUsageProvider(apiKeyProvider: { "key" }, creditsClient: FakeOpenRouterCreditsFetching())
        let withoutKey = OpenRouterUsageProvider(apiKeyProvider: { nil }, creditsClient: FakeOpenRouterCreditsFetching())

        let a = await withKey.isAuthenticated()
        let b = await withoutKey.isAuthenticated()

        XCTAssertTrue(a)
        XCTAssertFalse(b)
    }

    func test_apiClient_decodesFixture() async throws {
        let fixtureURL = Bundle.module.url(forResource: "openrouter_credits_response", withExtension: "json")!
        let data = try Data(contentsOf: fixtureURL)
        URLProtocolStub.stubResponses[URL(string: "https://openrouter.ai/api/v1/credits")!] = (data, 200)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: config)

        let client = OpenRouterAPIClient(session: session)
        let response = try await client.fetchCredits(apiKey: "key123")

        XCTAssertEqual(response.data.totalCredits, 50.0)
        XCTAssertEqual(response.data.totalUsage, 12.5)
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail to compile**

Run: `swift test --filter OpenRouterUsageProviderTests`
Expected: FAIL — `cannot find type 'OpenRouterCreditsResponse' in scope`.

- [ ] **Step 4: Implement `OpenRouterAPIClient`**

```swift
// Sources/OkTally/Plugins/OpenRouter/OpenRouterAPIClient.swift
import Foundation

struct OpenRouterCreditsResponse: Codable, Equatable {
    struct DataField: Codable, Equatable {
        let totalCredits: Double
        let totalUsage: Double
        enum CodingKeys: String, CodingKey {
            case totalCredits = "total_credits"
            case totalUsage = "total_usage"
        }
    }
    let data: DataField
}

protocol OpenRouterCreditsFetching {
    func fetchCredits(apiKey: String) async throws -> OpenRouterCreditsResponse
}

enum OpenRouterError: Error, Equatable {
    case badResponse(Int?)
    case missingAPIKey
}

final class OpenRouterAPIClient: OpenRouterCreditsFetching {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func fetchCredits(apiKey: String) async throws -> OpenRouterCreditsResponse {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/credits")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw OpenRouterError.badResponse((response as? HTTPURLResponse)?.statusCode)
        }
        return try JSONDecoder().decode(OpenRouterCreditsResponse.self, from: data)
    }
}
```

- [ ] **Step 5: Implement `OpenRouterUsageProvider`**

```swift
// Sources/OkTally/Plugins/OpenRouter/OpenRouterUsageProvider.swift
import Foundation

final class OpenRouterUsageProvider: UsageProvider {
    let id = "openrouter"
    let displayName = "OpenRouter"
    let authMethod: AuthMethod = .apiKey
    let refreshInterval: TimeInterval = 600

    private let apiKeyProvider: () -> String?
    private let creditsClient: OpenRouterCreditsFetching

    init(apiKeyProvider: @escaping () -> String?, creditsClient: OpenRouterCreditsFetching = OpenRouterAPIClient()) {
        self.apiKeyProvider = apiKeyProvider
        self.creditsClient = creditsClient
    }

    func isAuthenticated() async -> Bool {
        apiKeyProvider() != nil
    }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        guard let apiKey = apiKeyProvider() else { throw OpenRouterError.missingAPIKey }
        let response = try await creditsClient.fetchCredits(apiKey: apiKey)
        let remaining = Decimal(response.data.totalCredits - response.data.totalUsage)
        let window = QuotaWindow(label: "balance", shape: .creditBalance(remaining: remaining, currency: "USD"))
        return ProviderSnapshot(providerId: id, fetchedAt: Date(), quotas: [window], usageDetail: nil)
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --filter OpenRouterUsageProviderTests`
Expected: PASS, 4 tests executed.

- [ ] **Step 7: Run the full suite**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 8: Commit**

```bash
git add Sources/OkTally/Plugins/OpenRouter Tests/OkTallyTests/OpenRouterUsageProviderTests.swift Tests/OkTallyTests/Fixtures/openrouter_credits_response.json
git commit -m "feat: add OpenRouter usage plugin"
```

---

### Task 11: Preferences store

**Files:**
- Create: `Sources/OkTally/Preferences/PreferencesStore.swift`
- Test: `Tests/OkTallyTests/PreferencesStoreTests.swift`

**Interfaces:**
- Consumes: nothing beyond Foundation.
- Produces: `KeyValueStore` protocol (`func string(forKey:) -> String?`, `func set(_:forKey:)` for `String?`, `func double(forKey:) -> Double`, `func set(_:forKey:)` for `Double`), `UserDefaults: KeyValueStore` (extension), `PreferencesStore` (class: `init(store: KeyValueStore = UserDefaults.standard)`, `var openRouterAPIKey: String?`, `func refreshInterval(for providerId: String, default: TimeInterval) -> TimeInterval`, `func setRefreshInterval(_ interval: TimeInterval, for providerId: String)`). Task 14 constructs `OpenRouterUsageProvider`'s `apiKeyProvider` closure from `preferencesStore.openRouterAPIKey`, and the Preferences UI (Task 14) reads/writes through this store.

- [ ] **Step 1: Write the failing test using an in-memory fake store**

```swift
// Tests/OkTallyTests/PreferencesStoreTests.swift
import XCTest
@testable import OkTally

final class FakeKeyValueStore: KeyValueStore {
    private var strings: [String: String] = [:]
    private var doubles: [String: Double] = [:]

    func string(forKey key: String) -> String? { strings[key] }
    func set(_ value: String?, forKey key: String) { strings[key] = value }
    func double(forKey key: String) -> Double { doubles[key] ?? 0 }
    func set(_ value: Double, forKey key: String) { doubles[key] = value }
}

final class PreferencesStoreTests: XCTestCase {
    func test_openRouterAPIKey_roundTrips() {
        let store = PreferencesStore(store: FakeKeyValueStore())
        XCTAssertNil(store.openRouterAPIKey)

        store.openRouterAPIKey = "sk-or-123"

        XCTAssertEqual(store.openRouterAPIKey, "sk-or-123")
    }

    func test_refreshInterval_returnsDefaultWhenUnset() {
        let store = PreferencesStore(store: FakeKeyValueStore())
        XCTAssertEqual(store.refreshInterval(for: "claude", default: 60), 60)
    }

    func test_refreshInterval_returnsStoredValueAfterSet() {
        let store = PreferencesStore(store: FakeKeyValueStore())
        store.setRefreshInterval(120, for: "claude")
        XCTAssertEqual(store.refreshInterval(for: "claude", default: 60), 120)
    }

    func test_refreshInterval_isPerProvider() {
        let store = PreferencesStore(store: FakeKeyValueStore())
        store.setRefreshInterval(120, for: "claude")
        XCTAssertEqual(store.refreshInterval(for: "openrouter", default: 600), 600)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail to compile**

Run: `swift test --filter PreferencesStoreTests`
Expected: FAIL — `cannot find type 'PreferencesStore' in scope`.

- [ ] **Step 3: Implement `PreferencesStore`**

```swift
// Sources/OkTally/Preferences/PreferencesStore.swift
import Foundation

protocol KeyValueStore {
    func string(forKey key: String) -> String?
    func set(_ value: String?, forKey key: String)
    func double(forKey key: String) -> Double
    func set(_ value: Double, forKey key: String)
}

extension UserDefaults: KeyValueStore {}

final class PreferencesStore {
    private let store: KeyValueStore

    private enum Keys {
        static let openRouterAPIKey = "openRouterAPIKey"
        static func refreshInterval(_ providerId: String) -> String { "refreshInterval.\(providerId)" }
    }

    init(store: KeyValueStore = UserDefaults.standard) {
        self.store = store
    }

    var openRouterAPIKey: String? {
        get { store.string(forKey: Keys.openRouterAPIKey) }
        set { store.set(newValue, forKey: Keys.openRouterAPIKey) }
    }

    func refreshInterval(for providerId: String, default defaultValue: TimeInterval) -> TimeInterval {
        let stored = store.double(forKey: Keys.refreshInterval(providerId))
        return stored > 0 ? stored : defaultValue
    }

    func setRefreshInterval(_ interval: TimeInterval, for providerId: String) {
        store.set(interval, forKey: Keys.refreshInterval(providerId))
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter PreferencesStoreTests`
Expected: PASS, 4 tests executed.

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/OkTally/Preferences/PreferencesStore.swift Tests/OkTallyTests/PreferencesStoreTests.swift
git commit -m "feat: add UserDefaults-backed PreferencesStore"
```

---

### Task 12: Menu bar state calculator and quota display formatter

**Files:**
- Create: `Sources/OkTally/UI/MenuBarStateCalculator.swift`
- Create: `Sources/OkTally/UI/QuotaDisplayFormatter.swift`
- Test: `Tests/OkTallyTests/MenuBarStateCalculatorTests.swift`
- Test: `Tests/OkTallyTests/QuotaDisplayFormatterTests.swift`

**Interfaces:**
- Consumes: `ProviderSnapshot`, `QuotaWindow`, `QuotaShape` (Task 2).
- Produces: `MenuBarState` (struct: `percent: Double?`, `hasError: Bool`), `MenuBarStateCalculator` (enum: `static func worstState(snapshots: [ProviderSnapshot], hasAnyError: Bool) -> MenuBarState`, `static func colorName(for state: MenuBarState) -> String`, `static func labelText(for state: MenuBarState) -> String`), `QuotaDisplayFormatter` (enum: `static func valueText(for shape: QuotaShape) -> String`). Task 13's `PopoverView`/label and Task 14's `AppModel` depend on these.

- [ ] **Step 1: Write the failing tests for `MenuBarStateCalculator`**

```swift
// Tests/OkTallyTests/MenuBarStateCalculatorTests.swift
import XCTest
@testable import OkTally

final class MenuBarStateCalculatorTests: XCTestCase {
    private func snapshot(percent: Double) -> ProviderSnapshot {
        ProviderSnapshot(
            providerId: "p",
            fetchedAt: Date(),
            quotas: [QuotaWindow(label: "w", shape: .rollingWindow(used: percent, limit: 100, windowStart: Date(), resetAt: Date()))],
            usageDetail: nil
        )
    }

    func test_worstState_picksHighestPercentAcrossSnapshots() {
        let state = MenuBarStateCalculator.worstState(snapshots: [snapshot(percent: 30), snapshot(percent: 82)], hasAnyError: false)
        XCTAssertEqual(state.percent, 82)
    }

    func test_worstState_noSnapshots_noPercent() {
        let state = MenuBarStateCalculator.worstState(snapshots: [], hasAnyError: false)
        XCTAssertNil(state.percent)
    }

    func test_colorName_thresholds() {
        XCTAssertEqual(MenuBarStateCalculator.colorName(for: MenuBarState(percent: 50, hasError: false)), "green")
        XCTAssertEqual(MenuBarStateCalculator.colorName(for: MenuBarState(percent: 75, hasError: false)), "yellow")
        XCTAssertEqual(MenuBarStateCalculator.colorName(for: MenuBarState(percent: 95, hasError: false)), "red")
        XCTAssertEqual(MenuBarStateCalculator.colorName(for: MenuBarState(percent: nil, hasError: false)), "green")
        XCTAssertEqual(MenuBarStateCalculator.colorName(for: MenuBarState(percent: nil, hasError: true)), "gray")
    }

    func test_labelText_formatsPercentOrFallback() {
        XCTAssertEqual(MenuBarStateCalculator.labelText(for: MenuBarState(percent: 82.6, hasError: false)), "83%")
        XCTAssertEqual(MenuBarStateCalculator.labelText(for: MenuBarState(percent: nil, hasError: false)), "OK")
        XCTAssertEqual(MenuBarStateCalculator.labelText(for: MenuBarState(percent: nil, hasError: true)), "!")
    }
}
```

- [ ] **Step 2: Write the failing tests for `QuotaDisplayFormatter`**

```swift
// Tests/OkTallyTests/QuotaDisplayFormatterTests.swift
import XCTest
@testable import OkTally

final class QuotaDisplayFormatterTests: XCTestCase {
    func test_rollingWindow_showsPercent() {
        let shape = QuotaShape.rollingWindow(used: 42, limit: 100, windowStart: Date(), resetAt: Date())
        XCTAssertEqual(QuotaDisplayFormatter.valueText(for: shape), "42%")
    }

    func test_creditBalance_showsAmountAndCurrency() {
        let shape = QuotaShape.creditBalance(remaining: 37.5, currency: "USD")
        XCTAssertEqual(QuotaDisplayFormatter.valueText(for: shape), "37.5 USD")
    }

    func test_meteredOnly_showsDollarCost() {
        let shape = QuotaShape.meteredOnly(costAccrued: 3.2)
        XCTAssertEqual(QuotaDisplayFormatter.valueText(for: shape), "$3.2")
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail to compile**

Run: `swift test --filter MenuBarStateCalculatorTests`
Expected: FAIL — `cannot find 'MenuBarStateCalculator' in scope`.

- [ ] **Step 4: Implement `MenuBarStateCalculator`**

```swift
// Sources/OkTally/UI/MenuBarStateCalculator.swift
import Foundation

struct MenuBarState: Equatable {
    let percent: Double?
    let hasError: Bool
}

enum MenuBarStateCalculator {
    static func worstState(snapshots: [ProviderSnapshot], hasAnyError: Bool) -> MenuBarState {
        let percents = snapshots.flatMap { $0.quotas.compactMap { $0.shape.usedPercent } }
        return MenuBarState(percent: percents.max(), hasError: hasAnyError)
    }

    static func colorName(for state: MenuBarState) -> String {
        guard let percent = state.percent else { return state.hasError ? "gray" : "green" }
        if percent >= 90 { return "red" }
        if percent >= 70 { return "yellow" }
        return "green"
    }

    static func labelText(for state: MenuBarState) -> String {
        guard let percent = state.percent else { return state.hasError ? "!" : "OK" }
        return "\(Int(percent.rounded()))%"
    }
}
```

- [ ] **Step 5: Implement `QuotaDisplayFormatter`**

```swift
// Sources/OkTally/UI/QuotaDisplayFormatter.swift
import Foundation

enum QuotaDisplayFormatter {
    static func valueText(for shape: QuotaShape) -> String {
        if let percent = shape.usedPercent {
            return "\(Int(percent.rounded()))%"
        }
        switch shape {
        case .creditBalance(let remaining, let currency):
            return "\(remaining) \(currency)"
        case .meteredOnly(let cost):
            return "$\(cost)"
        default:
            return ""
        }
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --filter MenuBarStateCalculatorTests`
Run: `swift test --filter QuotaDisplayFormatterTests`
Expected: both PASS (4 and 3 tests respectively).

- [ ] **Step 7: Run the full suite**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 8: Commit**

```bash
git add Sources/OkTally/UI/MenuBarStateCalculator.swift Sources/OkTally/UI/QuotaDisplayFormatter.swift Tests/OkTallyTests/MenuBarStateCalculatorTests.swift Tests/OkTallyTests/QuotaDisplayFormatterTests.swift
git commit -m "feat: add menu bar state and quota display formatting logic"
```

---

### Task 13: AppModel and popover UI

**Files:**
- Create: `Sources/OkTally/App/AppModel.swift`
- Create: `Sources/OkTally/UI/QuotaBarView.swift`
- Create: `Sources/OkTally/UI/ProviderCardView.swift`
- Create: `Sources/OkTally/UI/PopoverView.swift`
- Test: `Tests/OkTallyTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `PluginRegistry`, `Scheduler`, `SchedulerFetchResult` (Task 7), `MenuBarStateCalculator`, `MenuBarState`, `QuotaDisplayFormatter` (Task 12), `UsageProvider`, `ProviderSnapshot` (Task 2).
- Produces: `AppModel` (`@MainActor final class`, `ObservableObject`: `init(registry: PluginRegistry, scheduler: Scheduler)`, `@Published private(set) var snapshotsByProvider: [String: ProviderSnapshot]`, `@Published private(set) var errorsByProvider: [String: String]`, `func start()`, `func refreshNow() async`, `var menuBarState: MenuBarState`, `var orderedProviders: [UsageProvider]`), plus `QuotaBarView`, `ProviderCardView`, `PopoverView` SwiftUI views. Task 14 constructs the real `AppModel` and wires it into `OkTallyApp`'s `MenuBarExtra`/`Settings` scenes.

- [ ] **Step 1: Write the failing test for `AppModel`'s result handling (no SwiftUI involved)**

```swift
// Tests/OkTallyTests/AppModelTests.swift
import XCTest
@testable import OkTally

@MainActor
final class AppModelTests: XCTestCase {
    func test_refreshNow_populatesSnapshotsAndErrors() async {
        let good = FakeUsageProvider(id: "openrouter", displayName: "OpenRouter")
        good.snapshotToReturn = ProviderSnapshot(providerId: "openrouter", fetchedAt: Date(), quotas: [], usageDetail: nil)
        let bad = FakeUsageProvider(id: "claude", displayName: "Claude Code")
        bad.errorToThrow = FakeError.boom
        let registry = PluginRegistry()
        registry.register(good)
        registry.register(bad)
        let scheduler = Scheduler(
            registry: registry,
            storage: FakeStorage(),
            alertEngine: AlertEngine(),
            alertDispatcher: AlertDispatcher(sender: FakeNotificationSender())
        )
        let model = AppModel(registry: registry, scheduler: scheduler)

        await model.refreshNow()

        XCTAssertNotNil(model.snapshotsByProvider["openrouter"])
        XCTAssertNotNil(model.errorsByProvider["claude"])
    }

    func test_menuBarState_reflectsWorstSnapshot() async {
        let provider = FakeUsageProvider(id: "claude", displayName: "Claude Code")
        provider.snapshotToReturn = ProviderSnapshot(
            providerId: "claude",
            fetchedAt: Date(),
            quotas: [QuotaWindow(label: "5h", shape: .rollingWindow(used: 88, limit: 100, windowStart: Date(), resetAt: Date()))],
            usageDetail: nil
        )
        let registry = PluginRegistry()
        registry.register(provider)
        let scheduler = Scheduler(
            registry: registry,
            storage: FakeStorage(),
            alertEngine: AlertEngine(),
            alertDispatcher: AlertDispatcher(sender: FakeNotificationSender())
        )
        let model = AppModel(registry: registry, scheduler: scheduler)

        await model.refreshNow()

        XCTAssertEqual(model.menuBarState.percent, 88)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail to compile**

Run: `swift test --filter AppModelTests`
Expected: FAIL — `cannot find type 'AppModel' in scope`.

- [ ] **Step 3: Implement `AppModel`**

```swift
// Sources/OkTally/App/AppModel.swift
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshotsByProvider: [String: ProviderSnapshot] = [:]
    @Published private(set) var errorsByProvider: [String: String] = [:]

    private let registry: PluginRegistry
    private let scheduler: Scheduler

    init(registry: PluginRegistry, scheduler: Scheduler) {
        self.registry = registry
        self.scheduler = scheduler
        scheduler.onResult = { [weak self] result in
            Task { @MainActor in self?.apply(result) }
        }
    }

    func start() {
        scheduler.startPeriodicLoop()
    }

    func refreshNow() async {
        _ = await scheduler.fetchAll()
    }

    var menuBarState: MenuBarState {
        MenuBarStateCalculator.worstState(
            snapshots: Array(snapshotsByProvider.values),
            hasAnyError: !errorsByProvider.isEmpty
        )
    }

    var orderedProviders: [UsageProvider] { registry.providers }

    private func apply(_ result: SchedulerFetchResult) {
        switch result.outcome {
        case .success(let snapshot):
            snapshotsByProvider[result.providerId] = snapshot
            errorsByProvider[result.providerId] = nil
        case .failure(let error):
            errorsByProvider[result.providerId] = error.localizedDescription
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter AppModelTests`
Expected: PASS, 2 tests executed.

- [ ] **Step 5: Implement the SwiftUI views (no automated test — pure layout, verified manually in Task 14)**

```swift
// Sources/OkTally/UI/QuotaBarView.swift
import SwiftUI

struct QuotaBarView: View {
    let window: QuotaWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(window.label)
                    .font(.caption)
                Spacer()
                Text(QuotaDisplayFormatter.valueText(for: window.shape))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let percent = window.shape.usedPercent {
                ProgressView(value: min(percent, 100), total: 100)
            }
        }
    }
}
```

```swift
// Sources/OkTally/UI/ProviderCardView.swift
import SwiftUI

struct ProviderCardView: View {
    let provider: UsageProvider
    let snapshot: ProviderSnapshot?
    let errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(provider.displayName)
                .font(.headline)
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if let snapshot {
                ForEach(snapshot.quotas, id: \.label) { window in
                    QuotaBarView(window: window)
                }
            } else {
                Text("Carregando…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
    }
}
```

```swift
// Sources/OkTally/UI/PopoverView.swift
import SwiftUI

struct PopoverView: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(appModel.orderedProviders, id: \.id) { provider in
                ProviderCardView(
                    provider: provider,
                    snapshot: appModel.snapshotsByProvider[provider.id],
                    errorMessage: appModel.errorsByProvider[provider.id]
                )
                Divider()
            }
            Button("Atualizar agora") {
                Task { await appModel.refreshNow() }
            }
            Button("Preferências…") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            Button("Sair") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 260)
    }
}
```

Note: `showSettingsWindow:` is the AppKit selector SwiftUI's `Settings` scene registers under on macOS 13/14 (before the `SettingsLink` view existed); since `OkTallyApp` has `LSUIElement` set, there is no Dock menu to open Preferences from otherwise, so this button is the only entry point.

- [ ] **Step 6: Run the full suite**

Run: `swift test`
Expected: all tests pass (the new SwiftUI files add no tests but must compile).

- [ ] **Step 7: Commit**

```bash
git add Sources/OkTally/App/AppModel.swift Sources/OkTally/UI/QuotaBarView.swift Sources/OkTally/UI/ProviderCardView.swift Sources/OkTally/UI/PopoverView.swift Tests/OkTallyTests/AppModelTests.swift
git commit -m "feat: add AppModel and popover UI"
```

---

### Task 14: Preferences UI and end-to-end wiring

**Files:**
- Create: `Sources/OkTally/UI/PreferencesView.swift`
- Modify: `Sources/OkTally/App/OkTallyApp.swift` (replace the Task 1 placeholder body entirely)

**Interfaces:**
- Consumes: `PreferencesStore` (Task 11), `AppModel` (Task 13), `PluginRegistry`, `Scheduler` (Task 7), `SQLiteStorage` (Task 6), `AlertEngine` (Task 3), `AlertDispatcher`, `UNNotificationSender` (Task 4), `ClaudeUsageProvider` (Task 9), `OpenRouterUsageProvider` (Task 10), `MenuBarStateCalculator` (Task 12).
- Produces: `PreferencesView` (SwiftUI), and the fully wired `OkTallyApp` — the terminal deliverable of this plan.

- [ ] **Step 1: Implement `PreferencesView`**

```swift
// Sources/OkTally/UI/PreferencesView.swift
import SwiftUI

struct PreferencesView: View {
    let preferencesStore: PreferencesStore
    @State private var openRouterAPIKey: String = ""

    var body: some View {
        Form {
            Section("OpenRouter") {
                SecureField("API Key", text: $openRouterAPIKey)
                Button("Salvar") {
                    preferencesStore.openRouterAPIKey = openRouterAPIKey
                }
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            openRouterAPIKey = preferencesStore.openRouterAPIKey ?? ""
        }
    }
}
```

- [ ] **Step 2: Replace `OkTallyApp` with the fully wired version**

```swift
// Sources/OkTally/App/OkTallyApp.swift
import SwiftUI

@main
struct OkTallyApp: App {
    @StateObject private var appModel: AppModel
    private let preferencesStore = PreferencesStore()

    init() {
        let appSupportDir = NSHomeDirectory() + "/Library/Application Support/OkTally"
        try? FileManager.default.createDirectory(atPath: appSupportDir, withIntermediateDirectories: true)

        let registry = PluginRegistry()
        let preferencesStore = PreferencesStore()
        let storage = try! SQLiteStorage(path: appSupportDir + "/usage.sqlite")
        let alertEngine = AlertEngine()
        let notificationSender = UNNotificationSender()
        let alertDispatcher = AlertDispatcher(sender: notificationSender)
        let scheduler = Scheduler(
            registry: registry,
            storage: storage,
            alertEngine: alertEngine,
            alertDispatcher: alertDispatcher,
            thresholdsProvider: { _ in [:] }
        )

        registry.register(ClaudeUsageProvider())
        registry.register(OpenRouterUsageProvider(apiKeyProvider: { preferencesStore.openRouterAPIKey }))

        let model = AppModel(registry: registry, scheduler: scheduler)
        _appModel = StateObject(wrappedValue: model)

        Task { await notificationSender.requestAuthorizationIfNeeded() }
        model.start()
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(appModel: appModel)
        } label: {
            Text(MenuBarStateCalculator.labelText(for: appModel.menuBarState))
                .foregroundStyle(Self.color(for: MenuBarStateCalculator.colorName(for: appModel.menuBarState)))
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView(preferencesStore: preferencesStore)
        }
    }

    private static func color(for colorName: String) -> Color {
        switch colorName {
        case "red": return .red
        case "yellow": return .yellow
        case "gray": return .gray
        default: return .green
        }
    }
}
```

- [ ] **Step 3: Run the full test suite**

Run: `swift test`
Expected: all tests from Tasks 1–13 still pass (this task adds no new automated tests — it is integration wiring, verified manually in Step 5).

- [ ] **Step 4: Rebuild the app bundle**

Run: `./Scripts/build_app.sh`
Expected: `Built .build/OkTally.app`, no errors.

- [ ] **Step 5: Manual end-to-end verification**

Prerequisite: you are logged into Claude Code (`claude` CLI) on this machine, and you have an OpenRouter API key.

1. Run: `open .build/OkTally.app`
2. The first time it runs, macOS shows a Keychain access prompt naming "OkTally" asking to read the "Claude Code-credentials" item — click **Always Allow** (or **Allow**).
3. macOS also prompts for notification permission — click **Allow**.
4. Click the menu bar item. Expected: a popover opens showing a "Claude Code" card with 2–3 quota bars (5h, weekly, and weekly-opus if applicable) showing real percentages that roughly match what `claude`'s `/usage` command reports, and an "OpenRouter" card showing "Carregando…" (no API key configured yet).
5. Click "Preferências…" in the popover. Expected: a Settings window opens. Enter your OpenRouter API key, click "Salvar", close the window.
6. Click "Atualizar agora" in the popover. Expected: the OpenRouter card now shows a "balance" bar with your real remaining credit.
7. Confirm the menu bar label's color matches the worst percentage across both providers' rolling/periodic windows (green under 70%, yellow 70–90%, red 90%+; ignore OpenRouter's balance, since `creditBalance` doesn't contribute a percent).
8. To verify alerting end-to-end without waiting for real usage: temporarily change `AlertThreshold.defaultPercentageThresholds` in `Sources/OkTally/Core/AlertThreshold.swift` to include a threshold below your current Claude 5h usage (e.g. `.percentage(0.01)`), rebuild, relaunch, and click "Atualizar agora" — expect a native macOS notification titled "Claude Code — 5h" to appear. Revert the threshold change afterward and rebuild.

- [ ] **Step 6: Register a LaunchAgent so OkTally starts on login**

```xml
<!-- Resources/com.oktally.app.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.oktally.app</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-a</string>
        <string>OkTally</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
```

```bash
# Scripts/install_launch_agent.sh
#!/bin/bash
set -euo pipefail
mkdir -p ~/Library/LaunchAgents
cp Resources/com.oktally.app.plist ~/Library/LaunchAgents/com.oktally.app.plist
launchctl unload ~/Library/LaunchAgents/com.oktally.app.plist 2>/dev/null || true
launchctl load ~/Library/LaunchAgents/com.oktally.app.plist
echo "LaunchAgent installed — OkTally will now start on login."
```

```bash
chmod +x Scripts/install_launch_agent.sh
```

This script is provided but **not run automatically** — running it moves `.build/OkTally.app` to `/Applications` first is a reasonable prerequisite the reader should do manually (`cp -R .build/OkTally.app /Applications/`), since `open -a OkTally` resolves by app name via Spotlight's index, which only reliably finds apps under standard app directories.

- [ ] **Step 7: Run the full test suite one more time**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 8: Commit**

```bash
git add Sources/OkTally/UI/PreferencesView.swift Sources/OkTally/App/OkTallyApp.swift Resources/com.oktally.app.plist Scripts/install_launch_agent.sh
git commit -m "feat: wire Preferences UI, apply menu bar color, add LaunchAgent installer"
```

---

## Known Limitations (deferred, not gaps to silently ignore)

- **Codex CLI, Cursor Pro, MiniMax, MiMo, OpenCode Zen/Go plugins** are not part of this plan — their usage/balance endpoints are marked "to be confirmed during implementation" in the design spec and will be researched and built in a follow-on plan, reusing the `UsageProvider` pattern proven here by Claude and OpenRouter.
- **Cost estimation is not yet visible anywhere.** `PricingEngine` and `OpenRouterPricingSource` (Task 5) are fully implemented and tested, but nothing in this plan wires them into `AppModel` or the popover, because no v1 plugin populates `ProviderSnapshot.usageDetail` (OpenRouter's `/credits` endpoint reports balance, not per-model token counts). Wiring this in is straightforward once a plugin supplies `UsageDetail` — likely one of the Plan 2 providers, or a future enhancement to pull per-model usage from OpenRouter's `/generation` endpoint.
- **No trend/sparkline view.** `SQLiteStorage.snapshots(providerId:since:)` (Task 6) already supports querying history, but no task in this plan builds a chart from it — the popover only shows the latest snapshot per provider.
- **Refresh interval is not yet user-configurable from the UI.** `PreferencesStore.refreshInterval(for:default:)` (Task 11) exists, but `PreferencesView` (Task 14) only exposes the OpenRouter API key field — a refresh-interval control is a small follow-up.
