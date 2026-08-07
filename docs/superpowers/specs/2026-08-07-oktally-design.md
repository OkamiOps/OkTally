# OkTally — Design

## 1. Overview & Goals

OkTally is a native macOS menu bar application that tracks usage and estimates cost across
multiple AI subscriptions (Claude Code, Codex CLI, Cursor Pro, OpenRouter, MiniMax, MiMo,
OpenCode Zen/Go, and others added later), and alerts the user before a time-boxed quota
(e.g. Claude's rolling 5-hour and weekly windows) is exhausted, so they can switch models in
time.

**Primary pain point solved:** today the user relies on `npx ccusage`, which miscalculates
usage, and has no advance warning before Claude's 5-hour quota resets — they only find out
after being blocked. OkTally reads the same real usage data the official CLIs use internally
(via locally stored OAuth credentials / API keys) rather than estimating from local logs.

**Secondary goal:** since most of these are flat-fee subscriptions, OkTally estimates an
"equivalent cost" for actual usage based on live OpenRouter pricing, so the user can judge
whether a subscription is worth it and compare providers on a common basis.

**Non-goals:** no cloud sync, no multi-user support, no mobile app. Single user, local-only,
macOS only.

## 2. Architecture

- **Stack:** Swift native (SwiftUI + AppKit), `NSStatusItem` menu bar app. No Node/Electron
  dependency — every plugin is Swift code, run in-process.
- **Core app:** single process, registered as a `LaunchAgent` to start on login, runs
  continuously in the background.
- **Plugin Registry:** each provider (Claude, Codex, Cursor, OpenRouter, MiniMax, MiMo,
  OpenCode) implements the `UsageProvider` protocol (see §3). New providers are added by
  writing a new plugin, without touching core app, UI, or alert logic.
- **Scheduler:** calls `fetchSnapshot()` on each registered plugin at a per-plugin refresh
  interval (e.g. Claude every ~60s during recent activity, others every 5–15 min) to avoid
  rate-limiting the undocumented endpoints several of these rely on.
- **Pricing Engine:** periodically fetches `GET https://openrouter.ai/api/v1/models` (public,
  no auth required), caches the per-model prompt/completion pricing table. Used by every
  plugin that reports granular token usage to compute an "equivalent cost".
- **Storage:** local SQLite database at
  `~/Library/Application Support/OkTally/usage.sqlite`, storing every `ProviderSnapshot`
  received, for history/trend display and for the Alert Engine to detect threshold crossings.
- **Alert Engine:** generic, operates over `QuotaWindow`/`QuotaShape` values (not aware of
  specific providers), triggers native notifications and drives the menu bar icon's
  color/percentage.
- **UI:**
  - Menu bar icon: color reflects the worst state across all active quota windows
    (green < 70%, yellow 70–90%, red ≥ 90%), with the most critical percentage shown next to
    the icon.
  - Popover (on click): one card per provider, each card listing its `QuotaWindow`s (progress
    bar + time to reset) and the estimated cost for the current period.
  - Preferences window: per-window alert thresholds, refresh intervals, API keys (MiniMax,
    MiMo, OpenCode, OpenRouter), provider display order.

## 3. Plugin Protocol & Data Model

```swift
protocol UsageProvider {
    var id: String { get }              // "claude", "codex", "cursor", "openrouter", "minimax", "mimo", "opencode"
    var displayName: String { get }
    var authMethod: AuthMethod { get }  // .keychain(service:), .localFile(path:), .apiKey, .oauthSession
    var refreshInterval: TimeInterval { get }

    func isAuthenticated() async -> Bool
    func fetchSnapshot() async throws -> ProviderSnapshot
}

struct ProviderSnapshot {
    let providerId: String
    let fetchedAt: Date
    let quotas: [QuotaWindow]        // a provider can report more than one simultaneous window
    let usageDetail: [UsageDetail]?  // granular tokens/requests, when available, for cost estimation
}

struct QuotaWindow {
    let label: String                // "5h", "weekly", "weekly-fable", "weekly-opus" — whatever the provider/CLI calls it
    let shape: QuotaShape
}

enum QuotaShape {
    case rollingWindow(used: Double, limit: Double, windowStart: Date, resetAt: Date)  // Claude 5h/weekly, and other providers with rolling windows
    case periodicCounter(used: Double, limit: Double, resetAt: Date)                   // Codex, Cursor
    case creditBalance(remaining: Decimal, currency: String)                           // OpenRouter, MiniMax, MiMo, OpenCode
    case meteredOnly(costAccrued: Decimal)                                             // pay-as-you-go, no ceiling
}

struct UsageDetail {
    let modelId: String        // mapped to an OpenRouter model slug for pricing lookup
    let promptTokens: Int
    let completionTokens: Int
}
```

Design notes:

- `ProviderSnapshot.quotas` is a **list**, not a single value, because multiple providers
  (not just Claude) report more than one simultaneous quota window. Claude specifically
  reports three: 5h (all models), weekly (all models), and weekly for a specific model tier
  (e.g. Fable/Opus).
- The UI renders each `QuotaWindow` as its own progress element inside the provider's card
  (e.g. the "Claude MAX 5X" card shows three bars: 5h / weekly / weekly-fable).
- The Alert Engine evaluates thresholds **per window**, not per provider — so a notification
  can say specifically "weekly-fable window at 92%" rather than a vague provider-level alert.
- Only `.rollingWindow`, `.periodicCounter`, and `.creditBalance` (all have a defined limit)
  participate in alerting. `.meteredOnly` never alerts — it only contributes to the cost
  total.
- Cost estimation: whenever `usageDetail` is present, each entry's `modelId` is matched
  against the OpenRouter pricing table and the equivalent cost
  (`promptTokens * promptPrice + completionTokens * completionPrice`) is computed and stored
  alongside the snapshot — including for subscription providers, where this is purely
  informational (e.g. "this week on Claude you extracted ~$47 of equivalent value from a
  $100/mo plan").

## 4. v1 Plugins

| Provider | Auth | Usage source |
|---|---|---|
| **Claude Code** | Reads OAuth token from macOS Keychain (`service: "Claude Code-credentials"`), falls back to `~/.claude/.credentials.json` if Keychain read fails | `GET api.anthropic.com/api/oauth/usage` with header `anthropic-beta: oauth-2025-04-20` and `Authorization: Bearer <token>` → returns 5h, weekly, and weekly-per-tier windows. This is the same undocumented endpoint the CLI's `/usage` command and third-party menu bar apps (Usagebar, CodeQuota) use. |
| **Codex CLI** | Reads local `auth.json` written by the Codex CLI | Replicates whatever the CLI's `/status` command fetches internally. Exact endpoint **to be confirmed during implementation** by inspecting the open-source CLI. |
| **Cursor Pro** | Session cookie or Admin API key, depending on what the plan exposes | `cursor.com/api/usage` or `GetCurrentPeriodUsage` via `api2.cursor.sh`. Exact auth/shape **to be confirmed during implementation**. |
| **OpenRouter** | User-supplied API key (entered in Preferences) | `GET /api/v1/credits` (balance) + `GET /api/v1/models` (pricing table — also used by every other plugin) |
| **MiniMax** | User-supplied Token Plan API key | Platform usage/balance endpoint. Exact path **to be confirmed during implementation**. |
| **MiMo** | User-supplied Token Plan API key (`tp-xxxxx`) | Platform usage/balance endpoint. OpenAI/Anthropic-compatible chat endpoints are confirmed; the balance-query endpoint **to be confirmed during implementation**. |
| **OpenCode Zen/Go** | `OPENCODE_API_KEY` (shared between Zen and Go) | Credits/usage endpoint. Exact path **to be confirmed during implementation**. |

Claude and OpenRouter have fully confirmed, documented-by-precedent endpoints and serve as
the reference implementation for the plugin pattern. The remaining plugins' exact
balance/usage endpoints are marked as implementation-time investigation (inspecting each
CLI/network traffic), since comparable third-party tools already do this successfully.

## 5. Alerting

- Thresholds are configurable **per `QuotaWindow`** (default: 70% / 90% / 100%), and can
  differ by provider/window (e.g. 80% on Claude's 5h window, 95% on OpenRouter's credit
  balance).
- Crossing a threshold triggers a native macOS notification: title = provider + window name,
  body = current percentage + time to reset (e.g. "82% of 5h window — resets in 2h14min").
- Notifications are edge-triggered (fire only when a threshold is newly crossed, not on every
  refresh) to avoid spam.
- The menu bar icon always reflects the worst state across all active windows: green (<70%),
  yellow (70–90%), red (≥90%), with the most critical percentage shown as the icon's label.

## 6. Storage

- SQLite database at `~/Library/Application Support/OkTally/usage.sqlite`.
- Every `ProviderSnapshot` fetched is persisted, enabling a simple trend view in the popover
  (e.g. a 7-day cost sparkline) and giving the Alert Engine a previous-snapshot baseline to
  detect threshold crossings against.
- Fully local — no sync, no cloud backend. This is personal, single-machine use.

## 7. Error Handling

Each plugin fails in isolation — one broken provider never affects the others or crashes the
app:

- **Expired/revoked token:** the provider's card shows a "re-authenticate" state instead of a
  stale or broken value.
- **Rate limiting (429):** exponential backoff per plugin; the app never hammers an endpoint
  known to rate-limit aggressively (confirmed behavior of Claude's usage endpoint).
- **Endpoint/format changes:** since most of these are undocumented, a parsing failure fails
  that single snapshot fetch, logs locally, and leaves every other plugin unaffected.

## 8. Build Order

Each phase produces something usable on its own:

1. Core: menu bar shell, `UsageProvider` protocol, Scheduler, Alert Engine, Storage, Pricing
   Engine (OpenRouter) — no plugins yet.
2. Claude Code plugin — proves the protocol end-to-end (Keychain auth, three simultaneous
   `rollingWindow`s, alerting, colored icon). Solves the user's primary pain point first.
3. OpenRouter plugin — proves `creditBalance` and supplies the pricing table every other
   plugin depends on.
4. Codex CLI plugin — proves `periodicCounter` and a second local-credential auth pattern.
5. Cursor, MiniMax, MiMo, OpenCode plugins — same validated pattern, added as each provider's
   exact endpoint is confirmed.

## 9. Testing

- `UsageProvider` fakes/mocks to test the Alert Engine and UI without hitting real APIs.
- Captured real-response JSON fixtures per endpoint, to test parsing in isolation.
- Manual test of the full alert flow: simulate a snapshot crossing a threshold and confirm
  both the notification and the icon color change.
