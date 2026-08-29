---
title: "OkTally — reordenar assinaturas nas Preferências"
tags: [oktally, preferences, providers]
status: active
created: 2026-08-29
---

# OkTally Provider Order Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:test-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking. This feature is tightly coupled — implement the three tasks in order on one branch; do not split across parallel workers.

**Goal:** The owner can drag accounts in the Preferences **Contas** sidebar into the order he wants; that order persists and is used everywhere the app lists providers.

**Architecture:** A pure `ProviderOrder.resolved(saved:known:)` decides visible order (saved list, or the historical Preferences default when unset; unknown ids dropped; new registry ids appended). `PreferencesStore.providerOrder` persists it. `AppModel.orderedProviders` sorts the registry by that result. Preferences sidebar reads the model and reuses `PinReorder` + a dedicated `Transferable` type, same drag pattern as menu-bar pins.

**Tech Stack:** Swift 5, SwiftUI, macOS 26, XCTest, UserDefaults via `PreferencesStore`.

## Global Constraints

- Default visible order when nothing is saved MUST be the current Preferences hardcoded list: `["claude", "codex", "supergrok", "cursor", "cursor-grokbot", "copilot", "antigravity", "openrouter", "minimax", "opencode", "mimo"]` — not `OkTallyApp` registration order. Upgrading must not reshuffle anyone who never reordered.
- New providers not in the saved list append at the end, in registry order among themselves.
- Saved ids that are no longer registered are omitted from the visible list; do not rewrite storage until the owner reorders.
- Reuse `PinReorder.reordered(_:dragging:onto:)` for the drop math. Do not reimplement index arithmetic in the view.
- Drag payload is a dedicated `Transferable` type (`com.oktally.app.providerorder`), not `String`. Mirror `MenuBarPinTransfer` + its tests + `Info.plist` UTType.
- `orderedProviders` is the single source of list order for Preferences, Overview, popover, notch, analytics.
- No auto-recency / last-used sorting.
- Do not hide unconfigured accounts. Do not change plugin registration order in `OkTallyApp`.
- Comments in Portuguese, same voice as neighboring files. No English-only new comments in production files.
- Git author in this worktree: `Ferm Santos <fern@okamiops.com>`. Set `git config user.name` and `user.email` locally before the first commit. Do not use the global/repo Marcos identity.
- Branch: `feat/provider-order` from current `master` (`7b187b9692245fa67535232f91c4158470b55133` or whatever HEAD is at worktree creation). Never commit on `master`.
- TDD: failing test first, watch it fail, then implement. Full `swift test` before each commit (the OkTally package suite, not a scoped module).
- Copy this plan into `docs/superpowers/plans/2026-08-29-provider-order.md` on the feature branch (do not edit `master` in the main checkout).

---

## File structure

- Create: `Sources/OkTally/Core/ProviderOrder.swift` — pure resolve function + default IDs
- Create: `Sources/OkTally/Core/ProviderOrderTransfer.swift` — Transferable payload
- Create: `Tests/OkTallyTests/ProviderOrderTests.swift`
- Create: `Tests/OkTallyTests/ProviderOrderTransferTests.swift`
- Modify: `Sources/OkTally/Preferences/PreferencesStore.swift` — persist `[String]`
- Modify: `Tests/OkTallyTests/PreferencesStoreTests.swift`
- Modify: `Sources/OkTally/App/AppModel.swift` — `providerOrder`, `orderedProviders`, `moveProvider`
- Modify: `Tests/OkTallyTests/AppModelTests.swift`
- Modify: `Sources/OkTally/UI/PreferencesView.swift` — drop hardcoded array; drag on Contas rows
- Modify: `Resources/Info.plist` — export `com.oktally.app.providerorder`
- Modify: `CHANGELOG.md` — Unreleased

---

### Task 1: Resolve + persist order

**Files:**
- Create: `Sources/OkTally/Core/ProviderOrder.swift`
- Create: `Tests/OkTallyTests/ProviderOrderTests.swift`
- Modify: `Sources/OkTally/Preferences/PreferencesStore.swift`
- Modify: `Tests/OkTallyTests/PreferencesStoreTests.swift`

**Interfaces:**
- Consumes: `KeyValueStore` / `PreferencesStore` string keys; `PinReorder` is unused in this task
- Produces:
  - `enum ProviderOrder` with `static let defaultIDs: [String]` and `static func resolved(saved: [String], known: [String]) -> [String]`
  - `PreferencesStore.providerOrder: [String]` (empty array means unset)

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/OkTallyTests/ProviderOrderTests.swift
import XCTest
@testable import OkTally

final class ProviderOrderTests: XCTestCase {
    private let defaults = [
        "claude", "codex", "supergrok", "cursor", "cursor-grokbot", "copilot",
        "antigravity", "openrouter", "minimax", "opencode", "mimo"
    ]
    private let known = [
        "claude", "codex", "openrouter", "minimax", "cursor", "cursor-grokbot",
        "copilot", "antigravity", "opencode", "mimo", "supergrok"
    ]

    func test_nadaSalvo_usaAOrdemHistoricaDasPreferenciasNaoADoRegistry() {
        XCTAssertEqual(ProviderOrder.resolved(saved: [], known: known), defaults)
    }

    func test_listaSalva_filtraIdsDesconhecidosEPreservaAOrdemDoDono() {
        XCTAssertEqual(
            ProviderOrder.resolved(saved: ["mimo", "ghost", "claude"], known: ["claude", "mimo", "codex"]),
            ["mimo", "claude", "codex"]
        )
    }

    func test_providerNovo_entraNoFimNaOrdemDoRegistry() {
        XCTAssertEqual(
            ProviderOrder.resolved(saved: ["mimo", "claude"], known: ["claude", "novo", "mimo", "outro"]),
            ["mimo", "claude", "novo", "outro"]
        )
    }

    func test_duplicataNaListaSalva_mantemAPrimeira() {
        XCTAssertEqual(
            ProviderOrder.resolved(saved: ["claude", "mimo", "claude"], known: ["claude", "mimo"]),
            ["claude", "mimo"]
        )
    }
}
```

Add to `PreferencesStoreTests.swift`:

```swift
func test_providerOrder_emptyWhenUnset() {
    let store = makeStore()
    XCTAssertEqual(store.providerOrder, [])
}

func test_providerOrder_roundTrips() {
    let store = makeStore()
    store.providerOrder = ["mimo", "claude"]
    XCTAssertEqual(store.providerOrder, ["mimo", "claude"])
}

func test_providerOrder_emptyArrayClearsStorage() {
    let kv = FakeKeyValueStore()
    let store = makeStore(kv: kv)
    store.providerOrder = ["claude"]
    store.providerOrder = []
    XCTAssertNil(kv.string(forKey: "providerOrder"))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ProviderOrderTests --filter PreferencesStoreTests.test_providerOrder`
Expected: FAIL — `ProviderOrder` / `providerOrder` do not exist.

- [ ] **Step 3: Minimal implementation**

```swift
// Sources/OkTally/Core/ProviderOrder.swift
import Foundation

/// Ordem visível das contas: a que o dono arrumou, ou a lista histórica das
/// Preferências quando ele ainda não tocou em nada.
enum ProviderOrder {
    /// A sequência que a sidebar de Preferências usava hardcoded. Quem atualiza
    /// sem nunca reordenar continua vendo isto — não a ordem de `registry.register`.
    static let defaultIDs = [
        "claude", "codex", "supergrok", "cursor", "cursor-grokbot", "copilot",
        "antigravity", "openrouter", "minimax", "opencode", "mimo"
    ]

    /// Resolve a ordem mostrada.
    ///
    /// - `saved` vazio = nunca persistido → usa `defaultIDs`.
    /// - ids salvos que o registry não conhece saem da lista visível (o storage
    ///   não é reescrito aqui).
    /// - ids conhecidos que ainda não estão em `saved` entram no fim, na ordem
    ///   em que `known` os apresentou.
    static func resolved(saved: [String], known: [String]) -> [String] {
        let seed = saved.isEmpty ? defaultIDs : saved
        var seen = Set<String>()
        let knownSet = Set(known)
        var result: [String] = []
        result.reserveCapacity(known.count)
        for id in seed where knownSet.contains(id) && seen.insert(id).inserted {
            result.append(id)
        }
        for id in known where seen.insert(id).inserted {
            result.append(id)
        }
        return result
    }
}
```

In `PreferencesStore.Keys`: `static let providerOrder = "providerOrder"`

```swift
/// Ordem das contas escolhida pelo dono. Array vazio = nunca escolheu, e quem
/// lê usa `ProviderOrder.defaultIDs`. Separador `\u{2}` — o mesmo dos pins da
/// barra — porque os ids são tokens simples sem esse caractere.
var providerOrder: [String] {
    get {
        guard let raw = store.string(forKey: Keys.providerOrder), !raw.isEmpty else { return [] }
        return raw.split(separator: "\u{2}", omittingEmptySubsequences: true).map(String.init)
    }
    set {
        store.set(newValue.isEmpty ? nil : newValue.joined(separator: "\u{2}"), forKey: Keys.providerOrder)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ProviderOrderTests` and the three new PreferencesStore tests.
Then: `swift test` for the whole OkTally package.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git config user.name "Ferm Santos"
git config user.email "fern@okamiops.com"
git add Sources/OkTally/Core/ProviderOrder.swift \
        Tests/OkTallyTests/ProviderOrderTests.swift \
        Sources/OkTally/Preferences/PreferencesStore.swift \
        Tests/OkTallyTests/PreferencesStoreTests.swift \
        docs/superpowers/plans/2026-08-29-provider-order.md
git commit -m "$(cat <<'EOF'
feat(prefs): persist custom provider order

Keep the historical Preferences sequence as the unset default so an
upgrade does not reshuffle accounts the owner never rearranged.
EOF
)"
```

---

### Task 2: AppModel uses resolved order and can reorder

**Files:**
- Modify: `Sources/OkTally/App/AppModel.swift`
- Modify: `Tests/OkTallyTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `ProviderOrder.resolved`, `PreferencesStore.providerOrder`, `PinReorder.reordered`
- Produces:
  - `@Published var providerOrder: [String]` persisted via `preferences.providerOrder`
  - `var orderedProviders: [UsageProvider]` sorted by `ProviderOrder.resolved`
  - `func moveProvider(dragging: String, onto target: String) -> Bool`

- [ ] **Step 1: Write the failing tests** (append to `AppModelTests.swift`)

Use existing `FakeUsageProvider` + `FakeStorage` + a `UserDefaults(suiteName:)` so persistence does not touch the owner's defaults. Match the existing `AppModel(registry:scheduler:defaults:preferences:)` injection (`preferences` defaults to a store on the same `defaults`).

```swift
@MainActor
func test_orderedProviders_withoutSavedOrder_followsPreferencesDefaultNotRegistry() {
    let registry = PluginRegistry()
    for id in ["openrouter", "claude", "mimo"] {
        registry.register(FakeUsageProvider(id: id, displayName: id))
    }
    let defaults = UserDefaults(suiteName: "oktally.tests.provider-order.\(UUID().uuidString)")!
    defaults.removePersistentDomain(forName: defaults.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? "")
    let scheduler = Scheduler(
        registry: registry,
        storage: FakeStorage(),
        alertEngine: AlertEngine(),
        alertDispatcher: AlertDispatcher(sender: FakeNotificationSender())
    )
    let model = AppModel(registry: registry, scheduler: scheduler, defaults: defaults)
    XCTAssertEqual(model.orderedProviders.map(\.id), ["claude", "openrouter", "mimo"])
}

@MainActor
func test_moveProvider_persistsFullResolvedOrder() {
    let registry = PluginRegistry()
    for id in ["claude", "codex", "mimo"] {
        registry.register(FakeUsageProvider(id: id, displayName: id))
    }
    let suite = "oktally.tests.provider-order.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let scheduler = Scheduler(
        registry: registry,
        storage: FakeStorage(),
        alertEngine: AlertEngine(),
        alertDispatcher: AlertDispatcher(sender: FakeNotificationSender())
    )
    let model = AppModel(registry: registry, scheduler: scheduler, defaults: defaults)
    XCTAssertTrue(model.moveProvider(dragging: "mimo", onto: "claude"))
    XCTAssertEqual(model.orderedProviders.map(\.id), ["mimo", "claude", "codex"])
    XCTAssertEqual(model.providerOrder, ["mimo", "claude", "codex"])

    let reloaded = AppModel(registry: registry, scheduler: scheduler, defaults: defaults)
    XCTAssertEqual(reloaded.orderedProviders.map(\.id), ["mimo", "claude", "codex"])
}

@MainActor
func test_moveProvider_droppingOnSelf_returnsFalseAndDoesNotWrite() {
    let registry = PluginRegistry()
    registry.register(FakeUsageProvider(id: "claude", displayName: "Claude"))
    registry.register(FakeUsageProvider(id: "mimo", displayName: "MiMo"))
    let defaults = UserDefaults(suiteName: "oktally.tests.provider-order.\(UUID().uuidString)")!
    let scheduler = Scheduler(
        registry: registry,
        storage: FakeStorage(),
        alertEngine: AlertEngine(),
        alertDispatcher: AlertDispatcher(sender: FakeNotificationSender())
    )
    let model = AppModel(registry: registry, scheduler: scheduler, defaults: defaults)
    XCTAssertFalse(model.moveProvider(dragging: "claude", onto: "claude"))
    XCTAssertEqual(model.providerOrder, [])
}
```

Clean up suites in `tearDown` if you introduce a helper; leaking suites is acceptable for UUID-named ones if you call `removePersistentDomain`. Prefer a small helper that creates isolated defaults.

If constructing `AppModel` with a custom suite is awkward because `PreferencesStore` wraps `UserDefaults.standard` unless you pass `defaults:` — you MUST pass `defaults:` so `AppModel` builds `PreferencesStore(store: defaults)` (already the case at `AppModel.swift` ~160).

- [ ] **Step 2: Run to verify fail**

Run: `swift test --filter AppModelTests.test_orderedProviders --filter AppModelTests.test_moveProvider`
Expected: FAIL — `moveProvider` missing; `orderedProviders` still registry order (`openrouter, claude, mimo`).

- [ ] **Step 3: Minimal implementation**

In `AppModel`:

```swift
/// Ordem das contas na sidebar / popover / análise. Vazio = nunca arrastou,
/// e `orderedProviders` cai na lista histórica das Preferências.
@Published var providerOrder: [String] {
    didSet { preferences.providerOrder = providerOrder }
}
```

Init: `self.providerOrder = preferences.providerOrder` (alongside the other preference seeds).

Replace:

```swift
var orderedProviders: [UsageProvider] { registry.providers }
```

with:

```swift
var orderedProviders: [UsageProvider] {
    let known = registry.providers
    let ids = ProviderOrder.resolved(saved: providerOrder, known: known.map(\.id))
    let byId = Dictionary(uniqueKeysWithValues: known.map { ($0.id, $0) })
    return ids.compactMap { byId[$0] }
}

/// Move a conta arrastada para a posição do alvo e persiste a lista visível
/// inteira. `false` quando o arrasto não muda nada (`PinReorder` devolve nil).
@discardableResult
func moveProvider(dragging: String, onto target: String) -> Bool {
    let current = orderedProviders.map(\.id)
    guard let next = PinReorder.reordered(current, dragging: dragging, onto: target) else {
        return false
    }
    providerOrder = next
    return true
}
```

- [ ] **Step 4: `swift test` full package — PASS**

- [ ] **Step 5: Commit** `feat(prefs): apply saved provider order across the app`

---

### Task 3: Preferences sidebar drag + Transferable + changelog

**Files:**
- Create: `Sources/OkTally/Core/ProviderOrderTransfer.swift`
- Create: `Tests/OkTallyTests/ProviderOrderTransferTests.swift`
- Modify: `Sources/OkTally/UI/PreferencesView.swift`
- Modify: `Resources/Info.plist`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: `AppModel.orderedProviders`, `AppModel.moveProvider(dragging:onto:)`
- Produces: draggable Contas rows; UTType `com.oktally.app.providerorder`

- [ ] **Step 1: Failing transfer tests** — copy the structure of `MenuBarPinTransferTests` (exported types, NSItemProvider, Info.plist identifier, PinReorder feed). Identifier: `com.oktally.app.providerorder`. Payload field: `id: String`.

- [ ] **Step 2: Watch them fail**

- [ ] **Step 3: Implement transfer type + plist entry** (mirror `MenuBarPinTransfer` comments in Portuguese). Add a second dict to `UTExportedTypeDeclarations` (do not remove `menubarpin`).

- [ ] **Step 4: Wire PreferencesView**

Delete `private let providerIds = [...]`.

Use:

```swift
private var providerIds: [String] { appModel.orderedProviders.map(\.id) }
```

On each Contas row, after `.tag(PreferencesPane.provider(id))`:

```swift
.draggable(ProviderOrderTransfer(id: id))
.dropDestination(for: ProviderOrderTransfer.self) { items, _ in
    guard let dragged = items.first else { return false }
    return appModel.moveProvider(dragging: dragged.id, onto: id)
}
```

Do not add a drag handle; the row already has the chip. Do not use `onMove` unless drag-and-drop on the `List` selection is genuinely broken — then note it in the report.

Keep `consumeRequestedPane` checking `providerIds.contains(requested)`.

- [ ] **Step 5: CHANGELOG under `## [Unreleased]` → `### Added`:**

```
- **Custom account order in Preferences**: drag the Contas sidebar into the
  order you want. The same sequence is used in Overview, the popover, the
  notch, and Analytics. Newly added providers land at the end.
```

- [ ] **Step 6: Full `swift test`. Confirm HEAD. Commit** `feat(prefs): drag to reorder accounts in Preferences`

---

## Out of scope

- Recency / last-used auto sort
- Hiding unconfigured providers
- Reordering from Overview/popover (Preferences is the editor)
- Changing `OkTallyApp` registration order

## Self-review (controller)

- Spec: drag in Preferences Contas, persist, apply everywhere, new providers at end, no recency — Tasks 1–3.
- Default order is the hardcoded Preferences list, not registry order.
- Transferable is not String.
- PinReorder reused.
