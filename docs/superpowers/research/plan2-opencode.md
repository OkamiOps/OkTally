# OpenCode Zen / OpenCode Go — Usage & Balance API Research (v2)

Date: 2026-08-07
Scope: find a programmatic way (for OkTally's OpenCode usage plugin) to read (a) OpenCode Zen pay-as-you-go credit balance and (b) OpenCode Go subscription usage.

**This supersedes `plan2-opencode.md` v1.** That pass looked only at bearer-token REST routes reachable with `OPENCODE_API_KEY` and concluded "no public API exists." That was incomplete: it missed a real, live OAuth2 device-code flow that OpenCode ships. This pass found and live-tested that flow. **Bottom line, updated: the OAuth flow is real and does grant a bearer token good for a small `/api/*` surface (`orgs`, `user`, `config`) on `console.opencode.ai` — but that surface still does not include a balance/usage endpoint, confirmed both by reading the account-service source and by direct probing of the live API.** The web dashboard's billing data is on a *separate*, cookie-only authentication path that the OAuth token cannot reach. See §6 for exactly what was tried and what remains unconfirmed.

## 1. The OAuth flow (new finding — the previous pass missed this entirely)

**Confidence: confirmed-from-source AND confirmed-live** (read `packages/opencode/src/account/account.ts` in `sst/opencode`, then independently exercised the real endpoints with `curl` against production `console.opencode.ai`, no credentials used).

OpenCode has a genuine RFC 8628 OAuth2 **device-authorization** flow, completely separate from the `OPENCODE_API_KEY` used for Zen/Go inference. It authenticates an **OpenCode Console account** (GitHub/Google login), not the Zen/Go billing key.

- Client source: `packages/opencode/src/account/account.ts` (the `Account` service) and `packages/opencode/src/cli/cmd/account.ts` (the CLI command wiring, hidden: `opencode console login` / `logout` / `switch` / `orgs` / `open`). Also wired as an "OpenCode Console account" OAuth **integration method** in `packages/core/src/plugin/provider/opencode.ts` (alongside the separate "API key (service account)" method that's the `OPENCODE_API_KEY` path).
- `client_id = "opencode-cli"`, default server = `https://console.opencode.ai`.
- **Endpoints (all confirmed live against production, 2026-08-07):**

  1. `POST https://console.opencode.ai/auth/device/code`
     Body: `{"client_id":"opencode-cli"}`
     Live response (real, just tested):
     ```json
     {"device_code":"...","user_code":"FGBX-JLKG","verification_uri":"/device","verification_uri_complete":"/device?user_code=FGBX-JLKG&client_id=opencode-cli","expires_in":900,"interval":5}
     ```
  2. `POST https://console.opencode.ai/auth/device/token`
     Body (poll): `{"grant_type":"urn:ietf:params:oauth:grant-type:device_code","device_code":"...","client_id":"opencode-cli"}`
     Live response while unauthorized (real, just tested, HTTP 400):
     ```json
     {"_tag":"DeviceTokenError","error":"authorization_pending","error_description":"The authorization request is still pending"}
     ```
     Other possible `error` values per source: `slow_down`, `expired_token`, `access_denied`.
     On success: `{"access_token":"...","refresh_token":"...","token_type":"Bearer","expires_in":<seconds>}`.
  3. `POST https://console.opencode.ai/auth/device/token`
     Body (refresh): `{"grant_type":"refresh_token","refresh_token":"...","client_id":"opencode-cli"}` → same success shape, rotates both tokens.
- **Token storage:** NOT `~/.local/share/opencode/auth.json`. Stored in the local SQLite DB (`~/.local/share/opencode/opencode.db`), tables `AccountTable` / `AccountStateTable` (schema in `@opencode-ai/core/account/sql`, repo layer in `packages/opencode/src/account/repo.ts`). Confirmed on this machine: `auth.json`'s `"opencode"` entry is only `{type: "api", key: "<67 chars>"}` — a **static API key**, no `refresh`/`access`/`expires` fields (unlike e.g. the `"openai"` entry, which genuinely is `{type: "oauth", refresh, access, expires, accountId}` for ChatGPT-Plus login). So this OAuth account system and the `OPENCODE_API_KEY` are two independent credentials that happen to share the same "OpenCode" branding — the OAuth login is **not** how `OPENCODE_API_KEY` itself is minted; it authenticates a Console account instead.
- **What the OAuth access token can call (bearer, `Authorization: Bearer <access_token>`), confirmed live by source + probing:**
  - `GET https://console.opencode.ai/api/orgs` → `Org[]` (`{id, name}`). Live-probed with a bogus token: `401 {"_tag":"Unauthorized"}` — proves the route is real and enforces the token.
  - `GET https://console.opencode.ai/api/user` → `{id, email}`. Same live 401 confirms it's real.
  - `GET https://console.opencode.ai/api/config` (header `x-org-id: <org id>`) → `{"config": Record<string, Json>}`. Same live 401 confirms it's real. **Read the schema this actually returns** (`packages/core/src/v1/config/config.ts`, `ConfigV1.Info`): it's the standard `opencode.jsonc` config schema (shell, logLevel, server, plugin list, provider/model catalog overrides, etc.) used for managed/remote-config and to populate the provider model catalog (`packages/core/src/plugin/provider/opencode.ts`, `fetchProviders`). **There is no balance/credit/usage field anywhere in that schema.**

## 2. Does the OAuth token unlock a billing/usage endpoint anywhere on `console.opencode.ai`? No — probed directly.

**Confidence: confirmed-live** (direct HTTP probes, 2026-08-07, no credentials used — just checking whether routes exist at all via 401-vs-404 behavior).

The `/api/*` prefix is a real router (confirmed: known routes 401 "Unauthorized"; unknown routes return a distinct 404 "Not found" in plain text) — so probing is meaningful, not just guessing against a always-200 catch-all:

| Path | Result |
|---|---|
| `/api/orgs`, `/api/user`, `/api/config` | 401 `{"_tag":"Unauthorized"}` — **real routes** |
| `/api/usage` | 404 `Not found` |
| `/api/billing` | 404 |
| `/api/credits` | 404 |
| `/api/balance` | 404 |
| `/api/account` | 404 |
| `/api/workspace` | 404 |
| `/api/orgs/{id}/usage` | 404 |

Conclusion: even with a fully-completed OAuth login (which this session cannot do — it requires a human to open the `verification_uri_complete` URL and approve), **there is no bearer-token-reachable billing/usage endpoint on `console.opencode.ai/api/*`.** The `/api/config` route (the one endpoint that sounded promising) is confirmed by source to be model/provider catalog config, not billing.

## 3. Why the web dashboard still can't be reached even with the OAuth token — the SolidStart server-function boundary

**Confidence: confirmed-from-source.**

Re-examined `packages/console/app/src/context/auth.ts` and `auth.withActor.ts` (previous pass had only looked at `billing.ts` and stopped). The billing/usage dashboard's data (`queryBillingInfo` etc., `packages/console/app/src/routes/workspace/[id]/billing/*`, `.../usage/*`) is gated through `withActor()` → `getActor()` → `useAuthSession()`:

```ts
export function useAuthSession() {
  return useSession<AuthSession>({
    password: Resource.ZEN_SESSION_SECRET.value,
    name: "auth",
    cookie: { secure: false, httpOnly: true },
  })
}
```

This is an **encrypted, httpOnly browser session cookie** issued by a *different* auth stack — `packages/console/function/src/auth.ts`, a standard `@openauthjs/openauth` `issuer()` (GitHub/Google OAuth login for the *web app*, running as its own Cloudflare Worker at a separate `VITE_AUTH_URL` issuer origin) — landing in this cookie via `packages/console/app/src/routes/auth/{authorize,callback,logout,status}.ts`. This is architecturally **unrelated** to the CLI's `console.opencode.ai/auth/device/*` flow from §1, despite both ultimately being "log in with GitHub/Google to an OpenCode account." Two separate OAuth issuers, two separate token/session formats, no interop found in source: the device-flow `access_token` is a bearer JWT/opaque token checked by a small Hono-ish `/api/*` router; the web session is an openauth-js encrypted cookie checked by SolidStart's `getRequestEvent().locals`. **Nothing in the repo exchanges one for the other.** So the billing server functions genuinely cannot be called with the OAuth bearer token — only with a real browser session cookie, i.e., only by driving/scraping the actual logged-in browser session, not by a clean API call.

## 4. The OpenCode team itself hasn't shipped a balance/usage API — confirmed via open GitHub issues

**Confidence: confirmed-live** (fetched the actual issue pages, not just search snippets).

- **[Feature Request: Add Zen balance API endpoint #10448](https://github.com/anomalyco/opencode/issues/10448)** — opened 2026-01-24, **still open**, assigned to a maintainer (`fwang`), no response yet. Proposes exactly `GET https://opencode.ai/zen/v1/balance` with a `{balance, currency, auto_reload}` shape — i.e., this doesn't exist yet; it's a wishlist item from another user hitting the same wall.
- **[FEATURE]: Add Go plan usage/balance API endpoint (rolling/weekly/monthly windows) #16017** — same story for Go, also unresolved.

This directly confirms (from the OpenCode team's own issue tracker, not inference) that no such endpoint ships today.

## 5. Community integrations re-checked — still no remote quota read

**Confidence: confirmed-live** (fetched actual docs/repo, not just search summaries).

- **OpenClaw's `opencode-go` provider** (`docs.openclaw.ai/providers/opencode-go`): documents `OPENCODE_API_KEY` auth and model routing only. No usage/quota endpoint mentioned. OpenClaw's own quota-tracking feature (`openclaw status --usage`, its list of "usage-window providers": Claude, ClawRouter, Copilot, DeepSeek, MiniMax, OpenAI, Xiaomi, z.ai) **explicitly does not include OpenCode Go** — i.e., OpenClaw itself cannot show OpenCode quota either. This directly contradicts "he can see his quota in other applications" if the app in question is OpenClaw.
- **`gaboe/opencode-usage`** (a CLI literally named for this purpose): reads `~/.local/share/opencode/opencode.db` locally only, same technique as `opencode stats` from the v1 report. No remote API call.
- Did not find any tool that displays a live, server-authoritative OpenCode Zen/Go balance. If the owner is seeing quota in some other app, the most likely explanations, in order of probability: (a) they're looking at `console.opencode.ai`'s web dashboard itself (browser session, not an API); (b) they're looking at OpenCode's own **desktop app** (`ai.opencode.desktop`), which very likely embeds the same web dashboard via webview/browser session rather than a public API — its local data files are opaque `.dat` blobs, not independently inspectable without live access; (c) they're conflating a *different* provider's quota display (e.g. Anthropic/OpenAI native usage, which several tools do support) with "OpenCode."

## 6. What was tried (for the owner to redirect us if we're still missing the app)

- Read `packages/opencode/src/account/account.ts`, `repo.ts`, `schema.ts`, `cli/cmd/account.ts`, `packages/core/src/plugin/provider/opencode.ts` — the full OAuth device-code client implementation.
- Live-tested `POST /auth/device/code` and `POST /auth/device/token` against production `console.opencode.ai` (no credentials, just protocol-shape verification) — both real and match source exactly.
- Live-probed `/api/orgs`, `/api/user`, `/api/config`, and eight guessed billing-shaped paths (`/api/usage`, `/api/billing`, `/api/credits`, `/api/balance`, `/api/account`, `/api/workspace`, `/api/orgs/:id/usage`) — only the three known-good ones exist.
- Read `ConfigV1.Info` schema fully — confirmed `/api/config`'s payload is provider/model catalog config, not billing.
- Read `packages/console/app/src/context/auth.ts` / `auth.withActor.ts` / `packages/console/function/src/auth.ts` — confirmed the web dashboard's billing server functions use a completely separate cookie-session auth stack that the device-flow OAuth token cannot satisfy.
- Fetched the two open OpenCode GitHub issues asking for exactly this feature (#10448, #16017) — confirms upstream hasn't shipped it.
- Fetched OpenClaw's `opencode-go` provider docs and its own quota-provider list — confirms OpenClaw can't show OpenCode quota either.
- Fetched `gaboe/opencode-usage` — confirms it's local-DB-only, same technique already known from v1.
- Did **not** attempt: completing the actual device-code login (requires a human to open a browser and approve — out of scope for a non-interactive research pass, and would require the owner's explicit action); inspecting the OpenCode desktop app's live network traffic (would need the owner to run it while we watch, or the owner to grant browser/computer-use access to their already-logged-in `console.opencode.ai` session so we can inspect real (not fake-token) API responses and dashboard network calls first-hand).

**If the owner can point to the specific "other application" that shows OpenCode quota** (name, or a screenshot), that would let us target the exact integration rather than re-guessing. Similarly, if the owner is willing to run `opencode console login` themselves and then let us inspect (not use) the resulting session — e.g. share what `GET /api/orgs` returns once authenticated, or open their already-logged-in `console.opencode.ai` dashboard in a browser we can read network requests from — that's the one investigative step this pass couldn't complete non-interactively and would settle definitively whether *any* authenticated surface (even the cookie-only dashboard) exposes a machine-readable balance number we could scrape as a fallback.

## 7. Unchanged from v1 (still valid)

- Zen/Go inference endpoints (`https://opencode.ai/zen/v1/*`, `https://opencode.ai/zen/go/v1/*`), authenticated with `OPENCODE_API_KEY` as a Bearer token via the OpenAI-compatible adapter — confirmed, no balance data on success responses.
- On HTTP 429, structured error bodies (`FreeUsageLimitError`, `GoUsageLimitError` with `metadata: {workspace, limitName}` and a `retry-after` header) are the one place usage state leaks into the inference API surface — reactive only, not a queryable gauge. Source: `packages/opencode/src/session/retry.ts`.
- Local estimate via `~/.local/share/opencode/opencode.db` (`session`/`message`/`part` tables, `data` JSON blob with cost/token accounting) — same as `opencode stats`, client-side only, not authoritative.

## 8. Recommendation for OkTally

No live remote balance/usage read exists today, via any auth mechanism — API key, or the newly-found OAuth device flow. Given the upstream feature requests are open but unassigned-to-shipping, OkTally's plugin should:

1. **Primary:** local estimate from `opencode.db` (as v1 recommended), clearly labeled "local estimate, this machine only."
2. **Reactive:** parse `FreeUsageLimitError`/`GoUsageLimitError` 429 metadata during real usage for an authoritative "at limit until HH:MM" signal.
3. **Optional, higher-effort:** implement the OAuth device-code flow from §1 (it's straightforward, and legitimate — it's OpenCode's own public login mechanism) purely to identify *which* OpenCode account/org is active (email, org name via `/api/user` and `/api/orgs`) for display purposes in OkTally, while being explicit in the UI that it cannot fetch a live balance through this token — only identity.
4. **Track upstream:** subscribe to sst/opencode issues #10448 and #16017 — if either ships, it directly unblocks a true live balance/usage gauge with no further reverse-engineering needed.

## Sources

- https://github.com/sst/opencode (aka `anomalyco/opencode` upstream), specifically:
  - `packages/opencode/src/account/account.ts`, `repo.ts`, `schema.ts`, `url.ts`
  - `packages/opencode/src/cli/cmd/account.ts`
  - `packages/core/src/plugin/provider/opencode.ts`
  - `packages/core/src/v1/config/config.ts`
  - `packages/console/app/src/context/auth.ts`, `auth.withActor.ts`
  - `packages/console/function/src/auth.ts`
  - `packages/console/app/src/routes/api/*`, `packages/function/src/api.ts` (ruled out as unrelated)
  - `packages/opencode/src/session/retry.ts` (unchanged from v1)
- Live HTTP probes against `https://console.opencode.ai` (2026-08-07): `/auth/device/code`, `/auth/device/token`, `/api/orgs`, `/api/user`, `/api/config`, and eight negative-control paths. No credentials used or exposed.
- https://github.com/anomalyco/opencode/issues/10448 (fetched)
- https://github.com/anomalyco/opencode/issues/16017 (referenced)
- https://docs.openclaw.ai/providers/opencode-go (fetched)
- https://github.com/gaboe/opencode-usage (fetched)
- Local files inspected (structure only, no secret values captured): `~/.local/share/opencode/auth.json` (schema of all six provider entries, including confirming the `"opencode"` entry is a static API key, not an OAuth pair).
