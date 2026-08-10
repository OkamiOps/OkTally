# Interface Redesign + MiMo Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Colored multi-pin menu bar label, gauge-based popover, sidebar Preferences, and a MiMo web session that self-recovers from STS expiry instead of demanding relogin.

**Architecture:** Pure presentation models (`MenuBarLabelModel`, recovery policy `MiMoSessionRecovery`) carry all logic and tests; SwiftUI views stay thin. The menu bar label becomes a non-template `NSImage` rendered via `ImageRenderer` because `MenuBarExtra` strips `foregroundStyle` from text labels.

**Tech Stack:** Swift 5 / SwiftUI / SPM, XCTest. macOS 13+ (`ImageRenderer` requires 13).

## Global Constraints

- All user-facing copy in Portuguese (existing convention: "restante", "Reseta em…", "Conectado").
- Danger thresholds (remaining fraction): `>0.30` green, `≤0.30` orange, `≤0.10` red — must match `QuotaPresentation.color(remaining:)`.
- The menu bar shows **% restante** (not % usado) — consistent with the dropdown copy.
- Spec deviation (approved during planning): refresh-interval UI is cut from the "Geral" pane because `PreferencesStore.refreshInterval` is not wired into `Scheduler` (it reads `provider.refreshInterval` directly). Geral manages pins only.

---

### Task 1: MiMo session recovery policy (the relogin fix)

**Files:**
- Create: `Sources/OkTally/Plugins/MiMo/MiMoSessionRecovery.swift`
- Modify: `Sources/OkTally/Plugins/MiMo/MiMoWebSession.swift` (replace blind 6×2s retry with recovery policy; add `reloadConsole()`)
- Test: `Tests/OkTallyTests/MiMoSessionRecoveryTests.swift`

**Interfaces:**
- Produces: `struct MiMoSessionRecovery { init(fetch: @escaping () async throws -> Data, reload: @escaping () async throws -> Void); func fetchWithRecovery() async throws -> Data }` — throws `MiMoConsoleError.notLoggedIn` only when a fetch *after* reload still returns `"code":401`.
- Consumes: `MiMoConsoleError` (exists).

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import OkTally

final class MiMoSessionRecoveryTests: XCTestCase {
    private let ok = #"{"code":0,"data":{"usage":{"percent":0.5}}}"#
    private let unauthorized = #"{"code":401,"loginUrl":"https://account.xiaomi.com/x"}"#

    func test_healthySession_fetchesOnce_noReload() async throws {
        var fetches = 0, reloads = 0
        let recovery = MiMoSessionRecovery(
            fetch: { fetches += 1; return Data(self.ok.utf8) },
            reload: { reloads += 1 }
        )
        let data = try await recovery.fetchWithRecovery()
        XCTAssertEqual(String(data: data, encoding: .utf8), ok)
        XCTAssertEqual(fetches, 1)
        XCTAssertEqual(reloads, 0)
    }

    func test_expiredSTS_reloadsConsole_thenSucceeds() async throws {
        var fetches = 0, reloads = 0
        let recovery = MiMoSessionRecovery(
            fetch: { fetches += 1; return Data((fetches == 1 ? self.unauthorized : self.ok).utf8) },
            reload: { reloads += 1 }
        )
        let data = try await recovery.fetchWithRecovery()
        XCTAssertEqual(String(data: data, encoding: .utf8), ok)
        XCTAssertEqual(fetches, 2)
        XCTAssertEqual(reloads, 1, "401 must trigger exactly one console reload (SSO → new STS)")
    }

    func test_deadSSO_still401AfterReload_throwsNotLoggedIn() async {
        var reloads = 0
        let recovery = MiMoSessionRecovery(
            fetch: { Data(self.unauthorized.utf8) },
            reload: { reloads += 1 }
        )
        do {
            _ = try await recovery.fetchWithRecovery()
            XCTFail("expected notLoggedIn")
        } catch let error as MiMoConsoleError {
            XCTAssertEqual(String(describing: error), String(describing: MiMoConsoleError.notLoggedIn))
        } catch { XCTFail("unexpected \(error)") }
        XCTAssertEqual(reloads, 1)
    }

    func test_reloadFailure_propagates() async {
        struct Boom: Error {}
        let recovery = MiMoSessionRecovery(
            fetch: { Data(self.unauthorized.utf8) },
            reload: { throw Boom() }
        )
        do { _ = try await recovery.fetchWithRecovery(); XCTFail("expected Boom") }
        catch is Boom {} catch { XCTFail("unexpected \(error)") }
    }
}
```

- [ ] **Step 2: Run tests, verify they fail** — `swift test --filter MiMoSessionRecoveryTests` → FAIL (type not defined).

- [ ] **Step 3: Implement**

```swift
// Sources/OkTally/Plugins/MiMo/MiMoSessionRecovery.swift
import Foundation

/// The STS cookie behind the MiMo console expires long before the Xiaomi SSO session
/// does. A 401 therefore usually means "stale STS", not "logged out" — reloading the
/// console page re-runs the SSO redirect chain and mints a fresh STS. Only a 401 that
/// survives that reload means the SSO itself is dead and the user must log in again.
struct MiMoSessionRecovery {
    private let fetch: () async throws -> Data
    private let reload: () async throws -> Void

    init(fetch: @escaping () async throws -> Data, reload: @escaping () async throws -> Void) {
        self.fetch = fetch
        self.reload = reload
    }

    func fetchWithRecovery() async throws -> Data {
        let first = try await fetch()
        guard isUnauthorized(first) else { return first }
        try await reload()
        let second = try await fetch()
        guard isUnauthorized(second) else { return second }
        throw MiMoConsoleError.notLoggedIn
    }

    private func isUnauthorized(_ data: Data) -> Bool {
        String(data: data, encoding: .utf8)?.contains("\"code\":401") ?? false
    }
}
```

In `MiMoWebSession`: change `ensureConsoleLoaded()` to `loadConsole()` (always navigates, resolving waiters on didFinish — drop the `everLoaded` short-circuit for forced reloads but keep a `hasLoaded` fast path for first use), add:

```swift
func fetchUsageJSON() async throws -> Data {
    let recovery = MiMoSessionRecovery(
        fetch: { [weak self] in try await self?.rawFetch() ?? Data() },
        reload: { [weak self] in try await self?.reloadConsole() }
    )
    return try await recovery.fetchWithRecovery()
}

private func rawFetch() async throws -> Data {
    try await ensureConsoleLoaded()
    let js = """
    const r = await fetch('/api/v1/tokenPlan/usage', { credentials: 'include' });
    return await r.text();
    """
    // Console SPA may still be booting right after a load; give the fetch a short
    // settling loop, but 401 is returned immediately for the recovery policy to judge.
    for attempt in 0..<3 {
        if attempt > 0 { try? await Task.sleep(nanoseconds: 1_500_000_000) }
        if let s = try await webView.callAsyncJavaScript(js, arguments: [:], in: nil, contentWorld: .page) as? String {
            return Data(s.utf8)
        }
    }
    throw MiMoConsoleError.noData
}

func reloadConsole() async throws {
    everLoaded = false
    try await ensureConsoleLoaded()
    // The SPA re-establishes STS via redirects after load; give it a beat.
    try? await Task.sleep(nanoseconds: 2_000_000_000)
}
```

`MiMoUsageProvider` keeps its existing behavior: `MiMoConsoleError.notLoggedIn` → clear `isLoggedIn`, fall back to manual. Since `fetchWithRecovery` now *throws* on persistent 401 instead of returning the 401 body, the provider's string check `text.contains("\"code\":401")` becomes dead for the web path but harmless for fakes — leave it (tests use it).

- [ ] **Step 4: Run tests** — `swift test --filter "MiMoSessionRecoveryTests|MiMoUsageProviderTests"` → PASS; full `swift build` clean.

- [ ] **Step 5: Commit** — `fix(mimo): recover from STS expiry by reloading console instead of demanding relogin`

---

### Task 2: Multi-pin AppModel

**Files:**
- Modify: `Sources/OkTally/App/AppModel.swift`
- Test: `Tests/OkTallyTests/AppModelTests.swift` (extend)

**Interfaces:**
- Produces: `AppModel.menuBarPins: [MenuBarPin]` (published, persisted under `"menuBarPins"`, `\u{2}`-joined stored forms; migrates legacy `"menuBarPin"`); `togglePin(providerId:windowLabel:)` (append/remove keeping order); `isPinned(providerId:windowLabel:) -> Bool`. `menuBarState` removed in Task 3 (kept until then).
- Consumes: `MenuBarPin.stored` / `init?(stored:)` (exists).

- [ ] **Step 1: Failing tests** (in `AppModelTests`, using its existing fixtures/UserDefaults handling; add a suiteName-scoped `UserDefaults` to avoid polluting real prefs)

```swift
func test_togglePin_appendsAndRemoves_keepingOrder() { /* toggle A, B, A → [B] */ }
func test_pins_persist_roundTrip() { /* set pins, read storage key, new model restores */ }
func test_legacySinglePin_migratesToList() { /* write old "menuBarPin" key, init model, expect [that pin], old key cleared */ }
```

Concrete test code:

```swift
func test_togglePin_appendsAndRemoves_keepingOrder() {
    let model = makeModel() // existing helper
    model.togglePin(providerId: "claude", windowLabel: "5h")
    model.togglePin(providerId: "codex", windowLabel: "semanal")
    model.togglePin(providerId: "claude", windowLabel: "5h")
    XCTAssertEqual(model.menuBarPins, [.init(providerId: "codex", windowLabel: "semanal")])
    XCTAssertTrue(model.isPinned(providerId: "codex", windowLabel: "semanal"))
    XCTAssertFalse(model.isPinned(providerId: "claude", windowLabel: "5h"))
}
```

Persistence tests inject `UserDefaults(suiteName: #function)!` (AppModel gains a `defaults:` init parameter defaulting to `.standard`).

- [ ] **Step 2: Run, verify fail** — `swift test --filter AppModelTests` → FAIL.

- [ ] **Step 3: Implement** in `AppModel`:

```swift
@Published var menuBarPins: [MenuBarPin] {
    didSet {
        let joined = menuBarPins.map(\.stored).joined(separator: "\u{2}")
        defaults.set(joined.isEmpty ? nil : joined, forKey: Self.menuBarPinsKey)
    }
}
private static let menuBarPinsKey = "menuBarPins"
private static let legacyMenuBarPinKey = "menuBarPin"
private let defaults: UserDefaults

// in init(registry:scheduler:defaults: UserDefaults = .standard):
self.defaults = defaults
if let joined = defaults.string(forKey: Self.menuBarPinsKey) {
    self.menuBarPins = joined.split(separator: "\u{2}").compactMap { MenuBarPin(stored: String($0)) }
} else if let legacy = MenuBarPin(stored: defaults.string(forKey: Self.legacyMenuBarPinKey)) {
    self.menuBarPins = [legacy]
    defaults.removeObject(forKey: Self.legacyMenuBarPinKey)
} else {
    self.menuBarPins = []
}

func togglePin(providerId: String, windowLabel: String) {
    let pin = MenuBarPin(providerId: providerId, windowLabel: windowLabel)
    if let i = menuBarPins.firstIndex(of: pin) { menuBarPins.remove(at: i) }
    else { menuBarPins.append(pin) }
}

func isPinned(providerId: String, windowLabel: String) -> Bool {
    menuBarPins.contains(MenuBarPin(providerId: providerId, windowLabel: windowLabel))
}
```

Delete the old `menuBarPin` property; temporarily patch `menuBarState` and `PopoverView` call sites to compile (`pin:` → first pin) — both are rebuilt in Tasks 3–4.

- [ ] **Step 4: Run tests** — PASS (fix any fallout in `MenuBarStateCalculatorTests` only if compilation breaks).

- [ ] **Step 5: Commit** — `feat: menu bar pins become an ordered, persisted list (migrates legacy single pin)`

---

### Task 3: MenuBarLabelModel + colored image renderer

**Files:**
- Create: `Sources/OkTally/UI/MenuBarLabelModel.swift`, `Sources/OkTally/UI/MenuBarLabelRenderer.swift`
- Modify: `Sources/OkTally/UI/ProviderPalette.swift` (id-keyed glyphs), `Sources/OkTally/App/AppModel.swift` (replace `menuBarState` with `menuBarSegments`), `Sources/OkTally/App/OkTallyApp.swift` (label = `Image(nsImage:)`)
- Delete: `Sources/OkTally/UI/MenuBarStateCalculator.swift`, `Tests/OkTallyTests/MenuBarStateCalculatorTests.swift`
- Test: `Tests/OkTallyTests/MenuBarLabelModelTests.swift`

**Interfaces:**
- Produces:

```swift
enum DangerLevel: Equatable { case ok, warn, critical, neutral }
struct MenuBarSegment: Equatable {
    let glyph: String?      // provider glyph ("C"); nil in automatic mode
    let providerId: String? // identity color lookup; nil in automatic mode
    let text: String        // "78" (% restante), "19.8$", "OK", "!"
    let danger: DangerLevel
}
enum MenuBarLabelModel {
    static func segments(pins: [AppModel.MenuBarPin], snapshots: [String: ProviderSnapshot], hasAnyError: Bool) -> [MenuBarSegment]
    static func danger(remaining: Double) -> DangerLevel // >0.30 ok, ≤0.30 warn, ≤0.10 critical
}
ProviderPalette.glyph(forId:) -> String  // claude C, codex X, supergrok G, cursor ▹, openrouter O, minimax M, opencode ◇, mimo K
MenuBarLabelRenderer.image(for: [MenuBarSegment]) -> NSImage // @MainActor, non-template
AppModel.menuBarSegments: [MenuBarSegment]
```

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import OkTally

final class MenuBarLabelModelTests: XCTestCase {
    private func snapshot(_ id: String, _ quotas: [QuotaWindow]) -> ProviderSnapshot {
        ProviderSnapshot(providerId: id, fetchedAt: Date(), quotas: quotas, usageDetail: nil)
    }
    private func window(_ label: String, usedPercent: Double) -> QuotaWindow {
        QuotaWindow(label: label, shape: .rollingWindow(
            used: usedPercent, limit: 100, windowStart: Date(), resetAt: Date().addingTimeInterval(3600)))
    }

    func test_pinnedPercentWindow_showsRemainingWithProviderGlyph() {
        let segs = MenuBarLabelModel.segments(
            pins: [.init(providerId: "claude", windowLabel: "5h")],
            snapshots: ["claude": snapshot("claude", [window("5h", usedPercent: 22)])],
            hasAnyError: false)
        XCTAssertEqual(segs, [MenuBarSegment(glyph: "C", providerId: "claude", text: "78", danger: .ok)])
    }

    func test_dangerLevels_matchQuotaPresentationThresholds() {
        XCTAssertEqual(MenuBarLabelModel.danger(remaining: 0.31), .ok)
        XCTAssertEqual(MenuBarLabelModel.danger(remaining: 0.30), .warn)
        XCTAssertEqual(MenuBarLabelModel.danger(remaining: 0.10), .critical)
    }

    func test_pinnedBalance_showsCompactValue() {
        let w = QuotaWindow(label: "balance", shape: .creditBalance(remaining: Decimal(19.82), currency: "USD"))
        let segs = MenuBarLabelModel.segments(
            pins: [.init(providerId: "openrouter", windowLabel: "balance")],
            snapshots: ["openrouter": snapshot("openrouter", [w])],
            hasAnyError: false)
        XCTAssertEqual(segs.first?.text, "19.8$")
        XCTAssertEqual(segs.first?.danger, .neutral)
    }

    func test_orphanPin_isOmitted() {
        let segs = MenuBarLabelModel.segments(
            pins: [.init(providerId: "gone", windowLabel: "x"),
                   .init(providerId: "claude", windowLabel: "5h")],
            snapshots: ["claude": snapshot("claude", [window("5h", usedPercent: 95)])],
            hasAnyError: false)
        XCTAssertEqual(segs, [MenuBarSegment(glyph: "C", providerId: "claude", text: "5", danger: .critical)])
    }

    func test_noPins_automatic_worstWindowNoGlyph() {
        let segs = MenuBarLabelModel.segments(
            pins: [],
            snapshots: ["claude": snapshot("claude", [window("5h", usedPercent: 22)]),
                        "codex": snapshot("codex", [window("semanal", usedPercent: 80)])],
            hasAnyError: false)
        XCTAssertEqual(segs, [MenuBarSegment(glyph: nil, providerId: nil, text: "20", danger: .warn)])
    }

    func test_noPins_noData_errorShowsBang_elseOK() {
        XCTAssertEqual(MenuBarLabelModel.segments(pins: [], snapshots: [:], hasAnyError: true),
                       [MenuBarSegment(glyph: nil, providerId: nil, text: "!", danger: .neutral)])
        XCTAssertEqual(MenuBarLabelModel.segments(pins: [], snapshots: [:], hasAnyError: false),
                       [MenuBarSegment(glyph: nil, providerId: nil, text: "OK", danger: .neutral)])
    }
}
```

- [ ] **Step 2: Run, verify fail.**

- [ ] **Step 3: Implement**

```swift
// Sources/OkTally/UI/MenuBarLabelModel.swift
import Foundation

enum DangerLevel: Equatable { case ok, warn, critical, neutral }

struct MenuBarSegment: Equatable {
    let glyph: String?
    let providerId: String?
    let text: String
    let danger: DangerLevel
}

/// Pure computation of what the menu bar shows — kept out of the view/renderer so the
/// pin → segment rules are unit-testable. The bar shows *remaining* percent, matching
/// the dropdown's "X% restante" copy (the pre-redesign bar showed used percent).
enum MenuBarLabelModel {
    static func segments(pins: [AppModel.MenuBarPin], snapshots: [String: ProviderSnapshot], hasAnyError: Bool) -> [MenuBarSegment] {
        let pinned = pins.compactMap { pin -> MenuBarSegment? in
            guard let snapshot = snapshots[pin.providerId],
                  let window = snapshot.quotas.first(where: { $0.label == pin.windowLabel })
            else { return nil }
            return segment(providerId: pin.providerId, shape: window.shape)
        }
        if !pinned.isEmpty { return pinned }

        let remainings = snapshots.values
            .flatMap(\.quotas)
            .compactMap { QuotaPresentation.remainingFraction($0.shape) }
        guard let worst = remainings.min() else {
            return [MenuBarSegment(glyph: nil, providerId: nil,
                                   text: hasAnyError ? "!" : "OK", danger: .neutral)]
        }
        return [MenuBarSegment(glyph: nil, providerId: nil,
                               text: String(Int((worst * 100).rounded())), danger: danger(remaining: worst))]
    }

    static func danger(remaining: Double) -> DangerLevel {
        if remaining <= 0.10 { return .critical }
        if remaining <= 0.30 { return .warn }
        return .ok
    }

    private static func segment(providerId: String, shape: QuotaShape) -> MenuBarSegment {
        let glyph = ProviderPalette.glyph(forId: providerId)
        if let remaining = QuotaPresentation.remainingFraction(shape) {
            return MenuBarSegment(glyph: glyph, providerId: providerId,
                                  text: String(Int((remaining * 100).rounded())),
                                  danger: danger(remaining: remaining))
        }
        switch shape {
        case .creditBalance(let remaining, _):
            let value = NSDecimalNumber(decimal: remaining).doubleValue
            return MenuBarSegment(glyph: glyph, providerId: providerId,
                                  text: String(format: "%.1f$", value), danger: .neutral)
        case .meteredOnly(let cost):
            let value = NSDecimalNumber(decimal: cost).doubleValue
            return MenuBarSegment(glyph: glyph, providerId: providerId,
                                  text: String(format: "%.1f$", value), danger: .neutral)
        default:
            return MenuBarSegment(glyph: glyph, providerId: providerId, text: "–", danger: .neutral)
        }
    }
}
```

`ProviderPalette` gains:

```swift
/// Short distinct glyph per provider id (displayName initials collide: Claude/Codex/Cursor).
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
    default: return "?"
    }
}
```

and `glyph(for provider:)` delegates to it: `glyph(forId: provider.id)`.

```swift
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
    // appearance context, so semantic colors would bake in the app appearance and can
    // vanish against the opposite menu bar. Gray is legible on both.
    private func color(for danger: DangerLevel) -> Color {
        switch danger {
        case .ok: return Color(red: 0.22, green: 0.78, blue: 0.42)
        case .warn: return .orange
        case .critical: return Color(red: 0.98, green: 0.26, blue: 0.27)
        case .neutral: return Color(white: 0.62)
        }
    }
}
```

`AppModel`: delete `menuBarState`, add:

```swift
var menuBarSegments: [MenuBarSegment] {
    MenuBarLabelModel.segments(pins: menuBarPins, snapshots: snapshotsByProvider,
                               hasAnyError: !errorsByProvider.isEmpty)
}
```

`OkTallyApp` label closure becomes:

```swift
} label: {
    Image(nsImage: MenuBarLabelRenderer.image(for: appModel.menuBarSegments))
}
```

(delete the `color(for:)` helper). Delete `MenuBarStateCalculator.swift` + its test file.

- [ ] **Step 4: Run** — `swift test` full suite → PASS.

- [ ] **Step 5: Commit** — `feat: colored multi-pin menu bar label rendered as non-template image`

---

### Task 4: Popover redesign (hero + gauge cards + problem rows)

**Files:**
- Create: `Sources/OkTally/UI/RingGauge.swift`
- Rewrite: `Sources/OkTally/UI/PopoverView.swift`
- Test: compilation + existing suite (view-only task; logic already tested via `QuotaPresentation`)

**Interfaces:**
- Consumes: `appModel.isPinned/togglePin/menuBarPins`, `QuotaPresentation.*`, `ProviderPalette.*`.
- Produces: `RingGauge(remaining: Double, size: CGFloat, color: Color, content: some View)`; `PopoverView` (same external shape: `init(appModel:)`).

- [ ] **Step 1: RingGauge**

```swift
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
            content()
        }
        .frame(width: size, height: size)
    }
}
```

- [ ] **Step 2: Rewrite PopoverView** with this structure (full code in file; key pieces):

```swift
struct PopoverView: View {
    @ObservedObject var appModel: AppModel

    // Providers that produced quota windows → cards; the rest → problem rows.
    private var withData: [(UsageProvider, ProviderSnapshot)] { … }
    private var problems: [(UsageProvider, String, ProviderErrorPresentation?)] { … }

    /// Most critical window overall: smallest remaining fraction; ties → nearest reset.
    private var hero: (provider: UsageProvider, window: QuotaWindow, remaining: Double)? { … }

    var body: some View {
        VStack(spacing: 0) {
            header                       // "OkTally" + "Barra: N fixados"/"automático"
            Divider()
            ScrollView {
                VStack(spacing: 10) {
                    if let hero { HeroCard(hero…, pinAction…) }
                    LazyVGrid(columns: [GridItem(.flexible), GridItem(.flexible)], spacing: 10) {
                        ForEach(withData) { ProviderGaugeCard(…) }
                    }
                    if !problems.isEmpty { ProblemsSection(problems) }
                }
                .padding(12)
            }
            .frame(maxHeight: 520)
            Divider()
            footer                       // Atualizar · Preferências · Sair (unchanged)
        }
        .frame(width: 360)
    }
}
```

- `HeroCard`: 56pt `RingGauge` (danger color, remaining% centered), provider name + window label, "X% restante" prominent, `QuotaPresentation.resetText` beneath, pin button.
- `ProviderGaugeCard`: chip+name header; 40pt ring of the provider's worst window (or the balance value text for `creditBalance`/`meteredOnly`); below, one compact row per window: pin button (`appModel.isPinned`/`togglePin`), label, remaining%/value colored by danger, reset text in `.tertiary`.
- The hero's provider still appears in the grid (single source of layout truth; hero is a spotlight, not a move).
- `ProblemsSection`: rows `[chip] name — message` with color by `ProviderErrorPresentation` (`notConfigured` → `.secondary`, `needsReauth` → `.orange`, else `.red`), message truncated to 2 lines with `.help(fullMessage)`.
- Estimated shapes keep the `~` prefix from `QuotaPresentation.remainingText` and get `.help("Estimativa local…")`.

- [ ] **Step 3: Build + full test suite** — `swift build && swift test` → PASS.

- [ ] **Step 4: Commit** — `feat: popover redesign — hero gauge, provider cards, quiet problem rows`

---

### Task 5: Preferences with sidebar

**Files:**
- Rewrite: `Sources/OkTally/UI/PreferencesView.swift` (split into `PreferencesView` + one small detail view per pane in the same file; file stays <500 lines)
- Modify: `Sources/OkTally/App/OkTallyApp.swift` (Settings window sizing only if needed)
- Test: compilation + suite (view-only).

**Interfaces:**
- Consumes: everything the current `PreferencesView` consumes (unchanged init signature), plus `appModel` for pin management → **add `appModel: AppModel` parameter**, passed from `OkTallyApp`.
- Produces: same-name `PreferencesView` with `NavigationSplitView`.

- [ ] **Step 1: Structure**

```swift
enum PreferencesPane: Hashable { case general, provider(String) }

struct PreferencesView: View {
    // existing lets + appModel
    @State private var pane: PreferencesPane = .general
    var body: some View {
        NavigationSplitView {
            List(selection: $pane) {
                Label("Geral", systemImage: "slider.horizontal.3").tag(PreferencesPane.general)
                Section("Contas") {
                    ForEach(providerIds, id: \.self) { id in
                        sidebarRow(id).tag(PreferencesPane.provider(id))
                    }
                }
            }
            .navigationSplitViewColumnWidth(180)
        } detail: {
            switch pane { case .general: GeneralPane(appModel:…); case .provider(let id): providerPane(id) }
        }
        .frame(width: 640, height: 460)
        .onAppear(perform: load)
    }
}
```

- `sidebarRow`: 20pt rounded chip in `ProviderPalette.color`, provider name, trailing 7pt status dot — green (token/key/session present), gray (not configured); Cursor always green ("automático"). Status state recomputed by the existing `load()` + after every login/logout/save.
- Provider panes reuse the existing card bodies verbatim (Claude paste-code flow, SuperGrok device code, MiniMax region toggle, MiMo login/estimate, `keyCard` fields become pane bodies) — headers become a shared `paneHeader(title:glyph:color:status:)` with the big chip + textual status.
- `GeneralPane`: "Fixados na barra de menu" list — each pin as `[glyph colored] Provider · janela` with ✕ remove button and ↑/↓ reorder buttons mutating `appModel.menuBarPins`; empty state text "Nada fixado — a barra mostra a pior janela automaticamente." plus caption explaining pinning from the dropdown.
- `statusMessage` stays but renders inside the active detail pane footer.

- [ ] **Step 2: Build + suite** — PASS.

- [ ] **Step 3: Commit** — `feat: sidebar Preferences (System Settings style) with pin management pane`

---

### Task 6: Stable code signing

**Files:**
- Modify: `Scripts/build_app.sh`

- [ ] **Step 1: Implement**

```bash
# Ad-hoc signatures change identity every build, which invalidates Keychain ACLs and
# forces relogin after each update. Prefer a stable local identity when present.
IDENTITY="OkTally Dev"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  codesign --force --deep --sign "$IDENTITY" "$APP_BUNDLE"
  echo "Signed with stable identity '$IDENTITY'."
else
  codesign --force --deep --sign - "$APP_BUNDLE"
  cat <<'EOF'
WARNING: ad-hoc signature — Keychain logins will NOT survive rebuilds.
Create a stable identity once with:
  1. Keychain Access > Certificate Assistant > Create a Certificate…
     Name: "OkTally Dev", Identity Type: Self-Signed Root, Certificate Type: Code Signing
  2. Re-run this script.
EOF
fi
```

(replaces the unconditional `codesign --force --deep --sign -` line)

- [ ] **Step 2: Run `bash Scripts/build_app.sh`** — expect successful bundle + warning path (no identity on this machine yet).

- [ ] **Step 3: Commit** — `fix(build): sign with stable "OkTally Dev" identity when available so Keychain survives rebuilds`

---

### Task 7: Final verification

- [ ] `swift test` — entire suite green.
- [ ] `bash Scripts/build_app.sh` — bundle builds.
- [ ] Update spec's "Fora de escopo" with the refresh-interval cut; commit docs.
