---
title: "OkTally — múltiplas contas por provedor"
tags: [oktally, accounts, preferences, oauth, providers]
status: draft
created: 2026-09-28
---

# OkTally Multi-Account Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:test-driven-development. Checkbox (`- [ ]`) steps. Phases are sequential; each phase ends green (`swift test`) and is independently shippable. Tasks inside a phase are ordered — do not parallelize within a phase.

**Goal:** The owner can keep several accounts of the same provider (e.g. two Claude subscriptions) side by side. Each account is auto-labelled by the e-mail fetched after login plus an editable nickname ("Claude · Trabalho"), and that label shows in the Preferences sidebar, popover, notch, menu-bar pins and alerts.

**In scope:** Claude, Codex, SuperGrok (app-owned OAuth); OpenRouter, MiniMax (+ OpenCode, pending decision — see Task 4.4) (API keys); Antigravity (own Google OAuth for extra accounts); Cursor (own deep-login for extra accounts) with GrokBot following each Cursor account. **Out of scope:** MiMo (WKWebView session), Copilot (not requested) — both stay single-instance.

**Architecture:**
- `AccountKind` (what the provider *is*: palette, glyph, pane, OAuth config) vs **instance id** (the key *everywhere*: registry, scheduler, AppModel dicts, SQLite `snapshots.providerId`, Keychain service, pins/slots, providerOrder).
- Legacy instances keep id == kind (`"claude"`). Extra instances are `kind#xxxxxx` (6 hex). `#` is used because `\u{1}` (pins/slots), `\u{2}` (providerOrder/pins list) and `-` (`cursor-grokbot`) are already taken. **No migration** of pins, history or Keychain.
- `UsageProvider.id` becomes the instance id; each plugin gets an `instanceId` init parameter defaulting to its kind, so existing tests and call sites are untouched.
- `AccountInstance` list persisted in `PreferencesStore` (`accounts.v1`, JSON). Unset = one legacy instance per kind = today's app.
- The registry is built from the accounts by a `ProviderFactory`. A Cursor instance yields two providers: Cursor + its GrokBot twin (`cursor#abc` → `cursor-grokbot#abc`).
- Already per-instance once the id is the instance id: `KeychainTokenStore` (service `com.oktally.app.oauth.<id>`, `Auth/TokenStore.swift:25`), `KeychainSecretStore` (`Auth/SecretStore.swift:32`), `OAuthManager.inFlightRefreshes` (`Auth/OAuthManager.swift:112-120`), `SQLiteStorage` (snapshot carries `providerId`).
- `ProviderPalette` (`UI/ProviderPalette.swift:13-56`) resolves the kind by parsing the id, which fixes all 26 palette call sites at once.
- `displayName` is supplied by a `LabeledProvider` decorator reading the account label, so popover, notch, main window, analytics and alerts (`Core/Scheduler.swift:101`) get labels for free.

**Tech Stack:** Swift 5 mode, SwiftUI, macOS 26, XCTest, GRDB, Security.framework, CryptoKit.

## Global Constraints

- Zero behavior change for users who never add an account: same registry ids, same registration order (`claude, codex, openrouter, minimax, cursor, cursor-grokbot, copilot, antigravity, opencode, mimo, supergrok` — `App/OkTallyApp.swift:58-76`), same display names, same Keychain services, same pins.
- Instance id format: `kind` (legacy) or `kind#[0-9a-f]{6}`. `AccountID.kind(of:)` parses the prefix before `#`. Never split on `-`.
- Claude CLI legacy import (`ClaudeUsageProvider.importLegacyCredentialsIfAvailable`, `Plugins/Claude/ClaudeUsageProvider.swift:36-46`) only ever seeds the legacy `"claude"` instance, and only if that instance exists in the account list.
- Dedup: refuse to commit a new account whose `identityKey` already exists for that kind (Claude: `email|orgUUID`; other OAuth kinds: lowercased e-mail; API keys: `key:` + first 16 hex of SHA-256). On refusal, delete the credential written under the draft id.
- Refresh staggering: siblings of the same kind start their loops offset by `index * min(interval / count, 60s)`.
- Legacy IDE-bound instances (`cursor`, `antigravity`, `copilot`, `mimo`) cannot be removed. Legacy OAuth/API-key instances can; re-adding a kind whose legacy id is free reuses the legacy id.
- Comments in Portuguese, same voice as neighbouring files. UI strings through `L()`/`LF()` with `en.lproj` entries.
- Git author: `Ferm Santos <fern@okamiops.com>` (set locally in the worktree). Branch `feat/multi-account` from `master`; one branch per phase is fine (`feat/multi-account-p1` …). Never commit on `master`.
- TDD: failing test first, watch it fail, implement, full `swift test` before each commit.
- Commit trailer: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

---

## File structure

Create:
- `Sources/OkTally/Core/AccountKind.swift` — `AccountKind`, `AccountID`
- `Sources/OkTally/Core/AccountInstance.swift` — `AccountInstance`, `AccountsCatalog` (defaults), `AccountLabel`, `AccountDedup`, `AccountDirectory`
- `Sources/OkTally/Core/RefreshStagger.swift`
- `Sources/OkTally/Core/AccountRemoval.swift` — pure cleanup of pins/slots/order
- `Sources/OkTally/App/ProviderFactory.swift` — builds providers for an `AccountInstance`
- `Sources/OkTally/App/LabeledProvider.swift` — displayName decorator
- `Sources/OkTally/Auth/AccountEmailResolver.swift`
- `Sources/OkTally/Plugins/Antigravity/AntigravityOAuth.swift`
- `Sources/OkTally/Plugins/Cursor/CursorDeepLoginFlow.swift`
- Tests: `AccountKindTests`, `AccountInstanceTests`, `AccountsStoreTests` (in `PreferencesStoreTests`), `ProviderFactoryTests`, `RefreshStaggerTests`, `AccountRemovalTests`, `AccountEmailResolverTests`, `AntigravityOAuthTests`, `CursorDeepLoginFlowTests`, `AccountDirectoryTests`

Modify (main ones): `Core/UsageProvider.swift`, `Core/PluginRegistry.swift`, `Core/Scheduler.swift`, `App/OkTallyApp.swift`, `App/AppModel.swift`, `Preferences/PreferencesStore.swift`, `Auth/OAuthConfig.swift`, `Auth/OAuthManager.swift`, `Auth/BrowserOAuthFlow.swift`, `Auth/DeviceCodeFlow.swift`, all `Plugins/*/…UsageProvider.swift` in scope, `Plugins/Claude/ClaudeProfileClient.swift`, `Plugins/Cursor/CursorTokenReader.swift`, `Storage/StorageManaging.swift`, `Storage/SQLiteStorage.swift`, `UI/ProviderPalette.swift`, `UI/QuotaSlotResolver.swift:144`, `UI/PopoverView.swift:318`, `UI/PreferencesView.swift`, `UI/DesignSystem/ProviderSidebarRow.swift`, `UI/MenuBarLabelModel.swift:119-120`, `CHANGELOG.md`, `Resources/en.lproj/Localizable.strings`.

---

# Phase 1 — Core model (zero behavior change)

### Task 1.1: `AccountKind` + `AccountID`

**Files:** Create `Sources/OkTally/Core/AccountKind.swift`, `Tests/OkTallyTests/AccountKindTests.swift`

- [ ] **Step 1: failing tests**

```swift
import XCTest
@testable import OkTally

final class AccountKindTests: XCTestCase {
    func test_kind_legacyIdIsItsOwnKind() {
        XCTAssertEqual(AccountID.kind(of: "claude"), .claude)
        XCTAssertEqual(AccountID.kind(of: "cursor-grokbot"), .grokbot)
    }

    func test_kind_extraInstanceParsesPrefixBeforeHash() {
        XCTAssertEqual(AccountID.kind(of: "claude#a1b2c3"), .claude)
        XCTAssertEqual(AccountID.kind(of: "cursor-grokbot#a1b2c3"), .grokbot)
    }

    func test_kind_unknownIsNil() {
        XCTAssertNil(AccountID.kind(of: "ghost"))
        XCTAssertNil(AccountID.kind(of: "ghost#123456"))
    }

    func test_isLegacy() {
        XCTAssertTrue(AccountID.isLegacy("codex"))
        XCTAssertFalse(AccountID.isLegacy("codex#00ff00"))
    }

    func test_make_usesSixHexSuffix() {
        let id = AccountID.make(kind: .codex, suffix: "abc123")
        XCTAssertEqual(id, "codex#abc123")
        let random = AccountID.make(kind: .codex)
        XCTAssertTrue(random.range(of: "^codex#[0-9a-f]{6}$", options: .regularExpression) != nil)
    }

    func test_nextId_reusesLegacyWhenFree() {
        XCTAssertEqual(AccountID.nextId(kind: .claude, existing: [], suffix: "aaaaaa"), "claude")
        XCTAssertEqual(AccountID.nextId(kind: .claude, existing: ["claude"], suffix: "aaaaaa"), "claude#aaaaaa")
    }

    func test_grokBotTwin() {
        XCTAssertEqual(AccountID.grokBotId(forCursor: "cursor"), "cursor-grokbot")
        XCTAssertEqual(AccountID.grokBotId(forCursor: "cursor#abc123"), "cursor-grokbot#abc123")
    }

    func test_separatorNeverCollidesWithPersistenceSeparators() {
        let id = AccountID.make(kind: .claude)
        XCTAssertFalse(id.contains("\u{1}"))
        XCTAssertFalse(id.contains("\u{2}"))
        XCTAssertEqual(AppModel.MenuBarPin(stored: AppModel.MenuBarPin(providerId: id, windowLabel: "5h").stored)?.providerId, id)
        XCTAssertEqual(QuotaSlot(stored: QuotaSlot.window(providerId: id, windowLabel: "weekly").stored),
                       .window(providerId: id, windowLabel: "weekly"))
    }
}
```

- [ ] **Step 2:** `swift test --filter AccountKindTests` → fails (types missing).
- [ ] **Step 3: implement**

```swift
// Sources/OkTally/Core/AccountKind.swift
import Foundation

/// O que o provedor É (cor, glifo, painel, config OAuth). Distinto do id da instância,
/// que é a chave em todo o resto do app.
enum AccountKind: String, CaseIterable, Codable {
    case claude, codex, supergrok, cursor
    case grokbot = "cursor-grokbot"
    case copilot, antigravity, openrouter, minimax, opencode, mimo

    /// Tipos que aceitam segunda conta. Liga fase a fase (ver plano); vazio na Fase 1.
    static var addableKinds: [AccountKind] { [] }

    /// Tipos cujo legado lê um app de terceiros (IDE/CLI) e por isso não podem ser removidos.
    var legacyIsMachineBound: Bool {
        switch self {
        case .cursor, .grokbot, .antigravity, .copilot, .mimo: return true
        default: return false
        }
    }
}

enum AccountID {
    static let separator: Character = "#"

    static func kind(of instanceId: String) -> AccountKind? {
        let prefix = instanceId.split(separator: separator, maxSplits: 1, omittingEmptySubsequences: false).first
        return prefix.flatMap { AccountKind(rawValue: String($0)) }
    }

    static func isLegacy(_ instanceId: String) -> Bool { !instanceId.contains(separator) }

    static func suffix(of instanceId: String) -> String? {
        instanceId.split(separator: separator, maxSplits: 1).dropFirst().first.map(String.init)
    }

    static func make(kind: AccountKind, suffix: String = randomSuffix()) -> String {
        "\(kind.rawValue)\(separator)\(suffix)"
    }

    static func nextId(kind: AccountKind, existing: [String], suffix: String = randomSuffix()) -> String {
        existing.contains(kind.rawValue) ? make(kind: kind, suffix: suffix) : kind.rawValue
    }

    static func grokBotId(forCursor cursorId: String) -> String {
        suffix(of: cursorId).map { make(kind: .grokbot, suffix: $0) } ?? AccountKind.grokbot.rawValue
    }

    static func randomSuffix() -> String {
        String(UUID().uuidString.lowercased().filter(\.isHexDigit).prefix(6))
    }
}
```

- [ ] **Step 4:** tests green; full `swift test`.
- [ ] **Step 5: commit** `feat(accounts): introduce AccountKind and instance id format`

### Task 1.2: `AccountInstance`, defaults, labels, dedup

**Files:** Create `Sources/OkTally/Core/AccountInstance.swift`, `Tests/OkTallyTests/AccountInstanceTests.swift`

- [ ] **Step 1: failing tests**

```swift
final class AccountInstanceTests: XCTestCase {
    func test_defaults_matchTodaysRegistrationOrderWithoutGrokBot() {
        XCTAssertEqual(AccountsCatalog.defaultAccounts.map(\.id),
                       ["claude", "codex", "openrouter", "minimax", "cursor", "copilot",
                        "antigravity", "opencode", "mimo", "supergrok"])
    }

    func test_label_singleAccountWithoutNickname_isKindDisplayName() {
        let a = AccountInstance(id: "claude", kind: .claude)
        XCTAssertEqual(AccountLabel.display(for: a, baseName: "Claude Code", siblings: [a]), "Claude Code")
    }

    func test_label_nicknameAlwaysShows() {
        var a = AccountInstance(id: "claude", kind: .claude); a.nickname = "Trabalho"
        XCTAssertEqual(AccountLabel.display(for: a, baseName: "Claude Code", siblings: [a]), "Claude Code · Trabalho")
    }

    func test_label_siblingsWithoutNickname_fallBackToEmailThenOrdinal() {
        var a = AccountInstance(id: "claude", kind: .claude); a.email = "me@work.com"
        let b = AccountInstance(id: "claude#abc123", kind: .claude)
        XCTAssertEqual(AccountLabel.display(for: a, baseName: "Claude Code", siblings: [a, b]), "Claude Code · me@work.com")
        XCTAssertEqual(AccountLabel.display(for: b, baseName: "Claude Code", siblings: [a, b]), "Claude Code · 2")
    }

    func test_dedup_sameKindSameIdentity_isDuplicate() {
        var a = AccountInstance(id: "codex", kind: .codex); a.identityKey = "me@x.com"
        XCTAssertTrue(AccountDedup.isDuplicate(identityKey: "ME@x.com", kind: .codex, among: [a], excluding: "codex#new000"))
        XCTAssertFalse(AccountDedup.isDuplicate(identityKey: "me@x.com", kind: .claude, among: [a], excluding: "claude#new000"))
        XCTAssertFalse(AccountDedup.isDuplicate(identityKey: nil, kind: .codex, among: [a], excluding: "codex#new000"))
    }

    func test_codableRoundTrip() throws {
        var a = AccountInstance(id: "claude#abc123", kind: .claude)
        a.nickname = "Pessoal"; a.email = "p@x.com"; a.identityKey = "p@x.com|org"
        let data = try JSONEncoder().encode([a])
        XCTAssertEqual(try JSONDecoder().decode([AccountInstance].self, from: data), [a])
    }
}
```

- [ ] **Step 3: implement.** `struct AccountInstance: Codable, Equatable, Identifiable { let id: String; let kind: AccountKind; var nickname: String?; var email: String?; var identityKey: String? }`. `AccountsCatalog.defaultAccounts` in the order above. `AccountLabel.display(for:baseName:siblings:)`: nickname → `"base · nick"`; else if siblings of same kind > 1 → `"base · email"` or `"base · N"` (1-based position among siblings); else `base`. `AccountDedup.isDuplicate` compares `identityKey?.lowercased()` among same-kind instances whose id ≠ `excluding`.
- [ ] **Step 4–5:** green; commit `feat(accounts): account instance model, labels and dedup`

### Task 1.3: Persist accounts in `PreferencesStore`

**Files:** Modify `Sources/OkTally/Preferences/PreferencesStore.swift` (Keys enum `:20-49`), `Tests/OkTallyTests/PreferencesStoreTests.swift`

- [ ] **Step 1: failing tests**

```swift
func test_accounts_unsetReturnsLegacyDefaults() {
    XCTAssertEqual(makeStore().accounts, AccountsCatalog.defaultAccounts)
}

func test_accounts_roundTrip() {
    let store = makeStore()
    var extra = AccountInstance(id: "claude#abc123", kind: .claude); extra.nickname = "Trabalho"
    store.accounts = AccountsCatalog.defaultAccounts + [extra]
    XCTAssertEqual(store.accounts.last, extra)
}

func test_accounts_corruptJSONFallsBackToDefaults() {
    let kv = FakeKeyValueStore(); kv.set("{not json", forKey: "accounts.v1")
    XCTAssertEqual(makeStore(kv: kv).accounts, AccountsCatalog.defaultAccounts)
}
```

- [ ] **Step 3:** `static let accounts = "accounts.v1"`; getter decodes JSON (failure/empty → defaults); setter encodes. Comment in PT: e-mail lives here (not secret), credentials never.
- [ ] **Step 5:** commit `feat(accounts): persist account list in PreferencesStore`

### Task 1.4: Plugins accept `instanceId`

**Files:** Modify `Plugins/Claude/ClaudeUsageProvider.swift:4,17-29,36-46`, `Plugins/Codex/CodexUsageProvider.swift:5,14`, `Plugins/SuperGrok/SuperGrokUsageProvider.swift:20,30`, `Plugins/OpenRouter/OpenRouterUsageProvider.swift:5,13`, `Plugins/MiniMax/MiniMaxUsageProvider.swift:5,13`, `Plugins/OpenCode/OpenCodeUsageProvider.swift:28`, `Plugins/Cursor/CursorUsageProvider.swift:5,13`, `Plugins/Cursor/GrokBotUsageProvider.swift:51,62`, `Plugins/Antigravity/AntigravityUsageProvider.swift:28,51`, `Auth/OAuthConfig.swift`, `Auth/DeviceCodeFlow.swift:7-13`; tests in each provider's test file.

- [ ] **Step 1: failing tests** (one per plugin; example Claude + OAuthConfig):

```swift
// ClaudeUsageProviderTests
func test_extraInstance_usesInstanceIdForTokenAndSnapshot() async throws {
    let store = InMemoryTokenStore()
    try store.save(OAuthToken(accessToken: "tok2", refreshToken: "rt", expiresAt: nil, extra: [:]), providerId: "claude#abc123")
    let fetcher = FakeClaudeUsageFetching()
    fetcher.responseToReturn = ClaudeUsageResponse(
        fiveHour: ClaudeUsageWindow(utilization: 1, resetsAt: Date()),
        sevenDay: ClaudeUsageWindow(utilization: 2, resetsAt: Date()), sevenDayOpus: nil)
    let provider = ClaudeUsageProvider(instanceId: "claude#abc123", oauthManager: FakeOAuthManaging(),
                                       tokenStore: store, apiClient: fetcher, legacyCredentialProvider: nil)
    XCTAssertEqual(provider.id, "claude#abc123")
    let authenticated = await provider.isAuthenticated()
    XCTAssertTrue(authenticated)
    let snapshot = try await provider.fetchSnapshot()
    XCTAssertEqual(snapshot.providerId, "claude#abc123")
}

func test_legacyImport_neverSeedsExtraInstance() {
    let store = InMemoryTokenStore()
    let provider = ClaudeUsageProvider(instanceId: "claude#abc123", oauthManager: FakeOAuthManaging(),
                                       tokenStore: store, legacyCredentialProvider: ClaudeCredentialProvider(
                                           keychainReader: StubReader(json: validClaudeJSON)))
    XCTAssertFalse(provider.importLegacyCredentialsIfAvailable())
    XCTAssertNil(store.load(providerId: "claude#abc123"))
}

// OAuthConfigTests (new)
func test_forInstance_replacesStorageKeyOnly() {
    let c = CodexOAuth.config.forInstance("codex#abc123")
    XCTAssertEqual(c.providerId, "codex#abc123")
    XCTAssertEqual(c.clientId, CodexOAuth.config.clientId)
    XCTAssertEqual(c.redirectPort, 1455)
}
```

- [ ] **Step 3:** each provider: `let id: String` + `init(instanceId: String = "<kind>", …)`. Use `config.forInstance(id)` wherever `ClaudeOAuth.config` / `CodexOAuth.config` / `SuperGrokOAuth.refreshConfig` is passed to `validAccessToken`. `importLegacyCredentialsIfAvailable` guards `id == AccountKind.claude.rawValue`. Add `func forInstance(_:) -> OAuthConfig` and `DeviceCodeOAuthConfig.forInstance(_:)` (copy with `providerId` replaced). GrokBot: `init(instanceId: String = "cursor-grokbot", tokenReader: …)`.
- [ ] **Step 5:** commit `refactor(plugins): providers keyed by instance id (default = kind)`

### Task 1.5: `ProviderFactory` + `LabeledProvider` + registry from accounts

**Files:** Create `App/ProviderFactory.swift`, `App/LabeledProvider.swift`, `Tests/OkTallyTests/ProviderFactoryTests.swift`; Modify `Core/PluginRegistry.swift`, `App/OkTallyApp.swift:54-76`

- [ ] **Step 1: failing tests**

```swift
final class ProviderFactoryTests: XCTestCase {
    private func makeFactory() -> ProviderFactory {
        ProviderFactory(dependencies: .testing(tokenStore: InMemoryTokenStore(),
                                               preferences: PreferencesStore(store: FakeKeyValueStore(), secretStore: FakeSecretStore())))
    }

    func test_defaults_produceTodaysRegistryIdsInOrder() {
        let ids = AccountsCatalog.defaultAccounts.flatMap { makeFactory().providers(for: $0, all: AccountsCatalog.defaultAccounts) }.map(\.id)
        XCTAssertEqual(ids, ["claude", "codex", "openrouter", "minimax", "cursor", "cursor-grokbot",
                             "copilot", "antigravity", "opencode", "mimo", "supergrok"])
    }

    func test_defaults_keepTodaysDisplayNames() {
        let names = AccountsCatalog.defaultAccounts.flatMap { makeFactory().providers(for: $0, all: AccountsCatalog.defaultAccounts) }.map(\.displayName)
        XCTAssertEqual(names, ["Claude Code", "Codex", "OpenRouter", "MiniMax", "Cursor", "GrokBot",
                               "Copilot", "Antigravity", "OpenCode", "MiMo", "SuperGrok"])
    }

    func test_extraCursor_emitsGrokBotTwin() {
        let extra = AccountInstance(id: "cursor#abc123", kind: .cursor)
        XCTAssertEqual(makeFactory().providers(for: extra, all: [extra]).map(\.id), ["cursor#abc123", "cursor-grokbot#abc123"])
    }

    func test_registry_replaceAddRemove() {
        let registry = PluginRegistry()
        registry.register(FakeUsageProvider(id: "a", displayName: "A"))
        registry.add([FakeUsageProvider(id: "b", displayName: "B")])
        registry.remove(ids: ["a"])
        XCTAssertEqual(registry.providers.map(\.id), ["b"])
    }
}
```

(Adjust expected display names to the real `displayName` of Copilot/MiMo — read them from the plugins before writing the test.)

- [ ] **Step 3:**
  - `PluginRegistry`: keep `register(_:)`; add `add(_:)`, `remove(ids:)`; guard `providers` with `NSLock` (read from scheduler tasks off the main actor).
  - `LabeledProvider: UsageProvider` wraps `base` and returns `label()` for `displayName`, forwarding everything else.
  - `ProviderFactory.Dependencies` bundles `oauthManager`, `tokenStore`, `preferences`, `mimoSessionStore`; a `.testing` helper for tests.
  - `providers(for:all:)` switches on `kind` and wraps each provider with `LabeledProvider(base:label:)`, where the label is computed via `AccountLabel.display` from a closure reading the current accounts.
  - API-key closures keep calling `preferences.openRouterAPIKey` etc. for legacy ids (Phase 4 generalizes).
  - `OkTallyApp.init`: replace `:58-76` with `for account in preferencesStore.accounts { factory.providers(for: account, all: …).forEach(registry.register) }`. Keep `claudeProvider.importLegacyCredentialsIfAvailable()` only when the accounts contain `"claude"`. `onImportClaudeLegacy` keeps pointing at the legacy Claude provider (`:147`).
- [ ] **Step 4:** full suite plus manual launch: sidebar, popover and pins identical to 0.9.6.
- [ ] **Step 5:** commit `refactor(app): build registry from persisted accounts`

### Task 1.6: Palette/glyph and Codex special-cases by kind

**Files:** Modify `UI/ProviderPalette.swift:13-56`, `UI/QuotaSlotResolver.swift:144`, `UI/PopoverView.swift:318` (`PopoverLayout.orderedWindows`); tests `QuotaSlotResolverTests`, `PopoverLayoutTests`, new `ProviderPaletteTests`

- [ ] **Step 1: failing tests**

```swift
func test_palette_extraInstanceSharesKindColorAndGlyph() {
    XCTAssertEqual(ProviderPalette.color(for: "claude#abc123"), ProviderPalette.color(for: "claude"))
    XCTAssertEqual(ProviderPalette.glyph(forId: "cursor-grokbot#abc123"), "GB")
}

func test_codexWeeklyPriority_appliesToExtraCodexInstance() {
    let quotas = [spark(remaining: 0.1), weekly(remaining: 0.6)]
    XCTAssertEqual(PopoverLayout.primaryWindow(providerId: "codex#abc123", quotas: quotas)?.label, "weekly")
}
```

- [ ] **Step 3:** `color(for:)` / `glyph(forId:)` switch on `AccountID.kind(of:)?.rawValue ?? id`. Replace `providerId == "codex"` with `AccountID.kind(of: providerId) == .codex` at both sites.
- [ ] **Step 5:** commit `refactor(ui): resolve palette and Codex rules by account kind`

### Task 1.7: Dynamic scheduler loops + stagger

**Files:** Create `Core/RefreshStagger.swift`, `Tests/OkTallyTests/RefreshStaggerTests.swift`; Modify `Core/Scheduler.swift:71-80`, `Tests/OkTallyTests/SchedulerTests.swift`

- [ ] **Step 1: failing tests**

```swift
final class RefreshStaggerTests: XCTestCase {
    func test_singleInstancesStartImmediately() {
        let offsets = RefreshStagger.offsets(for: [("claude", 300), ("codex", 300)])
        XCTAssertEqual(offsets["claude"], 0); XCTAssertEqual(offsets["codex"], 0)
    }

    func test_siblingsSpreadAcrossInterval_cappedAt60s() {
        let offsets = RefreshStagger.offsets(for: [("claude", 300), ("claude#aaaaaa", 300), ("claude#bbbbbb", 300)])
        XCTAssertEqual(offsets["claude"], 0)
        XCTAssertEqual(offsets["claude#aaaaaa"], 60)
        XCTAssertEqual(offsets["claude#bbbbbb"], 120)
    }
}

// SchedulerTests
func test_stopLoop_cancelsOnlyThatInstance() async throws {
    let a = FakeUsageProvider(id: "a", displayName: "A"); a.snapshotToReturn = snapshot(providerId: "a", percent: 1)
    let registry = PluginRegistry(); registry.register(a)
    let scheduler = Scheduler(registry: registry, storage: FakeStorage(), alertEngine: AlertEngine(),
                              alertDispatcher: AlertDispatcher(sender: FakeNotificationSender()))
    scheduler.startLoop(for: a, initialDelay: 0)
    XCTAssertTrue(scheduler.isLooping(id: "a"))
    scheduler.stopLoop(id: "a")
    XCTAssertFalse(scheduler.isLooping(id: "a"))
}
```

- [ ] **Step 3:** `RefreshStagger.offsets(for: [(id, interval)]) -> [String: TimeInterval]` groups by kind in input order: `offset = index * min(interval / count, 60)`. Scheduler: `private var loops: [String: Task<Void, Never>]` under a lock; `startLoop(for:initialDelay:)` sleeps `initialDelay` then runs the existing loop body; `stopLoop(id:)` cancels; `startPeriodicLoop()` computes offsets and calls `startLoop` for each (all offsets are 0 for defaults, so behavior is unchanged). Also make `setLastError(nil, for:)` callable on stop so errors of removed instances disappear.
- [ ] **Step 5:** commit `feat(scheduler): per-instance loops with sibling stagger`

**Phase 1 exit:** `swift test` green; manual smoke on a real profile shows nothing changed. Ship as a patch release (no CHANGELOG user entry needed, or "Internal: account model").

---

# Phase 2 — Preferences UI (add/remove/rename, e-mail, per-instance panes)

### Task 2.1: AppModel account lifecycle

**Files:** Modify `App/AppModel.swift` (`init :150-208`, `orderedProviders :311-316`, `apply :419-434`), `Storage/StorageManaging.swift`, `Storage/SQLiteStorage.swift`; all `StorageManaging` conformers (`FakeStorage` in `SchedulerTests.swift`, the two private storages in `AppModelTests.swift:9,33`); Create `Core/AccountRemoval.swift`, `Tests/OkTallyTests/AccountRemovalTests.swift`

- [ ] **Step 1: failing tests**

```swift
final class AccountRemovalTests: XCTestCase {
    func test_cleanup_dropsPinsSlotsAndOrderForRemovedIdOnly() {
        let pins = [AppModel.MenuBarPin(providerId: "claude#abc123", windowLabel: "5h"),
                    AppModel.MenuBarPin(providerId: "claude", windowLabel: "5h")]
        let result = AccountRemoval.cleanup(
            removedIds: ["claude#abc123"], pins: pins,
            slots: [.window(providerId: "claude#abc123", windowLabel: "5h"), .automatic],
            order: ["claude", "claude#abc123", "codex"])
        XCTAssertEqual(result.pins.map(\.providerId), ["claude"])
        XCTAssertEqual(result.slots, [.automatic, .automatic])
        XCTAssertEqual(result.order, ["claude", "codex"])
    }
}

// AppModelTests
func test_addAccount_registersInsertsAfterSiblingsAndStartsLoop() async {
    let model = makeModelWithFactory()   // helper injecting a factory that returns FakeUsageProvider(id:)
    model.commitAccount(AccountInstance(id: "claude#abc123", kind: .claude))
    XCTAssertEqual(model.orderedProviders.map(\.id).prefix(2), ["claude", "claude#abc123"])
    XCTAssertTrue(model.accounts.contains { $0.id == "claude#abc123" })
}

func test_removeAccount_forgetsSnapshotsErrorsPinsAndCredential() async throws {
    let (model, storage, tokens) = makeModelWithExtraClaude()
    model.togglePin(providerId: "claude#abc123", windowLabel: "5h")
    try model.removeAccount(id: "claude#abc123")
    XCTAssertNil(model.snapshotsByProvider["claude#abc123"])
    XCTAssertFalse(model.isPinned(providerId: "claude#abc123", windowLabel: "5h"))
    XCTAssertNil(tokens.load(providerId: "claude#abc123"))
    XCTAssertTrue(try storage.snapshots(providerId: "claude#abc123", since: .distantPast).isEmpty)
}

func test_removeAccount_refusesMachineBoundLegacy() {
    let model = makeModelWithFactory()
    XCTAssertThrowsError(try model.removeAccount(id: "cursor"))
}

func test_renameAccount_updatesDisplayName() {
    let model = makeModelWithFactory()
    model.renameAccount(id: "claude", nickname: "Trabalho")
    XCTAssertEqual(model.orderedProviders.first { $0.id == "claude" }?.displayName, "Claude Code · Trabalho")
}
```

- [ ] **Step 3:**
  - `@Published private(set) var accounts: [AccountInstance]` (seeded from `preferences.accounts`).
  - `var providerFactory: ((AccountInstance) -> [UsageProvider])?` and `var credentialEraser: ((AccountInstance) throws -> Void)?`, both injected by `OkTallyApp`.
  - `commitAccount(_:)`: append, persist, `registry.add`, `scheduler.startLoop` with the stagger offset, and insert the id into `providerOrder` right after the last sibling (materialise the current `orderedProviders` ids first).
  - `removeAccount(id:)`: refuse machine-bound legacy ids; cascade to the GrokBot twin for Cursor; stop loops, remove from the registry, erase credentials, call `storage.deleteSnapshots(providerId:)`, apply `AccountRemoval.cleanup` to `menuBarPins`, the five `QuotaSlot`s and `providerOrder`; reset `forecastSlot` if it points at the removed id; drop entries from the published dicts.
  - `renameAccount(id:nickname:)`: empty string → nil; then `objectWillChange.send()`.
  - `setIdentity(id:email:identityKey:)`.
  - `StorageManaging.deleteSnapshots(providerId:)` with SQL `DELETE FROM snapshots WHERE providerId = ?`.
- [ ] **Step 5:** commit `feat(accounts): add, remove and rename accounts in AppModel`

### Task 2.2: E-mail resolution + backfill for legacy instances

**Files:** Create `Auth/AccountEmailResolver.swift`, `Tests/OkTallyTests/AccountEmailResolverTests.swift`; Modify `Plugins/Claude/ClaudeProfileClient.swift:46-57` (add `static func identity(fromProfile:) -> (email: String?, orgUUID: String?)` + `fetchIdentity(accessToken:)`, sharing the 12h cache), `Auth/OAuthManager.swift:145-153` (also capture the generic `email` claim from `id_token` into `extra["email"]`), `Auth/DeviceCodeFlow.swift:147-153` (same, via `JWT.decodePayload(payload.idToken)`), `Plugins/Cursor/CursorTokenReader.swift` (`readEmail()` → `cursorAuth/cachedEmail`), `Plugins/Antigravity/AntigravityTokenReader.swift` (`readEmail()` → JSON `email` of `antigravityAuthStatus`)

- [ ] **Step 1: failing tests**

```swift
func test_claudeIdentity_readsAccountEmailAndOrg() {
    let json: [String: Any] = ["account": ["email": "Me@Work.com"], "organization": ["uuid": "org-1", "organization_type": "claude_max"]]
    let identity = ClaudeProfileClient.identity(fromProfile: json)
    XCTAssertEqual(identity.email, "Me@Work.com"); XCTAssertEqual(identity.orgUUID, "org-1")
}

func test_codexEmail_fromAccessTokenProfileClaim() {
    let jwt = makeJWT(["https://api.openai.com/profile": ["email": "c@x.com"]])
    XCTAssertEqual(AccountEmailResolver.codexEmail(accessToken: jwt, extra: [:]), "c@x.com")
}

func test_oauthManager_storesEmailClaimFromIdToken() async throws {
    // stub token endpoint whose id_token payload has "email": "g@x.com"; expect token.extra["email"] == "g@x.com"
}

func test_cursorReader_readsCachedEmail() throws { /* temp state.vscdb with cursorAuth/cachedEmail */ }
func test_antigravityReader_readsAuthStatusEmail() throws { /* temp db with antigravityAuthStatus JSON */ }
```

- [ ] **Step 3:** `AccountEmailResolver.resolve(_ account:) async -> (email: String?, identityKey: String?)`, switching on kind:
  - claude → profile (`identityKey = email|orgUUID`)
  - codex → `extra["email"]` ?? access-token claim `https://api.openai.com/profile.email`
  - supergrok → `extra["email"]`
  - cursor legacy → `readEmail()`
  - antigravity legacy → `readEmail()`
  - API keys → handled in Phase 4

  `AppModel.apply(.success)`: when the account has `email == nil`, launch `resolveIdentityIfMissing(id)` once per launch (a `Set<String>` guard).
- [ ] **Step 5:** commit `feat(accounts): resolve account e-mail after login and backfill legacy`

### Task 2.3: Preferences panes parameterized by instance id

**Files:** Modify `UI/PreferencesView.swift` (`@State :24-38`, `isConfigured :146-160`, `detailContent :165-207`, panes `:211-457`, `load :502-513`, logins `:524-562`), `UI/DesignSystem/ProviderSidebarRow.swift`, `UI/ProviderPaneScaffold.swift`; Create `Core/AccountPaneRouting.swift` + `Tests/OkTallyTests/AccountPaneRoutingTests.swift`

- [ ] **Step 1: failing tests** (pure routing extracted so the switch is testable)

```swift
func test_route_dispatchesByKind() {
    XCTAssertEqual(AccountPaneRouting.route(for: "claude#abc123"), .claude(instanceId: "claude#abc123"))
    XCTAssertEqual(AccountPaneRouting.route(for: "cursor-grokbot#abc123"), .grokbot(instanceId: "cursor-grokbot#abc123"))
    XCTAssertEqual(AccountPaneRouting.route(for: "ghost"), .unknown)
}

func test_canRemove() {
    XCTAssertFalse(AccountPaneRouting.canRemove("cursor"))
    XCTAssertTrue(AccountPaneRouting.canRemove("claude"))
    XCTAssertTrue(AccountPaneRouting.canRemove("cursor#abc123"))
    XCTAssertFalse(AccountPaneRouting.canRemove("cursor-grokbot#abc123")) // follows its Cursor
}
```

- [ ] **Step 3:**
  - Replace `case .provider("claude")…` with `switch AccountPaneRouting.route(for: id)`. Each pane function takes `instanceId`.
  - Replace the booleans with `@State loggedIn: Set<String>`, `claudeSessions: [String: ManualCodeSession]`, `pastedCodes: [String: String]`, `deviceCodes: [String: DeviceCodeInfo]`, `apiKeyFields: [String: String]`.
  - `load()` iterates `appModel.accounts`. `isConfigured(id)` switches on kind.
  - Add an "Conta" header section in `ProviderPaneScaffold`: e-mail (secondary text), nickname `AutoSaveField` → `appModel.renameAccount`, and "Remover conta…" (destructive, `confirmationDialog`: "Remove a conta, o histórico e os pins") when `canRemove`.
  - `ProviderSidebarRow` gains `subtitle: String?` (the e-mail, caption, truncating middle).
  - Section header gets a "+" `Menu` listing `AccountKind.addableKinds`, hidden while empty (it is empty until Phase 3).
- [ ] **Step 4:** manual: every legacy pane looks and behaves the same; rename shows "Claude Code · Trabalho" in sidebar/popover/notch/alerts.
- [ ] **Step 5:** commit `feat(prefs): per-account panes with nickname, e-mail and removal`; CHANGELOG "Added: account nicknames and e-mail labels".

---

# Phase 3 — OAuth kinds (Claude, Codex, SuperGrok)

### Task 3.1: Per-instance single-flight proof

**Files:** `Tests/OkTallyTests/OAuthManagerTests.swift` (test-only; production is already per-instance at `OAuthManager.swift:112-120`)

- [ ] **Step 1: test**

```swift
func test_refresh_isSingleFlightPerInstance_notAcrossInstances() async throws {
    URLProtocolStub.resetRequestCounts()
    URLProtocolStub.stubResponses[config.tokenURL] = (tokenJSON, 200)
    let store = InMemoryTokenStore()
    for id in ["codex", "codex#abc123"] {
        try store.save(OAuthToken(accessToken: "old", refreshToken: "rt-\(id)", expiresAt: .distantPast, extra: [:]), providerId: id)
    }
    let manager = OAuthManager(store: store, session: makeSession())
    async let a1 = manager.validAccessToken(providerId: "codex", config: config.forInstance("codex"))
    async let a2 = manager.validAccessToken(providerId: "codex", config: config.forInstance("codex"))
    async let b1 = manager.validAccessToken(providerId: "codex#abc123", config: config.forInstance("codex#abc123"))
    _ = try await (a1, a2, b1)
    XCTAssertEqual(URLProtocolStub.requestCount(for: config.tokenURL), 2)
}
```

- [ ] **Step 4–5:** green without prod changes (if red, fix the keying); commit `test(oauth): refresh single-flight is per account instance`

### Task 3.2: Add-account draft flow + dedup commit

**Files:** Create `App/AccountEnrollment.swift`, `Tests/OkTallyTests/AccountEnrollmentTests.swift`; Modify `UI/PreferencesView.swift`

- [ ] **Step 1: failing tests**

```swift
func test_enroll_commitsWhenIdentityIsNew() async throws {
    let env = EnrollmentEnv(existing: [AccountInstance(id: "claude", kind: .claude, identityKey: "a@x.com|o1")])
    env.resolver.next = ("b@x.com", "b@x.com|o1")
    let result = await env.enrollment.finish(draftId: "claude#abc123", kind: .claude)
    XCTAssertEqual(result, .committed)
    XCTAssertEqual(env.model.accounts.last?.email, "b@x.com")
}

func test_enroll_duplicateIsRefusedAndCredentialDeleted() async throws {
    let env = EnrollmentEnv(existing: [AccountInstance(id: "claude", kind: .claude, identityKey: "a@x.com|o1")])
    try env.tokens.save(OAuthToken(accessToken: "t", refreshToken: nil, expiresAt: nil, extra: [:]), providerId: "claude#abc123")
    env.resolver.next = ("a@x.com", "a@x.com|o1")
    XCTAssertEqual(await env.enrollment.finish(draftId: "claude#abc123", kind: .claude), .duplicate(email: "a@x.com"))
    XCTAssertNil(env.tokens.load(providerId: "claude#abc123"))
    XCTAssertFalse(env.model.accounts.contains { $0.id == "claude#abc123" })
}

func test_enroll_unresolvableIdentity_commitsWithoutEmail() async { /* resolver returns (nil,nil) → committed; nickname prompt */ }
```

- [ ] **Step 3:** `AccountEnrollment.beginDraft(kind:) -> String` (`AccountID.nextId`) and `finish(draftId:kind:) async -> Result { committed, duplicate(email), failed }`. UI: "+" → kind → the sidebar shows a transient draft row + pane using the same per-instance login buttons (Claude manual code, Codex browser, SuperGrok device code) with `ClaudeOAuth.config.forInstance(draftId)` etc.; on token saved → `finish`. Cancel/abandon → `tokenStore.delete(draftId)`.
- [ ] **Step 5:** commit `feat(accounts): enroll extra OAuth accounts with e-mail dedup`

### Task 3.3: Enable kinds + per-instance Codex analytics

**Files:** `Core/AccountKind.swift` (`addableKinds = [.claude, .codex, .supergrok]`), `App/OkTallyApp.swift:82-88`, `App/AppModel.swift` (`analyticsLoaders` registered per Codex instance on commit, removed on remove), tests in `AppModelTests`

- [ ] Test: after committing `codex#abc123`, `analyticsProviderIds` contains it; Claude/OpenCode loaders remain only on legacy ids (local disk sources are machine-wide — comment in PT).
- [ ] Commit `feat(accounts): multiple Claude, Codex and SuperGrok accounts`; CHANGELOG "Added: multiple accounts per provider (Claude, Codex, SuperGrok)". Note: Codex login uses the fixed port 1455, so concurrent Codex logins are impossible; the existing `portInUse` error covers it.

---

# Phase 4 — API-key kinds (OpenRouter, MiniMax; OpenCode pending decision)

### Task 4.1: Secrets and region per instance

**Files:** `Preferences/PreferencesStore.swift:54-59,100-155`, `PreferencesStoreTests.swift`

- [ ] **Step 1: failing tests**

```swift
func test_apiKey_legacyInstanceUsesLegacyMigrationPath() throws {
    let kv = FakeKeyValueStore(); kv.set("sk-legacy", forKey: "openRouterAPIKey")
    let store = makeStore(kv: kv)
    XCTAssertEqual(store.apiKey(instanceId: "openrouter"), "sk-legacy")
}

func test_apiKey_extraInstanceIsIsolated() throws {
    let store = makeStore()
    try store.setAPIKey("sk-1", instanceId: "openrouter")
    try store.setAPIKey("sk-2", instanceId: "openrouter#abc123")
    XCTAssertEqual(store.apiKey(instanceId: "openrouter"), "sk-1")
    XCTAssertEqual(store.apiKey(instanceId: "openrouter#abc123"), "sk-2")
}

func test_minimaxRegion_perInstance_legacyFallsBackToOldKey() {
    let kv = FakeKeyValueStore(); kv.set("china", forKey: "minimaxRegionRaw")
    let store = makeStore(kv: kv)
    XCTAssertEqual(store.minimaxRegionRaw(instanceId: "minimax"), "china")
    XCTAssertEqual(store.minimaxRegionRaw(instanceId: "minimax#abc123"), "global")
}
```

- [ ] **Step 3:** `apiKey(instanceId:)`: legacy id → existing `migratedSecret(providerId: kind, legacyKey:)`; extra → `secretStore.load(providerId: instanceId)`. Existing named accessors delegate (no call-site churn). Region key `minimaxRegionRaw.<id>` for extras. The factory passes `{ preferences.apiKey(instanceId: id) }`.
- [ ] Commit `feat(prefs): API keys and MiniMax region per account instance`

### Task 4.2: Key fingerprint dedup + OpenRouter label

**Files:** `Core/AccountInstance.swift` (`AccountDedup.fingerprint(apiKey:)` via CryptoKit → `"key:" + 16 hex`), `Plugins/OpenRouter/OpenRouterAPIClient.swift` (`fetchKeyLabel` → `GET https://openrouter.ai/api/v1/key` → `data.label`; verify the field live first), tests.

- [ ] Tests: the same key on two instances → duplicate; the fingerprint never contains the key; the stubbed OpenRouter label is used as `email`-slot display text (stored in `email`? No — add `AccountInstance.autoLabel: String?`, and `AccountLabel` prefers nickname → email → autoLabel → ordinal).
- [ ] Commit `feat(accounts): dedup API-key accounts by fingerprint`

### Task 4.3: Enable OpenRouter + MiniMax

- [ ] `addableKinds += [.openrouter, .minimax]`; the key pane's commit path for a draft = save the key under the draft id → `finish` (dedup by fingerprint). Commit + CHANGELOG.

### Task 4.4: OpenCode — BLOCKED on owner decision

`OpenCodeUsageProvider` estimates from the machine-local `opencode.db`; the key only gates `isAuthenticated`. A second OpenCode account would show identical numbers. Options: (a) keep single-account (recommended, like MiMo); (b) allow it with a notice "estimativa local compartilhada". Do not implement until decided.

---

# Phase 5 — Antigravity (app-owned Google OAuth for extra accounts)

### Task 5.0: Live verification gate (no code)

With `curl` + a browser, confirm that the Antigravity client (`AntigravityUsageProvider.swift:41`, note: this is Antigravity's own client `1071006060591-…`, not gemini-cli's) accepts `redirect_uri=http://localhost:51121/oauth-callback` with `access_type=offline&prompt=consent`, PKCE S256, scopes `cloud-platform userinfo.email userinfo.profile cclog experimentsandconfigs`, and returns a `refresh_token` + `id_token`. If Google rejects `localhost`, retry with `http://127.0.0.1:51121/oauth-callback`. Record the result in `docs/superpowers/research/multi-account-antigravity.md`.

### Task 5.1: `OAuthConfig` gains client secret + extra authorize params

**Files:** `Auth/OAuthConfig.swift`, `Auth/BrowserOAuthFlow.swift:27-36,59-63`, `Auth/OAuthManager.swift:76-83,126-131`, tests `OAuthManagerTests`, new `BrowserOAuthFlowConfigTests`

- [ ] **Step 1: failing tests**

```swift
func test_exchangeAndRefresh_sendClientSecretWhenConfigured() async throws {
    // URLProtocolStub captures body; config with clientSecret "s3cr3t" → body contains "client_secret=s3cr3t"
}

func test_configWithoutSecret_bodyUnchanged() async throws {
    // existing Codex config → no client_secret key (regression guard)
}

func test_redirectConfig_preservesSecretAndExtras() {
    let c = AntigravityOAuth.config
    let r = BrowserOAuthFlow.redirectConfig(from: c, redirect: "http://localhost:51121/oauth-callback")
    XCTAssertEqual(r.clientSecret, c.clientSecret); XCTAssertEqual(r.providerId, c.providerId)
}
```

- [ ] **Step 3:** add `var clientSecret: String? = nil` and `var additionalAuthorizeParameters: [String: String] = [:]`. Extract `BrowserOAuthFlow.redirectConfig(from:redirect:)` (today `:59-63` rebuilds the config and would silently drop the new fields). Append the extra params to the authorize URL. `postForm` includes `client_secret` when non-nil.
- [ ] Commit `feat(oauth): optional client secret and extra authorize params`

### Task 5.2: `AntigravityOAuth` + dual credential source

**Files:** Create `Plugins/Antigravity/AntigravityOAuth.swift`; Modify `Plugins/Antigravity/AntigravityUsageProvider.swift:41-62,87-118`; tests `AntigravityUsageProviderTests`, `AntigravityOAuthTests`

- [ ] **Step 1: failing tests**

```swift
func test_appOwnedInstance_usesOAuthManagerTokenNotIDE() async throws {
    let store = InMemoryTokenStore()
    try store.save(OAuthToken(accessToken: "app-tok", refreshToken: "rt", expiresAt: .distantFuture, extra: [:]), providerId: "antigravity#abc123")
    // stub summaryURL 200; assert request Authorization == "Bearer app-tok" and snapshot.providerId == "antigravity#abc123"
}

func test_legacyInstance_stillReadsIDE() async throws { /* existing behaviour with FakeTokenReader */ }
```

- [ ] **Step 3:** move client id/secret/token URL into `AntigravityOAuth` (keeping the PT comment about RFC 8252 §8.5). `AntigravityOAuth.config`: authorize `https://accounts.google.com/o/oauth2/v2/auth`, token `https://oauth2.googleapis.com/token`, redirect per Task 5.0, `redirectPort: 51121`, extras `access_type=offline`, `prompt=consent`. Provider `enum CredentialSource { case ide(AntigravityTokenReading), appOwned(OAuthManaging, TokenStoring) }`; `.appOwned` calls `oauthManager.validAccessToken(providerId: id, config: AntigravityOAuth.config.forInstance(id))` (Google doesn't rotate refresh tokens; `makeToken` keeps `previousRefresh` — already correct). E-mail: the `id_token` `email` claim (captured by Task 2.2), fallback `GET https://www.googleapis.com/oauth2/v2/userinfo`.
- [ ] Commit `feat(antigravity): app-owned Google login for extra accounts`

### Task 5.3: Enable Antigravity

- [ ] `addableKinds += [.antigravity]`; the add pane shows a PT warning: "Login direto na Google fora do IDE pode violar os termos do Antigravity; use por sua conta." CHANGELOG.

---

# Phase 6 — Cursor (deep-login PKCE polling) + GrokBot twin

**Decision:** option (a), Cursor's browser deep-login with PKCE and polling, gives OkTally its own Cursor session independent of the IDE. Evidence: implemented by 9router (issue #253), cursor-for-android and cursed-gateway (`lib/cursor/account`). Flow: open `https://cursor.com/loginDeepControl?challenge=<S256>&uuid=<uuid>&mode=login&redirectTarget=cli`, poll `GET https://api2.cursor.sh/auth/poll?uuid=…&verifier=…` (404 until done, then `{accessToken, refreshToken}`), session JWT ≈60 days.

Option (b), copying the IDE's token, was rejected. A read-only check of the local `state.vscdb` shows `cursorAuth/accessToken == cursorAuth/refreshToken` (one session JWT), so a captured copy is the IDE's own session. Switching accounts in the IDE (the whole point of (b)) logs that session out, and OkTally cannot refresh independently. The legacy `cursor` instance keeps reading the IDE unchanged.

### Task 6.0: Live verification gate (no code)

Verify by hand, and record in `docs/superpowers/research/multi-account-cursor.md`:
1. The poll response shape.
2. That the token works on `GetCurrentPeriodUsage` and `GetSandUsageStatus`.
3. The refresh path. Candidates: `POST https://api2.cursor.sh/auth/exchange_user_api_key` with `Authorization: Bearer <refreshToken>` (per 9router), or `POST https://api2.cursor.sh/oauth/token` with `grant_type=refresh_token`. If neither works, the fallback is expiry → `needsReauth`.
4. An e-mail source. Candidate: `GET https://cursor.com/api/auth/me` with cookie `WorkosCursorSessionToken=<sub-after-|>%3A%3A<accessToken>`. If it doesn't work, the fallback is a required nickname.

### Task 6.1: `CursorDeepLoginFlow`

**Files:** Create `Plugins/Cursor/CursorDeepLoginFlow.swift`, `Tests/OkTallyTests/CursorDeepLoginFlowTests.swift`

- [ ] **Step 1: failing tests**

```swift
func test_loginURL_containsChallengeUuidAndMode() {
    let start = CursorDeepLoginFlow.makeStart(verifier: "v", uuid: "u-1")
    let items = URLComponents(url: start.browserURL, resolvingAgainstBaseURL: false)!.queryItems!
    XCTAssertEqual(items.first { $0.name == "challenge" }?.value, PKCE.challenge(for: "v"))
    XCTAssertEqual(items.first { $0.name == "uuid" }?.value, "u-1")
    XCTAssertEqual(items.first { $0.name == "mode" }?.value, "login")
}

func test_poll_404ThenSuccess_savesTokenUnderInstance() async throws {
    // URLProtocolStub sequence: 404, 404, 200 {"accessToken":"a","refreshToken":"r"}; sleep stub no-op
    // expect tokenStore.load("cursor#abc123")?.accessToken == "a", expiresAt == JWT exp (or nil if not a JWT)
}

func test_poll_givesUpAfterMaxAttempts() async { /* all 404 → throws OAuthError.loginTimeout */ }
```

(Extend `URLProtocolStub` with a per-URL response queue; `stubResponses` stays for existing tests.)

- [ ] **Step 3:** `final class CursorDeepLoginFlow { init(tokenStore:session:sleep:) ; func begin() -> Start ; func poll(_ start: Start, instanceId: String) async throws -> OAuthToken }`, backoff 1 s → ×1.5 → max 10 s, 150 attempts.
- [ ] Commit `feat(cursor): deep-login PKCE polling flow`

### Task 6.2: Cursor/GrokBot credential source per instance

**Files:** `Plugins/Cursor/CursorTokenReader.swift`, `CursorUsageProvider.swift`, `GrokBotUsageProvider.swift`, `App/ProviderFactory.swift`, tests

- [ ] Tests: `KeychainCursorTokenSource(instanceId:tokenStore:)` conforms to `CursorTokenReading` (`readAccessToken` → stored token unless expired; `readMembershipType` → nil). GrokBot `cursor-grokbot#abc123` uses the token of `cursor#abc123`. The factory for `cursor#abc123` wires both with the same source. Removing `cursor#abc123` removes its twin (AppModel test).
- [ ] Refresh per Task 6.0; if there's no refresh, an expired token raises a `needsReauth`-classified error (`ProviderErrorPresentation.classify`).
- [ ] Commit `feat(cursor): app-owned Cursor accounts with GrokBot twin`

### Task 6.3: Enable Cursor

- [ ] `addableKinds += [.cursor]`; the pane explains "Sessão própria do OkTally — trocar de conta no Cursor não afeta esta conta." CHANGELOG.

---

# Phase 7 — Labels across popover, notch, pins, alerts

### Task 7.1: `AccountDirectory` + glyph ordinal

**Files:** `Core/AccountInstance.swift` (`AccountDirectory`, `AccountDirectoryHolder` mirroring `UsageColorScaleHolder`), `UI/ProviderPalette.swift`, `UI/MenuBarLabelModel.swift:119-120`, tests `AccountDirectoryTests`, `MenuBarLabelModelTests`

- [ ] **Step 1: failing tests**

```swift
func test_glyph_secondSiblingGetsOrdinal() {
    let dir = AccountDirectory(accounts: [AccountInstance(id: "claude", kind: .claude),
                                          AccountInstance(id: "claude#abc123", kind: .claude)])
    XCTAssertEqual(dir.glyph(for: "claude"), "C")
    XCTAssertEqual(dir.glyph(for: "claude#abc123"), "C2")
}

func test_menuBarSegment_usesDirectoryGlyph() {
    AccountDirectoryHolder.current = AccountDirectory(accounts: [.init(id: "claude", kind: .claude), .init(id: "claude#abc123", kind: .claude)])
    defer { AccountDirectoryHolder.current = .empty }
    XCTAssertEqual(MenuBarLabelModel.segment(providerId: "claude#abc123", shape: rolling(50)).glyph, "C2")
}
```

- [ ] **Step 3:** AppModel sets the holder whenever `accounts` changes. `ProviderPalette.glyph(forId:)` consults the holder. Single-account users get unchanged glyphs.
- [ ] Commit `feat(ui): distinguish sibling accounts in glyphs`

### Task 7.2: Labels in pickers, pins list, notch, alerts

**Files:** `UI/PreferencesView.swift:959,982,999`, `UI/Notch/NotchHUDView.swift:246-247`, `UI/AnalyticsDashboardView.swift:21-22`, `Notifications/AlertNotificationFormatter.swift:6`, tests `AlertNotificationFormatterTests`, `NotchHUDModelTests`

- [ ] Tests: an alert for `claude#abc123` with nickname "Trabalho" has title `"Claude Code · Trabalho — 5h"` (it flows from `Scheduler` `provider.displayName`, so just assert end-to-end with `LabeledProvider`). Picker text is `"Claude Code · Trabalho · 5h"`.
- [ ] Most sites already read `displayName`, so this task is mostly verification plus the three `providerName` helpers. Add a compact variant (`AccountDirectory.shortLabel`, e.g. "Trabalho") for the notch where width is tight.
- [ ] Manual QA checklist: two Claude accounts → sidebar, popover cards, hero, notch wings/panel, menu-bar pins, forecast card, analytics tab, notifications all show distinct labels; removing one clears its pins/slots.
- [ ] Commit `feat(ui): account labels across popover, notch, pins and alerts`; CHANGELOG release entry.

---

## Risks / open questions

1. OpenCode multi-account is meaningless with the local estimator (Task 4.4, owner decision).
2. Claude dedup by e-mail alone would block personal + Team orgs on the same e-mail. The plan uses `email|orgUUID`; confirm.
3. Antigravity third-party login may violate the Antigravity ToS; community reports of Google blocking accounts. `localhost` vs `127.0.0.1` redirect is unverified (Task 5.0).
4. Cursor refresh and e-mail endpoints are undocumented (Task 6.0); the fallback is re-login + nickname.
5. Claude `/api/oauth/usage` 429s: two Claude accounts double the call volume. The stagger only spreads the first fetch; the loops can drift back together.
6. Removal deletes history (by design); the confirmation dialog must say so.
7. `PreferencesView` (1,112 lines) has no unit tests; logic is pulled into `AccountPaneRouting` / `AccountEnrollment` to keep TDD honest.
8. E-mails are stored in UserDefaults (PII, not secret).
9. Codex's fixed port 1455 serializes Codex logins.

---

## Decisões do dono (2026-09-28) — sobrepõem o texto acima

1. **OpenCode fica com uma conta só** (como o MiMo). Task 4.4 = não implementar; `addableKinds` nunca inclui `.opencode`.
2. **Dedup do Claude é só por e-mail** (lowercased), não `email|orgUUID`. Ajustar Task 2.2/3.2: `identityKey` do Claude = e-mail.
3. **Antigravity entra, com aviso** na tela de adicionar conta (Fase 5 completa).
4. **Execução: tudo num branch só**, um merge no final (não uma release por fase). Cada fase ainda termina com `swift test` verde e commit próprio.
