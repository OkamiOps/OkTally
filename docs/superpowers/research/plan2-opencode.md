# OpenCode Zen / OpenCode Go — Usage & Balance API Research

Date: 2026-08-07
Scope: find a programmatic way (for OkTally's OpenCode usage plugin) to read (a) OpenCode Zen pay-as-you-go credit balance and (b) OpenCode Go subscription usage, using the user's `OPENCODE_API_KEY`.

## TL;DR

**There is no documented or discoverable public REST endpoint that returns Zen credit balance or Go subscription usage, authenticated with just `OPENCODE_API_KEY`.** The dashboard that shows this data (`console.opencode.ai` / `opencode.ai/workspace/:id/billing` and `.../usage`) is a SolidStart web app whose data comes from server-side functions gated by a browser session (cookie), not from a callable JSON API. The only two realistic options for OkTally are:

1. **Local estimation** — read OpenCode's local SQLite DB (`~/.local/share/opencode/opencode.db`) and sum the cost/token fields embedded in message JSON, the same way `opencode stats` does. This gives a **client-side-only, non-authoritative** running total (misses usage from other machines/the desktop app pointed at a different DB, and misses the server's canonical balance/limit state).
2. **Reactive detection via 429 error bodies** — when a request to the Zen/Go endpoint is rate-limited, the JSON error body and `retry-after` header carry structured metadata (workspace id, limit name, reset time) that can be parsed to infer "how close to the limit" reactively, but only after a limit is actually hit.

There is no confirmed way to proactively query "remaining Zen credits" or "Go plan usage-to-date" as a number, short of scraping the authenticated web dashboard (out of scope / fragile / against the spirit of a public API).

## 1. Official docs (opencode.ai/docs/zen, /docs/go)

**Confidence: confirmed-from-source (fetched docs pages directly, 2026-08-07)**

- `opencode.ai/docs/zen`:
  - Endpoints, by model family (all under `https://opencode.ai/zen/v1`):
    - OpenAI-compatible: `POST https://opencode.ai/zen/v1/responses` and `POST https://opencode.ai/zen/v1/chat/completions`
    - Anthropic-compatible: `POST https://opencode.ai/zen/v1/messages`
    - Google: `https://opencode.ai/zen/v1/models/[model-id]`
    - Models metadata: `GET https://opencode.ai/zen/v1/models`
  - Auth: "sign in to OpenCode Zen, add your billing details, and copy your API key" — this is the same key stored as `OPENCODE_API_KEY`. Exact header name is not documented on the page (see §2 below — it's Bearer-style, handled by the OpenAI-compatible SDK adapter).
  - No documented endpoint for checking remaining credit balance. The page only mentions "you are charged per request" and an "auto-reload" feature (top up balance when it drops below a threshold).

- `opencode.ai/docs/go`:
  - "Track your current usage in the **console**" (`https://opencode.ai/auth` → web dashboard). This is explicitly the documented way to check usage — a **web UI**, not an API.
  - Auth flow: sign in to OpenCode Zen → subscribe to Go → copy API key → `/connect` in the TUI. Same `OPENCODE_API_KEY` covers both catalogs, confirming the user's premise.
  - Endpoints (same shape as Zen, different base path): `https://opencode.ai/zen/go/v1/chat/completions`, `.../responses`, `.../messages`, `.../models`.
  - **Usage limits are tiered, dollar-denominated, rolling windows**: "5 hour limit — $12 of usage", "Weekly limit — $30 of usage", "Monthly limit — $60 of usage" (exact figures may change with plan tier; these were what the docs showed at fetch time).
  - Overflow: if the user has a Zen balance and enables **"Use balance"** in the console, Go automatically falls back to spending Zen credits once a Go tier limit is hit.
  - No documented API for reading current usage-vs-limit programmatically.

## 2. Open-source repo (github.com/sst/opencode)

**Confidence: confirmed-from-source** (shallow-cloned `sst/opencode` at `/private/tmp/.../scratchpad/opencode-src` and read the actual TypeScript source, plus `strings`-dumped the locally installed compiled CLI binary at `~/.nvm/.../opencode-darwin-arm64/bin/opencode`, v1.17.15).

### 2.1 Provider wiring (confirms the shared-key premise)

Found directly in the compiled CLI's embedded provider registry:

```
{ env: ["OPENCODE_API_KEY"], npm: "@ai-sdk/openai-compatible",
  api: "https://opencode.ai/zen/v1", name: "OpenCode Zen", doc: "https://opencode.ai/docs/zen" }

{ env: ["OPENCODE_API_KEY"], npm: "@ai-sdk/openai-compatible",
  api: "https://opencode.ai/zen/go/v1", name: "OpenCode Go", doc: "https://opencode.ai/docs/zen" }
```

Both are plain OpenAI-compatible chat/completions providers, both read `OPENCODE_API_KEY` from `~/.local/share/opencode/auth.json` (confirmed locally — see §4), keyed as `"opencode": { "type": "api", "key": "<redacted>" }` — a single credential entry covers both Zen and Go, matching the user's statement.

### 2.2 Server source — the actual backend implementation lives in `packages/console/`

This is the real find: the repo contains the **server-side implementation** of the Zen/Go gateway and the billing dashboard (it's a monorepo — `sst/opencode` hosts both the CLI/TUI and the `opencode.ai` console web app + API).

- Route handlers for the model-proxying API: `packages/console/app/src/routes/zen/v1/{chat/completions,messages,models,responses}.ts` and the mirrored `zen/go/v1/...` — these are the inference endpoints only (no usage/balance route exists among them; I listed every file under `packages/console/app/src/routes/` and there is no `zen/v1/usage`, `zen/v1/credits`, or `zen/v1/balance`).
- Billing data model: `packages/console/core/src/schema/billing.sql.ts` — `BillingTable` has columns `balance` (bigint, stored in **micro-cents**; e.g. `packages/console/core/script/lookup-user.ts` formats it as `` `$${(row.balance / 100000000).toFixed(2)}` ``), `monthlyLimit`, `monthlyUsage`, `reload`/`reloadTrigger`/`reloadAmount` (auto-reload config), and a `subscription` JSON blob with `{status, seats, plan, useBalance}` for Go/Black plans.
- Billing business logic: `packages/console/core/src/billing.ts` (`Billing` namespace) — `Billing.get()`, `Billing.usages()`, `Billing.reload()`, `Billing.generateCheckoutUrl()`, `Billing.generateSessionUrl()` (Stripe billing portal), etc.
- **How the web dashboard actually fetches this data**: `packages/console/app/src/routes/workspace/[id]/billing/billing-section.tsx` calls `queryBillingInfo(params.id)`, a SolidStart `query()` — a **server function** (`"use server"`) wrapped in `withActor(...)`, i.e. it requires an authenticated **browser session** (cookie-based actor context), not a bearer-token/API-key REST call. There is no equivalent route under `packages/console/app/src/routes/api/` that exposes billing/usage — the only files under `routes/api/` are `enterprise.ts` and two support actions (`delete-account.ts`, `create-referral.ts`), unrelated to usage/credits.
- Usage page (`packages/console/app/src/routes/workspace/[id]/usage/usage-section.tsx`, `graph-section.tsx`) — same pattern, session-authenticated server queries, no public API.

**Conclusion: the balance/usage data has no bearer-token-accessible REST API in the open-source repo.** It is intentionally dashboard-only (session auth), consistent with the docs only pointing to "the console."

### 2.3 Rate-limit / usage-exceeded signal (the one place usage data leaks into the API surface)

`packages/opencode/src/session/retry.ts` (client-side error handling in the CLI/TUI) parses two structured error types that the Zen/Go proxy returns on **429 responses**:

- `FreeUsageLimitError` — free tier exhausted. Message: `"Free usage exceeded, subscribe to Go"`, links to `https://opencode.ai/go`.
- `GoUsageLimitError` — a Go plan tier limit was hit. The error body is JSON with `metadata: { workspace, limitName }` (e.g. `limitName` = "5 hour" / "Weekly" / "Monthly"), and the HTTP `retry-after` header gives seconds until reset. The client formats a message like: `"5 hour usage limit reached. It will reset in 5 hours 23 minutes. To continue using this model now, enable usage from your available balance — https://opencode.ai/workspace/{workspaceID}/go"`.

This confirms the **mechanism** linking Go and Zen (Go tiers are rolling windows; on exhaustion, spend can fall back to Zen's balance if "Use balance" is enabled) — but it's only observable reactively, after a 429, not as a queryable "current usage" number. No `x-ratelimit-remaining`-style header was found on successful (2xx) responses in `packages/console/app/src/routes/zen/util/handler.ts` (I grepped every header-setting call in that file and its siblings — only `retry-after` is set, and only on the error path).

### 2.4 opencode-sdk / other packages

The monorepo's `packages/sdks/` directory (TypeScript/other language SDKs, if present) mirrors the CLI's local HTTP server API (session/message CRUD for the TUI/IDE integrations) — it does not add any Zen/Go billing surface beyond what's above. Did not find a separate `sst/opencode-sdk` repo; the SDK lives inside the monorepo.

## 3. Community integrations

**Confidence: inferred / not found** — I did not find any community tool (OpenClaw's `opencode-go` provider docs, "Hermes Agent" guides, etc.) that fetches Zen/Go balance or usage programmatically. Every third-party integration found treats OpenCode Zen/Go purely as an **inference provider** (base URL + API key, OpenAI-compatible), the same shape documented in §1/§2.1 — none of them surface a usage/balance API because none exists. Treat this as a negative result, not an exhaustive survey.

## 4. Local machine (installed OpenCode CLI + config)

**Confidence: confirmed-from-source** (inspected directly on this machine; no secret values were printed — see redaction method below).

- Binary: `opencode` v1.17.15, installed via npm/nvm at `~/.nvm/versions/node/v24.17.0/bin/opencode` (a compiled Bun executable under `.../lib/node_modules/opencode-ai/node_modules/opencode-darwin-arm64/bin/opencode`).
- Config dir: `~/.config/opencode/` — `opencode.jsonc` (user's provider/model config, no secrets), `package.json`.
- Data dir: `~/.local/share/opencode/`:
  - `auth.json` (mode `600`, i.e. already permission-restricted) — a flat JSON object keyed by provider id. Structure (values redacted by type/length only, never printed):
    ```json
    {
      "opencode": { "type": "<string>", "key": "<string>" },
      "openai":   { "type": "<string>", "refresh": "<string>", "access": "<string>", "expires": "<int>", "accountId": "<string>" },
      "...other providers...": { }
    }
    ```
    The `"opencode"` entry (`type` = 3-char string, almost certainly `"api"`; `key` = 67-char string) is the single `OPENCODE_API_KEY`-equivalent credential shared by both Zen and Go, confirming the user's premise. **This is the credential OkTally would read to authenticate outbound calls**, but per §2.2 there's no balance/usage endpoint to call it against.
  - `opencode.db` (SQLite, ~80MB on this machine) — local session/message history. Relevant tables: `session`, `message` (columns: `id`, `session_id`, `time_created`, `time_updated`, `data` — `data` is a JSON blob per message containing token/cost accounting), `part` (same shape, message parts). This is exactly what the bundled `opencode stats` CLI command reads (verified: `opencode stats --days 1` prints a "COST & TOKENS" table with Total Cost, Input/Output/Cache Read/Cache Write token counts, sourced from this DB). **This is the one locally-available, non-network way to approximate usage** — but it is a client-side ledger of what this machine sent, not the server's authoritative balance or Go-tier usage-to-date, and it won't reflect usage from OpenCode's desktop app if it writes to a different DB, or from any other device using the same API key.
  - `opencode.db-wal` / `-shm` — SQLite WAL files, no independent info.
  - `repos/`, `storage/` — unrelated local caches.
- Desktop app (`ai.opencode.desktop`, found at `~/Library/Application Support/ai.opencode.desktop/`) — present but its data files are opaque binary blobs (`.dat`); not inspected further (out of scope, and likely just mirrors the same web dashboard via an embedded webview).
- CLI surface relevant to usage: `opencode stats` (local DB only, per above), `opencode providers`/`opencode auth list` (lists configured providers/credentials, not balance), `opencode db` (raw SQL access to the local DB — could be scripted by OkTally instead of reimplementing the stats parsing, e.g. `opencode db "select ..." --format json`).

## 5. Endpoint summary table

| Purpose | URL | Method | Auth | Status |
|---|---|---|---|---|
| Zen chat completions | `https://opencode.ai/zen/v1/chat/completions` (+ `/responses`, `/messages`) | POST | `OPENCODE_API_KEY` (Bearer, OpenAI-compatible adapter) | confirmed-from-source |
| Zen model list | `https://opencode.ai/zen/v1/models` | GET | `OPENCODE_API_KEY` | confirmed-from-source |
| Go chat completions | `https://opencode.ai/zen/go/v1/chat/completions` (+ `/responses`, `/messages`) | POST | `OPENCODE_API_KEY` | confirmed-from-source |
| Go model list | `https://opencode.ai/zen/go/v1/models` | GET | `OPENCODE_API_KEY` | confirmed-from-source |
| Zen balance / Go usage | *(none found)* — dashboard only, session-cookie auth, at `https://opencode.ai/workspace/{id}/billing` and `.../usage` | — | browser session, not API key | confirmed-absent (no route in `packages/console/app/src/routes/`) |
| Rate-limit signal | Any of the above, on HTTP 429 | — | — | error body `{error:{type: "FreeUsageLimitError"|"GoUsageLimitError", metadata:{workspace, limitName}}}`, header `retry-after` (seconds) | confirmed-from-source |

## 6. Mapping to OkTally `QuotaShape`

Given there is no authoritative remote read, OkTally's options per catalog:

- **Zen (pay-as-you-go credits)** → conceptually a `creditBalance` shape (a dollar balance that decrements per request, with auto-reload). **But it cannot be populated from a live API call** — there's no `GET .../credits` endpoint. Two fallbacks:
  - Best-effort: derive a **local, running total spent** from `opencode.db` (sum `data.cost` across `message` rows in the relevant time range) and present it as "$X spent" rather than "$Y remaining" — since OkTally can't know the account's actual top-up balance without dashboard access. This is inherently an estimate, not a balance.
  - Reactive: surface a warning/blocked state only once a `FreeUsageLimitError`/insufficient-balance 429 is observed from a real request.

- **Go ($10/mo subscription, tiered rolling limits)** → conceptually fits `rollingWindow`/`periodicCounter` (three concurrent windows: 5h/$12, weekly/$30, monthly/$60 — see caveat in §1 that exact numbers may vary by plan). **Also cannot be populated proactively** — no usage-to-date endpoint. Fallbacks:
  - Local estimate from `opencode.db`, filtered to Go-catalog model IDs/requests, bucketed into the three rolling windows client-side — same estimate caveat as above (only reflects usage made through this local install).
  - Reactive: parse `GoUsageLimitError` 429s to know *which* window (`limitName`) was hit and *when it resets* (`retry-after`), which is real, confirmed, structured data — useful for an "at limit until HH:MM" indicator, just not a live gauge.

**Bottom line for the plugin design**: OkTally cannot implement a true "remaining credits" or "usage-to-date" gauge against OpenCode's servers today with only `OPENCODE_API_KEY` — there is no such API. The practical plugin should (a) read `~/.local/share/opencode/opencode.db` for a local spend/token estimate (via `opencode db "<query>" --format json` or direct SQLite read), clearly labeled as a local estimate, and (b) listen for/parse 429 error metadata during real usage to surface authoritative "limit hit, resets at X" state for Go. Anything closer to a true live balance would require either scraping the authenticated console (fragile, likely against ToS) or OpenCode shipping a new public API (worth flagging upstream as a feature request — `packages/console/app/src/routes/api/` is exactly where such a route would go, based on repo conventions).

## Sources

- https://opencode.ai/docs/zen (fetched 2026-08-07)
- https://opencode.ai/docs/go (fetched 2026-08-07)
- https://github.com/sst/opencode (shallow clone, HEAD as of 2026-08-07), specifically:
  - `packages/console/app/src/routes/zen/**`
  - `packages/console/app/src/routes/workspace/[id]/billing/**`, `.../usage/**`
  - `packages/console/core/src/billing.ts`, `packages/console/core/src/schema/billing.sql.ts`
  - `packages/opencode/src/session/retry.ts`, `packages/opencode/test/session/retry.test.ts`
  - `packages/ui/src/i18n/en.ts` (dialog copy confirming Go tiers / balance fallback)
- Locally installed `opencode` CLI v1.17.15 (`~/.nvm/versions/node/v24.17.0/bin/opencode`), provider registry strings extracted via `strings` on the compiled binary.
- Local files inspected (structure only, no secret values captured): `~/.config/opencode/opencode.jsonc`, `~/.local/share/opencode/auth.json`, `~/.local/share/opencode/opencode.db` schema, `opencode stats` command output.
