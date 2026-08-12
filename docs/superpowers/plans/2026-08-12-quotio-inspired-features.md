# Quotio-Inspired Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the five approved features borrowed from Quotio's feature set: (1) usage history sparkline + DB pruning, (2) user-configurable alert thresholds, (3) wired-up cost engine, (4) friendly window labels, (5) zero-config GitHub Copilot provider.

**Architecture:** Every feature builds on infrastructure that already exists (SQLite history, `AlertEngine` threshold plumbing, `PricingEngine`, `QuotaShape` plugin contract). New code follows the repo's existing patterns: pure testable models in `Core/`, UI helpers in `UI/`, one plugin folder per provider, protocol-injected dependencies, XCTest per unit.

**Tech Stack:** Swift 5.9 SPM, macOS 13+, GRDB 6.29, SwiftUI, XCTest. All user-facing copy in Portuguese (repo convention).

## Global Constraints

- Platform floor: macOS 13 (`Package.swift`), no new dependencies.
- All UI copy in Portuguese, matching existing tone ("Reseta em…", "restante").
- Raw window labels remain the persistence key for pins and thresholds — friendly labels are **display-only** (never persisted).
- Secrets never in UserDefaults; provider auth follows existing `AuthMethod` patterns.
- Tests: `swift test` must stay green; new units get their own `Tests/OkTallyTests/*Tests.swift`.
- Providers must never crash on missing local files — degrade to `nil`/`notConfigured` (pattern: `OpenCodeLocalEstimator`).

---

### Task 1: Snapshot pruning (retention policy)

**Files:**
- Modify: `Sources/OkTally/Storage/StorageManaging.swift`
- Modify: `Sources/OkTally/Storage/SQLiteStorage.swift`
- Modify: `Sources/OkTally/App/OkTallyApp.swift` (init)
- Test: `Tests/OkTallyTests/SQLiteStorageTests.swift`

**Interfaces:**
- Produces: `func prune(olderThan cutoff: Date) throws` on `StorageManaging` (later tasks may rely on storage staying small; AppModel in Task 4 reads recent history only).

- [ ] **Step 1: Failing test** — in `SQLiteStorageTests`, insert two snapshots (one 40 days old, one now), call `prune(olderThan: now-30d)`, assert only the recent one survives via `snapshots(providerId:since: .distantPast)`.
- [ ] **Step 2: Run test** → FAIL (method not defined).
- [ ] **Step 3: Implement** — protocol gains `func prune(olderThan cutoff: Date) throws`; SQLite impl:

```swift
func prune(olderThan cutoff: Date) throws {
    let cutoffValue = cutoff.timeIntervalSinceReferenceDate
    _ = try dbQueue.write { db in
        try SnapshotRecord.filter(Column("fetchedAt") < cutoffValue).deleteAll(db)
    }
}
```

Any other `StorageManaging` conformances in Tests (stubs) get a no-op implementation. `OkTallyApp.init` calls, after building storage: `try? storage.prune(olderThan: Date().addingTimeInterval(-30 * 24 * 3600))`.
- [ ] **Step 4: Run tests** → PASS. **Step 5: Commit** `feat(storage): prune snapshots older than 30 days`.

---

### Task 2: Friendly window labels (display-only)

**Files:**
- Create: `Sources/OkTally/UI/WindowLabelCatalog.swift`
- Modify: `Sources/OkTally/UI/PopoverView.swift` (HeroCard, QuotaLine)
- Modify: `Sources/OkTally/UI/PreferencesView.swift` (GeneralPane pin rows)
- Test: `Tests/OkTallyTests/WindowLabelCatalogTests.swift`

**Interfaces:**
- Produces: `enum WindowLabelCatalog { static func displayLabel(_ raw: String) -> String }`.

- [ ] **Step 1: Failing tests** — exact matches (`"5h"→"Sessão 5h"`, `"weekly"→"Semanal"`, `"weekly-opus"→"Opus semanal"`, `"semanal"→"Semanal"`, `"uso"→"Uso"`, `"balance"→"Saldo"`, `"percent"→"Ciclo"`, `"mensal"→"Mensal"`, `"monthly"→"Mensal"`, `"plano"→"Plano"`, `"chat"→"Chat"`, `"completions"→"Autocomplete"`, `"premium"→"Premium"`), parenthesized suffix translation (`"GPT-5.3-Codex-Spark (weekly)" → "GPT-5.3-Codex-Spark (Semanal)"`), unknown labels pass through unchanged.
- [ ] **Step 2:** FAIL. **Step 3: Implement:**

```swift
enum WindowLabelCatalog {
    private static let table: [String: String] = [
        "5h": "Sessão 5h", "weekly": "Semanal", "weekly-opus": "Opus semanal",
        "semanal": "Semanal", "uso": "Uso", "balance": "Saldo", "percent": "Ciclo",
        "mensal": "Mensal", "monthly": "Mensal", "plano": "Plano",
        "chat": "Chat", "completions": "Autocomplete", "premium": "Premium",
    ]
    static func displayLabel(_ raw: String) -> String {
        if let mapped = table[raw] { return mapped }
        // "Nome do modelo (weekly)" → translate only the parenthesized window kind.
        if raw.hasSuffix(")"), let open = raw.lastIndex(of: "("), open > raw.startIndex {
            let inner = String(raw[raw.index(after: open)..<raw.index(before: raw.endIndex)])
            if let mapped = table[inner] {
                return "\(raw[..<open])(\(mapped))"
            }
        }
        return raw
    }
}
```

Replace every `window.label` / `pin.windowLabel` **rendered as text** with `WindowLabelCatalog.displayLabel(...)`; comparisons/persistence keep raw labels.
- [ ] **Step 4:** PASS. **Step 5: Commit** `feat(ui): friendly display labels for quota windows`.

---

### Task 3: Configurable alert thresholds

**Files:**
- Modify: `Sources/OkTally/Preferences/PreferencesStore.swift`
- Modify: `Sources/OkTally/Core/AlertEngine.swift`
- Modify: `Sources/OkTally/App/OkTallyApp.swift`
- Modify: `Sources/OkTally/UI/PreferencesView.swift` (GeneralPane)
- Test: `Tests/OkTallyTests/PreferencesStoreTests.swift`, `Tests/OkTallyTests/AlertEngineTests.swift`

**Interfaces:**
- Produces on `PreferencesStore`: `var alertsEnabled: Bool` (default true), `var alertPercentThresholds: [Double]` (default `[0.7, 0.9, 1.0]`, persisted as comma-joined string), `var alertLowBalanceThreshold: Double` (default 5.0).
- `AlertEngine` becomes configurable: `init(percentThresholds: @escaping () -> [Double] = { [0.7, 0.9, 1.0] }, lowBalanceLimit: @escaping () -> Decimal = { 5 }, isEnabled: @escaping () -> Bool = { true })`. `evaluate` returns `[]` when disabled; default thresholds derive from the closures (`defaultThresholds(for:)` becomes an instance method; keep a static wrapper for source compat if tests use it).

- [ ] **Step 1: Failing tests** — store round-trips the three prefs with correct defaults; engine with `isEnabled: { false }` yields no events; engine with `percentThresholds: { [0.5] }` fires at 50%.
- [ ] **Step 2:** FAIL. **Step 3: Implement** store keys (`alertsEnabled` stored as `"true"/"false"` string via existing `KeyValueStore`; percent list as `"0.7,0.9,1.0"`), engine closures, and wire in `OkTallyApp.init`:

```swift
let alertEngine = AlertEngine(
    percentThresholds: { preferencesStore.alertPercentThresholds },
    lowBalanceLimit: { Decimal(preferencesStore.alertLowBalanceThreshold) },
    isEnabled: { preferencesStore.alertsEnabled }
)
```

- [ ] **Step 4:** GeneralPane gains an "Alertas" section: master `Toggle("Notificações de cota")`, one toggle per percent step (70% / 90% / 100%) mapping to membership in `alertPercentThresholds`, and a small `TextField` for the low-balance USD threshold. `PreferencesView` needs `preferencesStore` already injected — reuse it; GeneralPane gains a `preferencesStore: PreferencesStore` parameter.
- [ ] **Step 5:** `swift test` PASS. **Step 6: Commit** `feat(alerts): user-configurable thresholds and master toggle`.

---

### Task 4: Usage history sparkline

**Files:**
- Create: `Sources/OkTally/Core/UsageHistory.swift`
- Create: `Sources/OkTally/UI/SparklineView.swift`
- Modify: `Sources/OkTally/App/AppModel.swift`
- Modify: `Sources/OkTally/UI/PopoverView.swift` (ProviderGaugeCard)
- Test: `Tests/OkTallyTests/UsageHistoryTests.swift`

**Interfaces:**
- Produces: `struct UsageHistoryPoint: Equatable { let date: Date; let usedPercent: Double }`; `enum UsageHistory { static func worstUsedSeries(_ snapshots: [ProviderSnapshot]) -> [UsageHistoryPoint] }` (per snapshot: max `usedPercent` across windows; snapshots with no percent windows are skipped).
- `AppModel` gains `@Published private(set) var historyByProvider: [String: [UsageHistoryPoint]]`, refreshed from `storage.snapshots(providerId:since: now-24h)` at init seed and after each successful fetch. AppModel must retain `storage` (currently dropped after init).

- [ ] **Step 1: Failing tests** — series maps snapshots to worst-window points in order; balance-only snapshots skipped.
- [ ] **Step 2:** FAIL. **Step 3: Implement** `UsageHistory` + AppModel wiring (`private let storage: StorageManaging?`; recompute in `apply(.success)` for that provider only).
- [ ] **Step 4:** `SparklineView(points: [Double], color: Color)` — normalized `Path` polyline over a `GeometryReader`, height 20, subtle `color.opacity(0.12)` fill under the line, no axes. Render in `ProviderGaugeCard` below the window list when `points.count >= 2`, colored by the card's worst-status color, with `.help("Uso nas últimas 24h")`.
- [ ] **Step 5:** PASS. **Step 6: Commit** `feat(history): 24h usage sparkline per provider card`.

---

### Task 5: Wire the cost engine (real `usageDetail` + estimated cost line)

**Files:**
- Modify: `Sources/OkTally/Plugins/OpenCode/OpenCodeLocalEstimator.swift`
- Modify: `Sources/OkTally/Plugins/OpenCode/OpenCodeUsageProvider.swift`
- Modify: `Sources/OkTally/Pricing/PricingEngine.swift`
- Modify: `Sources/OkTally/App/AppModel.swift`, `Sources/OkTally/App/OkTallyApp.swift`
- Modify: `Sources/OkTally/UI/PopoverView.swift`
- Test: `Tests/OkTallyTests/PricingEngineTests.swift`, `Tests/OkTallyTests/OpenCodeUsageProviderTests.swift`

**Interfaces:**
- `OpenCodeLocalEstimating` gains `func modelTokens(windowHours: Int, now: Date) -> [UsageDetail]?` **with a protocol-extension default returning `nil`** so existing stubs keep compiling. SQL: `SELECT model, SUM(tokens_input), SUM(tokens_output) FROM session WHERE time_updated >= ? AND model IS NOT NULL GROUP BY model`; the `model` column is a JSON blob `{"id": "...", "providerID": "..."}` → `modelId = "\(providerID)/\(id)"`.
- `OpenCodeUsageProvider.fetchSnapshot` fills `usageDetail` with `estimator.modelTokens(windowHours: 720, now: now)`.
- `PricingEngine` gains `func estimatedCost(for details: [UsageDetail]) -> Decimal?` — sums per-detail cost; per detail: exact `cache[modelId]`, else first cache key with suffix `"/" + idPart` where `idPart` is the substring after the last `/` of `modelId`; returns `nil` when no detail matched.
- `AppModel` gains `@Published private(set) var estimatedCostByProvider: [String: Decimal]` and an optional `pricingEngine: PricingEngine?` init parameter (default `nil`); on successful snapshot with non-empty `usageDetail`, a `Task` refreshes pricing and stores the cost.

- [ ] **Step 1: Failing tests** — `PricingEngine.estimatedCost(for:)` sums two details, applies suffix fallback (`"xai/grok-4.5"` matches cached `"x-ai/grok-4.5"` only if exact fails and suffix `/grok-4.5` matches), returns nil on all-miss. `OpenCodeUsageProvider` test: stub estimator returning details → snapshot carries them.
- [ ] **Step 2:** FAIL. **Step 3: Implement** (estimator degrades to `nil` on any DB problem, same double-optional collapse as `spentInCurrentWindow`).
- [ ] **Step 4:** UI — `ProviderGaugeCard` gains `let estimatedCost: Decimal?`; when present render `Label("Custo est.: $X.XX (30d)", systemImage: "dollarsign.circle")` caption at 9 pt tertiary. `PopoverContentView` passes `appModel.estimatedCostByProvider[entry.provider.id]`. `OkTallyApp` builds `PricingEngine(source: OpenRouterPricingSource())` and injects into `AppModel`.
- [ ] **Step 5:** PASS. **Step 6: Commit** `feat(pricing): wire PricingEngine — OpenCode per-model tokens → estimated cost`.

---

### Task 6: GitHub Copilot provider (zero-config)

**Files:**
- Create: `Sources/OkTally/Plugins/Copilot/CopilotTokenReader.swift`
- Create: `Sources/OkTally/Plugins/Copilot/CopilotUsageProvider.swift`
- Modify: `Sources/OkTally/UI/ProviderPalette.swift` (color + glyph "P", GitHub graphite-violet `Color(red: 0.45, green: 0.40, blue: 0.75)`)
- Modify: `Sources/OkTally/App/OkTallyApp.swift` (register after cursor)
- Modify: `Sources/OkTally/UI/PreferencesView.swift` (`providerIds` + read-only pane + `isConfigured` case)
- Test: `Tests/OkTallyTests/CopilotTokenReaderTests.swift`, `Tests/OkTallyTests/CopilotUsageProviderTests.swift`

**Interfaces:**
- `CopilotTokenReader` (protocol `CopilotTokenReading { func firstToken() -> String? }`): scans `<home>/.config/github-copilot/apps.json`, `hosts.json` (recursive collection of `oauth_token`/`access_token` string values), then `<home>/.config/gh/hosts.yml` (`oauth_token:` line). `init(homeDirectory: String = NSHomeDirectory())` for tests. Never throws.
- `CopilotUsageProvider(tokenReader: CopilotTokenReading = CopilotTokenReader(), session: URLSession = .shared)`: `id "copilot"`, `displayName "GitHub Copilot"`, `authMethod .localFile(path: "~/.config/github-copilot")`, `refreshInterval 600`.
- Fetch: GET `https://api.github.com/copilot_internal/user`, headers `Authorization: Bearer <token>`, `Accept: application/vnd.github+json`, `X-GitHub-Api-Version: 2022-11-28`. Decode `quota_snapshots.{chat,completions,premium_interactions}` (`percent_remaining`, `unlimited`, `entitlement`, `remaining`) and `quota_reset_date`/`quota_reset_date_utc`; fallback pair `limited_user_quotas` + `monthly_quotas` for free plans. Each non-unlimited snapshot → `QuotaWindow(label: "chat"|"completions"|"premium", shape: .periodicCounter(used: 100 - percentRemaining, limit: 100, resetAt: resetDate ?? startOfNextMonth))`. 401/403 → `CopilotError.tokenRejected` (LocalizedError, PT message "Token do GitHub recusado — faça login no Copilot/gh novamente."). No windows at all (all unlimited) → single window is fine to omit; return snapshot with whatever windows exist.
- Tests use the existing `URLProtocolStub` pattern and a temp home directory fixture.

- [ ] **Step 1: Failing tests** — token reader finds token in `apps.json` fixture and in `hosts.yml` fixture, returns nil on empty dir; provider maps a stubbed entitlement JSON (chat 80% remaining, premium 10% remaining, reset date ISO8601) into two windows with `used = 20 / 90`, resetAt parsed; 403 throws `tokenRejected`.
- [ ] **Step 2:** FAIL. **Step 3: Implement** reader + provider.
- [ ] **Step 4:** Registration (`OkTallyApp`), palette, `providerIds` insert `"copilot"` after `"cursor"`, Preferences read-only pane (mirrors `cursorPane`: explainer text "Detectado automaticamente a partir do login do Copilot/gh CLI neste Mac."), `isConfigured("copilot")` = reader token exists.
- [ ] **Step 5:** `swift test` PASS. **Step 6: Commit** `feat(copilot): zero-config GitHub Copilot provider`.

---

### Task 7: Full verification + ship

- [ ] `swift build && swift test` — all green.
- [ ] Render README assets still work (`ReadmeAssetRenderer` compiles).
- [ ] Merge worktree branch into `master`, rebuild via `Scripts/build_app.sh`, relaunch app (ship-workflow convention).

## Self-Review

- Spec coverage: features 1→Task 4+1, 2→Task 3, 3→Task 5, 4→Task 2, 5→Task 6. ✓
- No placeholders: each task carries concrete signatures/SQL/endpoints. ✓
- Type consistency: `UsageDetail` reused as the estimator return type (avoids a duplicate struct); `StorageManaging.prune` matches Task 4's storage retention assumption. ✓
