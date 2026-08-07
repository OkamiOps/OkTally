# OkTally Plan 2 — Six Provider Plugins + Own-OAuth Infrastructure

## 1. Overview & Goals

Plan 2 extends OkTally (see `2026-08-07-oktally-design.md` for the base architecture) with
six new/retrofitted provider plugins — Codex, Cursor, MiniMax, SuperGrok, MiMo, OpenCode —
plus the shared infrastructure they need: app-owned OAuth login, an estimated-quota shape
for providers without a live quota API, and local usage estimation.

Research grounding: `docs/superpowers/research/plan2-*.md` (one report per provider, with
per-claim confidence levels). The design below only commits to what those reports support.

**Binding constraint (owner decision):** OkTally must NOT depend on installed CLIs or their
credential files (`~/.codex/auth.json`, `~/.grok/`, Claude Code's Keychain item) — CLIs can
be uninstalled at any time. Every OAuth provider gets a login flow owned by OkTally, with
tokens stored under OkTally's own Keychain entries and refresh managed by the app.
Two sanctioned exceptions, both approved explicitly by the owner:

- **Cursor:** no third-party OAuth flow exists; the plugin reads the token from the Cursor
  app's own store (`~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`,
  key `cursorAuth/accessToken`). Rationale: uninstalling Cursor also ends Cursor usage, so
  the dependency is coherent. Degrades to a "Cursor não detectado" card state when absent.
- **OpenCode local estimate:** reads `~/.local/share/opencode/opencode.db` (per-message
  cost/tokens) as the estimation source. Same rationale and same graceful degradation.

**Quality tiers (owner accepted uneven quality across the six):**

- *Measured:* Codex, MiniMax, Cursor, SuperGrok — live quota from a provider endpoint.
- *Estimated:* MiMo, OpenCode — no live quota API exists today (verified from source code
  and live probing; OpenCode upstream has two open feature requests for one). These render
  with an explicit visual "estimate" treatment and can be promoted to Measured later if the
  owner identifies an app that reads real quota (open question, tracked in the research
  reports) or upstream ships an API.

## 2. New Shared Infrastructure

### 2.1 OAuthManager + TokenStore

- `TokenStore`: stores per-provider OAuth token sets (`accessToken`, `refreshToken`,
  `expiresAt`, plus provider-specific extras like Codex's `account_id`) in the app's own
  Keychain (service `com.oktally.app.oauth.<providerId>`). Protocol-backed for tests.
- `OAuthManager`: runs browser-based flows and refreshes:
  - **PKCE authorization-code + loopback redirect** (Codex, Claude retrofit): opens the
    system browser, listens on a localhost port for the callback, exchanges the code.
  - **Device code (RFC 8628)** (SuperGrok, if viable): displays the user code, polls the
    token endpoint.
  - **Browser flow with localhost callback, non-OAuth payload** (MiMo key issuance): opens
    the provider's authorize URL and receives an encrypted key on a localhost listener —
    shares the loopback-listener plumbing with PKCE but returns a key, not a token set.
  - Automatic refresh: before each plugin fetch, `OAuthManager` hands out a valid access
    token, refreshing transparently when `expiresAt` is near; a failed refresh flips the
    provider card to a "reautenticar" state with a login button.
- Preferences window gains a per-provider auth section: "Entrar…" / "Sair" buttons for
  OAuth providers, key fields for API-key providers (existing pattern).

### 2.2 `QuotaShape.estimated`

New enum case:

```swift
case estimated(used: Double, limit: Double?, basis: EstimationBasis, resetAt: Date?)

enum EstimationBasis: String, Codable {
    case localTokenCount      // summed locally from observed traffic/DB
    case reactiveRateLimit    // inferred from last 429 (limit name + retry-after)
}
```

- `usedPercent` returns a value only when `limit != nil`.
- UI: rendered with a dashed/hatched progress bar and a "~" prefix on the value; tooltip
  "estimativa local, não confirmada pelo provedor".
- Alerts: fire normally, but notification body is prefixed "Estimado: ".
- Codable round-trip covered like the existing four cases.

### 2.3 Local usage estimation

- `LocalUsageEstimator` protocol: `func estimateWindow() throws -> (used: Double, limit: Double?, resetAt: Date?)`.
- MiMo implementation: owner enters plan allowance (Credits) in Preferences; usage is
  accumulated from OkTally-observed traffic where possible and manual adjustment.
- OpenCode implementation: reads `opencode.db` (SQLite, read-only) summing per-message
  cost within the current window; the reactive 429 parser (see 3.6) overrides the estimate
  with authoritative "limit hit, resets at X" whenever one is observed.

## 3. Per-Plugin Specs

### 3.1 Codex (measured — confidence: confirmed from CLI source)

- Auth: OkTally-owned PKCE flow against `auth.openai.com` using the public client id
  `app_EMoamEEZ73f0CkXaXp7hrann`; refresh `POST auth.openai.com/oauth/token`
  (`grant_type=refresh_token`). Optional one-time bootstrap: offer to import an existing
  `~/.codex/auth.json` if detected (convenience only, never required).
- Usage: `GET https://chatgpt.com/backend-api/wham/usage` with `Authorization: Bearer` +
  `ChatGPT-Account-Id` headers. Response carries `plan_type`, `rate_limit.primary_window`
  (5h: `used_percent`, `reset_at`) and `.secondary_window` (weekly), `credits`.
- Shapes: two `rollingWindow`s ("5h", "weekly"); `credits` surfaced as `creditBalance` if
  present.

### 3.2 Cursor (measured — confidence: endpoint medium, schema low; confirm live in implementation)

- Auth: read `cursorAuth/accessToken` from `state.vscdb` (sanctioned exception above).
- Usage: `POST https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage`
  (ConnectRPC/JSON) with bearer token; `GET cursor.com/api/auth/stripe` for plan metadata.
- Shape: `creditBalance` (Cursor Pro is a ~$20/mo credit pool since mid-2025).
- Implementation gate: first task makes one live authenticated call to pin the response
  schema before the parser is written (same pattern as Claude's Task 9 verification step).

### 3.3 MiniMax (measured — confidence: community-documented with real captured responses)

- Auth: Token Plan API key (Preferences field, existing `apiKeyProvider` pattern).
- Usage: `GET https://api.minimax.io/v1/token_plan/remains` (global) /
  `api.minimaxi.com` (China) with `Authorization: Bearer`. Returns per-model
  `current_interval_*` (5h window) and `current_weekly_*` counts, `*_remaining_percent`,
  `remains_time`.
- Shapes: `rollingWindow` ("5h") + `periodicCounter` ("weekly"), aggregated across models
  (worst window wins; per-model detail in the card).
- Region toggle (global/China) in the provider's Preferences section.

### 3.4 SuperGrok (measured, fragile — confidence: low; endpoint reverse-engineered)

- Auth: OAuth against `accounts.x.ai`/`auth.x.ai`. Open problem: no public client id.
  First implementation task is an investigation gate — capture the flow (device-code per
  pi-grok/hermes-agent implementations) and determine a usable client id; if none is
  obtainable without unacceptable fragility, the plugin ships as `estimated`/manual until
  it is.
- Usage: `POST grok.com/grok_api_v2.GrokBuildBilling/GetGrokCreditsConfig` (gRPC-web)
  returning `credit_usage_percent` + reset time (weekly percentage pool).
- Shape: `rollingWindow` ("weekly", percent-based, limit 100).

### 3.5 MiMo (estimated — confidence: high that no live quota path exists today)

- Auth/onboarding: implement the MiMoCode key-issuance flow (browser SSO at
  `platform.xiaomimimo.com/authorize` with X25519/AES-GCM encrypted key return to a
  localhost callback) so the owner never pastes a key manually. The issued `tp-` key is
  stored in Keychain and used for inference-side identification only.
- Quota: `QuotaShape.estimated` with `basis: .localTokenCount`; allowance entered in
  Preferences; per-model Credit ratios from the published pricing table.
- Promotion path documented: console-session cookie API exists but is out of scope.

### 3.6 OpenCode (estimated/reactive — confidence: high that no usage API exists today)

- Auth: `OPENCODE_API_KEY` (Preferences field). The device-code OAuth flow exists but its
  bearer surface has no billing endpoints, so it is not used in this plan.
- Quota: `QuotaShape.estimated` with `basis: .localTokenCount` from `opencode.db`; when a
  429 with `GoUsageLimitError`/`FreeUsageLimitError` JSON (`metadata.limitName`,
  `retry-after`) is observed, the card switches to an authoritative "limite atingido,
  reseta às X" state (`basis: .reactiveRateLimit`) until the reset passes.
- Watch upstream issues #10448/#16017; promote to measured when an API ships.

### 3.7 Claude retrofit (measured — existing plugin, auth swap)

- Replace the Claude Code Keychain read with an OkTally-owned PKCE login against
  Anthropic's OAuth (same public client the CLI uses — community-documented; confirm the
  client id and endpoints at implementation). Existing-credential import offered as
  optional bootstrap only.
- Usage endpoint and shapes unchanged from Plan 1. The still-open schema confirmation
  (Plan 1 pendency) folds into this task's live verification step.

## 4. UI Changes

- Preferences: per-provider sections with login buttons (OAuth) / key fields (API key) /
  allowance field (MiMo) / region toggle (MiniMax).
- Cards: estimated windows render dashed with "~"; "reautenticar" state gets a button that
  triggers the provider's login flow directly; "não detectado" state for Cursor/OpenCode
  local sources absent.
- Menu bar aggregation unchanged; estimated percents participate, measured-vs-estimated is
  distinguishable in the popover, not the icon.

## 5. Error Handling & Degradation

- All new error enums conform to `LocalizedError` (Plan 1 final-review convention).
- OAuth refresh failure → "reautenticar" card state, no crash, other providers unaffected
  (existing per-plugin isolation).
- Local source missing (Cursor DB, opencode.db) → "não detectado" state, provider skipped
  by the scheduler without error noise.
- Undocumented endpoints (Codex wham, Cursor RPC, Grok gRPC-web, MiniMax remains) get the
  same defensive parsing + isolated-failure treatment as Plan 1's Claude endpoint, and
  each plugin's first implementation task pins the real schema with a live call.

## 6. Build Order

1. Shared infra: `TokenStore` (Keychain), `OAuthManager` (PKCE + device-code + refresh),
   `QuotaShape.estimated`, Preferences auth sections.
2. Codex plugin (proves PKCE end-to-end; highest-confidence endpoint).
3. Claude retrofit (reuses the PKCE infra; closes the Plan 1 schema pendency).
4. MiniMax plugin (API key; second measured provider).
5. Cursor plugin (local token read + live schema pin).
6. OpenCode plugin (estimated + reactive 429).
7. MiMo plugin (key-issuance flow + estimated).
8. SuperGrok plugin (investigation gate first; ships measured or degraded per outcome).

Each numbered item is independently shippable; the app remains releasable after every step.

## 7. Testing

- Same conventions as Plan 1: protocol fakes for every I/O seam, fixture JSON per endpoint
  (with `subdirectory: "Fixtures"` lookups), `URLProtocolStub` for HTTP clients, no real
  network/Keychain in tests.
- OAuth flows: token exchange/refresh logic tested against stubbed token endpoints; the
  browser round-trip itself is manual-verification only.
- `estimated` shape: Codable round-trip + formatter + alert-engine tests mirroring the
  existing four shapes.
- SQLite readers (Cursor `state.vscdb`, `opencode.db`): tested against fixture DB files
  built in-test with the real observed schemas.
