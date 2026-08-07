# Cursor Pro usage tracking — research notes

Goal: figure out how OkTally (macOS menu bar app) can read Cursor Pro (individual, non-team) subscription usage programmatically.

Confidence labels used below:
- **confirmed-from-source** — verified directly (local machine inspection, or primary-source docs I fetched)
- **documented-by-community** — stated in a community tool's README/source that I read, but not independently verified against a live request
- **inferred** — reasoned from adjacent facts, not directly observed

## 1. Endpoints

### 1.1 `GET https://cursor.com/api/usage?user={userId}` (legacy)
- **Status**: documented-by-community as still working for individual accounts (this is the endpoint the original Cursor "Usage" VS Code extensions were built around, pre-2025 request-based era).
- **Auth**: browser session cookie `WorkosCursorSessionToken`, format `{userId}::{accessToken}` (URL-encoded as `{userId}%3A%3A{accessToken}` when sent as a `Cookie` header). — documented-by-community
- **Response shape** (legacy, request-count model), field names as reported by community examples:
  ```json
  {
    "gpt-4": { "numRequests": 0, "numRequestsTotal": 0, "numTokens": 0, "maxRequestUsage": 500, "maxTokenUsage": null },
    "gpt-3.5-turbo": { "numRequests": 0, "numRequestsTotal": 0, "numTokens": 0, "maxRequestUsage": null, "maxTokenUsage": null },
    "gpt-4-32k": { "numRequests": 0, "numRequestsTotal": 0, "numTokens": 0, "maxRequestUsage": 50, "maxTokenUsage": null },
    "startOfMonth": "2026-08-01T00:00:00.000Z"
  }
  ```
  — documented-by-community. Note this schema predates Cursor's June 2025 switch to usage-based/credit billing, so it may be stale or only reflect legacy per-model counters that Cursor still returns for backward compatibility. Treat with caution — it's the shape found in older extension code and forum posts, not verified live.

### 1.2 `POST https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage` (current, ConnectRPC-style)
- **Status**: documented-by-community as the newer endpoint the Cursor desktop app itself calls internally; the full path (`aiserver.v1.DashboardService/GetCurrentPeriodUsage`) surfaced via web search of forum/reverse-engineering discussions, not read directly from source. — documented-by-community
- **Auth**: same session/access token, sent as `Authorization: Bearer {accessToken}` (not a cookie) per the `waitkafuka/cursor-api` proxy project's authentication docs. — documented-by-community
- **Response shape**: not confirmed in detail. Community tooling (`Tendo33/cursor-usage-tracker`) references merged fields `totalPercentUsed`, `apiPercentUsed`, `limit`, `used`, `planName`, plus `planUsage.remaining` / `planUsage.used` when normalizing this endpoint's output for its status bar display — but I could not read the literal response JSON from source (GitHub's web view truncated the TS source when fetched). — documented-by-community, lower confidence on exact field names.
- This is a Connect/gRPC-Web style endpoint (`aiserver.v1.*` package), consistent with Cursor's backend being a Go/Connect service — expect `application/proto` or `application/json` (Connect supports both) rather than a plain REST JSON body only.

### 1.3 `GET https://cursor.com/api/auth/stripe` (plan metadata)
- **Status**: documented-by-community, returns Stripe subscription/membership info (plan name, billing cycle end).
- **Auth**: same `WorkosCursorSessionToken` cookie.
- **Response shape**: not fully enumerated by any source I found; expected to include membership type and renewal date based on how `cursorAuth/stripeMembershipType` is cached locally (see §2).

### 1.4 Official documented APIs (cursor.com/docs/api)
- **confirmed-from-source** (fetched cursor.com/docs/api directly): Cursor's *officially documented* APIs are Admin API, Analytics API, AI Code Tracking API, Bugbot API, Cloud Agents API, Origin API, plus TS/Python SDKs. These use API keys (`crsr_...`) via HTTP Basic auth (key as username, empty password) or `Authorization: Bearer` for the Cloud Agents API specifically.
- **All of these are enterprise/team-admin scoped** — the docs give no indication of a per-user quota endpoint for individual Pro accounts. This confirms the three endpoints above (§1.1–1.3), which are *undocumented*, are the only realistic path for an individual Pro user; there is no supported/official API for this use case.

## 2. Where the credential lives locally (macOS)

**confirmed-from-source** — I inspected the user's machine directly:

- Cursor.app is installed at `/Applications/Cursor.app`.
- Session/auth data lives in a SQLite DB (VS Code-style `state.vscdb`) at:
  `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`
  (also `state.vscdb.backup`, `-wal`, `-shm` companion files; this is standard VS Code/Electron `ItemTable` key-value storage, not a custom Cursor format).
- Querying `ItemTable` for keys (values NOT read, per security constraint) shows these Cursor-auth-relevant rows exist:
  - `cursorAuth/accessToken` — the bearer/session token material
  - `cursorAuth/refreshToken`
  - `cursorAuth/cachedEmail`
  - `cursorAuth/cachedSignUpType`
  - `cursorAuth/cachedScopedProfile`
  - `cursorAuth/stripeMembershipType` — cached plan tier string (e.g. would hold something like "pro"), useful to distinguish plan without a network call
  - `cursorAuth/onboardingDate`
- Read pattern (matches what community tools do): open `state.vscdb` read-only with SQLite, `SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken'`. The community tools (`Tendo33/cursor-usage-tracker`) do exactly this via `sql.js` (JS) with a Python fallback, then derive `userId` from `cursorAuth/cachedEmail` / Sentry scope files (`sentry/scope_v3.json`) if not embedded in the token itself.
- For a macOS Swift/Obj-C menu bar app, the practical approach is: read `state.vscdb` with a bundled SQLite library (e.g. `GRDB` or `SQLite.swift`), extract `cursorAuth/accessToken`, and use it directly as a bearer token (no cookie needed) since §1.2 shows the DashboardService accepts `Authorization: Bearer`.
- No separate keychain entry was found for Cursor session tokens — it's stored in this SQLite file in plaintext-ish (VS Code doesn't encrypt `ItemTable` values), which is why extensions read it directly rather than going through Keychain.

**Caveat**: `~/Library/Application Support/Cursor` also holds a normal Chromium/Electron profile (Cookies, Network Persistent State, etc.) — reading `Cookies` directly is a secondary path but the SQLite `state.vscdb` route above is what community tools actually use and is simpler (no Chromium cookie decryption needed).

## 3. Rate limits / plan shape (for OkTally's QuotaShape)

- **confirmed-from-source** (web docs, 2026): Cursor moved off pure request-counting in **June 2025** to **usage-based billing**. Pro ($20/mo) now includes a monthly credit pool roughly equal to the subscription price (i.e. ~$20 of frontier-model usage credits), consumed by token usage priced per-model (e.g. output tokens ~$6/M tokens for some models). After the included credits are exhausted, usage continues as "on-demand" billed usage (unless the user has on-demand spending disabled, in which case they're blocked until renewal).
- This means Cursor Pro today is fundamentally a **dollar-denominated credit balance that resets monthly**, not a simple periodic request counter.
- **Recommended OkTally QuotaShape: `creditBalance`** (a numeric balance, denominated in USD, that depletes with usage and resets on a monthly cycle tied to the Stripe billing date) — this is the best fit.
  - Populate it from the `GetCurrentPeriodUsage` response's `used` / `limit` (or `totalPercentUsed`) fields (§1.2), with `planName` / `cursorAuth/stripeMembershipType` for tier display, and the Stripe billing-cycle-end date from `/api/auth/stripe` (§1.3) as the reset timestamp.
  - `periodicCounter` (a shape that just counts discrete uses against a fixed monthly quota) is a secondary/legacy fit only for the old `gpt-4.numRequests` / `maxRequestUsage` fields (§1.1), which may still be populated for backward compatibility but are not what actually gates a Pro user's access today.
- **inferred**: Because none of this is officially documented or stable, OkTally's Cursor plugin should be built defensively — treat `GetCurrentPeriodUsage`'s exact field names as unconfirmed until a live authenticated request is made and inspected (which I could not do here without using the user's live token, per the security rule against printing/exfiltrating secrets). Recommend the implementation team make one real authenticated request during development (locally, never logging the token) and adjust field mappings from the observed JSON before shipping.

## 4. Summary of source confidence

| Claim | Confidence |
|---|---|
| `cursor.com/api/usage` legacy GET endpoint exists, cookie auth | documented-by-community |
| `api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage` POST endpoint, bearer auth | documented-by-community |
| `cursor.com/api/auth/stripe` GET endpoint for plan metadata | documented-by-community |
| No official/documented API exists for individual-Pro usage (only enterprise Admin/Analytics APIs) | confirmed-from-source (cursor.com/docs/api) |
| Local credential location `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`, key names `cursorAuth/accessToken` etc. | confirmed-from-source (read directly on this machine) |
| Cursor Pro is now credit/usage-based billing (post-June-2025), not simple request counting | confirmed-from-source (current pricing docs) |
| Exact response JSON field names for `GetCurrentPeriodUsage` | inferred / low-confidence — needs live verification |

## 5. Sources

- [Tendo33/cursor-usage-tracker](https://github.com/Tendo33/cursor-usage-tracker)
- [Sammy970/cursor-usage-extension](https://github.com/Sammy970/cursor-usage-extension)
- [waitkafuka/cursor-api — Authentication (DeepWiki)](https://deepwiki.com/waitkafuka/cursor-api/1.2-authentication)
- [robinebers/openusage](https://github.com/robinebers/openusage)
- [Cursor APIs Overview — official docs](https://cursor.com/docs/api)
- [Cursor AI Code Tracking API — official docs](https://cursor.com/docs/account/teams/ai-code-tracking-api)
- [Cursor CLI Authentication — official docs](https://cursor.com/docs/cli/reference/authentication)
- [Peeking Under the Hood of Cursor's API Calls — Speedscale blog](https://speedscale.com/blog/peeking-under-the-hood-of-cursor/)
- [Cursor pricing explained 2026 — Vantage](https://www.vantage.sh/blog/cursor-pricing-explained)
- [Cursor pricing 2026 — eesel AI](https://www.eesel.ai/blog/cursor-pricing)
- Local machine inspection: `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` (this session, key names only, no values printed)
