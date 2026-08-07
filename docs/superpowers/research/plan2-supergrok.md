# SuperGrok usage tracking — research notes

Goal: figure out how OkTally (macOS menu bar app) can read a SuperGrok subscription's usage/quota
programmatically, given the user authenticates via OAuth (browser/device-code against
`accounts.x.ai` / `auth.x.ai`), not an `XAI_API_KEY`.

Confidence labels used below:
- **confirmed-from-source** — verified directly (local machine inspection, or primary-source docs I fetched)
- **documented-by-community** — stated in a community tool's README/source/issue that I read, but not independently verified against a live request
- **inferred** — reasoned from adjacent facts, not directly observed

## 0. Local machine finding (do this first — it changes the plan)

**confirmed-from-source.** This Mac already has an official **xAI "Grok" CLI** installed and authenticated:
`/Users/marcos/.grok/` (binaries under `bin/grok-0.2.11x`, plus `~/.local/bin/grok`).

Inspecting `~/.grok/auth.json` (keys/types only, per the security rule — no values were read or printed):

```
https://auth.x.ai::<uuid>:            (dict, top-level key is literally the issuer URL + a UUID)
  key: str
  auth_mode: str
  create_time: str
  user_id: str
  email: str
  first_name: str
  profile_image_asset_id: str
  principal_type: str
  principal_id: str
  team_id: str
  coding_data_retention_opt_out: bool
  refresh_token: str
  expires_at: str
  oidc_issuer: str
  oidc_client_id: str
```

This **independently confirms**, straight from a real local credential file on this machine, several claims the community sources below make: the OAuth issuer is `auth.x.ai`, tokens are OIDC-flavored (`oidc_issuer`, `oidc_client_id` fields), a `refresh_token` + `expires_at` pair drives silent renewal, and there's a `coding_data_retention_opt_out` flag (matches community tools' `/xai-privacy` "coding-data-retention" toggle, §1). `~/.grok/config.toml` also confirms this is a full agentic coding CLI (marketplace, skills, sessions, `[models] default`), i.e. it's a Grok-branded coding agent, not just a chat client — this is almost certainly the "Grok Build" / `grok-cli` product referenced throughout the OmniRoute issues in §2.

No quota/usage data was found cached locally (no `billing.json`/`usage.json`-style file) — usage has to come from a live network call, not a local cache.

**Practical implication for OkTally**: `~/.grok/auth.json` is a real, already-present, already-authenticated credential source on macOS. A SuperGrok plugin could piggyback on this file if it exists (read `refresh_token` at that JSON path, never persist the raw token elsewhere), falling back to OkTally doing its own OAuth login when it's absent.

## 1. OAuth flow

### 1.1 Community implementations found

- **`stnly/pi-grok`** (github.com/stnly/pi-grok) — xAI OAuth provider for the "pi" coding agent. — documented-by-community
- **`BlockedPath/pi-xai-oauth`** (github.com/BlockedPath/pi-xai-oauth) — a more detailed, dedicated OAuth-provider package for the same ecosystem. — documented-by-community
- **NousResearch `hermes-agent`** xAI Grok OAuth guide (hermes-agent.nousresearch.com/docs/guides/xai-grok-oauth). — documented-by-community
- Several forks/variants exist (`luxus/pi-xai`, `kenryu42/pi-grok-cli`, `ai-ecoverse/pi-grok`) — not individually inspected, treated as re-implementations of the same flow.

### 1.2 Endpoints / flow

- **Auth/issuer host**: `https://accounts.x.ai` (hermes-agent docs) and `https://auth.x.ai` (device-code requests per hermes-agent; also **confirmed-from-source** as the literal key prefix in this machine's `~/.grok/auth.json`, §0). These both appear to be xAI's OAuth surface — docs are inconsistent about which is used for which sub-step (authorize page vs. device-code/token issuer), and none of the sources I could reach disclosed the exact `/authorize`, `/oauth/token`, or `/oauth/device/code` paths. — documented-by-community for the flow shape; confirmed-from-source only for the `auth.x.ai` issuer string itself.
- **Flow type**: xAI supports **both**:
  - **Device-code flow** (default in `pi-grok`, and what `hermes-agent` uses): request a device code, user opens a verification URL, enters/approves a code, tool polls until approved. Device-code responses carry an `expires_in` ("typically tens of minutes" per hermes-agent docs). — documented-by-community
  - **Authorization-code + PKCE flow** (browser-callback flow, `PI_XAI_LOGIN_METHOD=callback` in pi-grok, loopback listener on port 56121; `pi-xai-oauth` describes this as "PKCE S256, state validation, loopback callback listener"). — documented-by-community
  - For a macOS menu-bar app, PKCE + a local loopback redirect (like the callback flow above) is the more natural fit than device-code, since OkTally can pop a browser and catch the redirect itself.
- **Client ID**: no source disclosed the literal client_id value. `pi-grok` exposes it as overridable via `PI_XAI_OAUTH_CLIENT_ID` with an undisclosed built-in default; `~/.grok/auth.json` confirms a field `oidc_client_id` exists but its value was not read (security rule). **OkTally will need to either register its own OAuth client with xAI, or reverse-engineer/reuse the CLI's client_id via traffic inspection** — this is a real open item, not resolved by this research. — inferred / open question.
- **Scopes**: `pi-grok` documents `openid profile email offline_access grok-cli:access api:access conversations:read conversations:write`. `pi-xai-oauth` separately describes an "eight-scope Grok client grant including `conversations:read` and `conversations:write`" without enumerating all eight. These are roughly consistent (7–8 scopes, OIDC + conversation history + CLI/API access). — documented-by-community, not independently verified.

### 1.3 Local token storage used by community tools

| Tool | Path | Notes |
|---|---|---|
| Official xAI Grok CLI | `~/.grok/auth.json` | **confirmed-from-source** on this machine (§0). `pi-xai-oauth` explicitly documents auto-detecting and reusing this same file. |
| NousResearch hermes-agent | `~/.hermes/auth.json` | documented-by-community (hermes-agent docs) |
| pi (BlockedPath/pi-xai-oauth) | managed by "Pi's credential store", exact path not disclosed | documented-by-community |

Refresh token lifetime: an OmniRoute bug report (issue #7610, `diegosouzapw/OmniRoute`) states the official CLI's refresh tokens in `~/.grok/auth.json` have "a ~7-day expiry window" and must be rotated before then or the user is forced to re-authenticate. — documented-by-community.

### 1.4 Refresh mechanism

All sources agree on the same pattern: access token is refreshed proactively (hermes-agent: "in the background" before use; pi-grok: "5 minutes before they expire"; pi-xai-oauth: "stored and rotated automatically before expiry"), plus reactively on HTTP 401 (hermes-agent: refresh-on-401, with `invalid_grant` triggering a re-auth prompt and dead tokens getting locally quarantined to avoid repeated failed calls). — documented-by-community, consistent across three independent projects.

## 2. Usage/quota endpoint findings

This is the least certain part of the research — no source gave a fully confirmed, literal request/response pair I could verify. But there is a consistent, cross-corroborated shape across three independent sources:

### 2.1 `POST https://grok.com/grok_api_v2.GrokBuildBilling/GetGrokCreditsConfig`
- Source: `diegosouzapw/OmniRoute` issue #6844 ("Grok Build (grok-cli) quota tracking"). — documented-by-community
- Described as a **gRPC-web** endpoint (package name `grok_api_v2`, service `GrokBuildBilling`), not a plain REST JSON endpoint — consistent with grok.com's backend being a Connect/gRPC-Web service (same pattern Cursor uses, see `plan2-cursor.md` in this same directory).
- Response fields described: `credit_usage_percent` (current pool consumption, as a percentage — proto3 omits the field entirely at 0%, so "absent" must be treated as 0, not "unknown"), plus a reset timestamp for the current billing period.
- Requires the same bearer JWT used for chat, i.e. no separate credential — reuse the OAuth access token.

### 2.2 ACP JSON-RPC `x.ai/billing` method
- Same issue (#6844) describes this as a "future-proofing" secondary source: a JSON-RPC 2.0 method (`x.ai/billing`, method name must be sent with a literal `/`, not escaped) over the Grok CLI's agent-stdio protocol (`grok agent stdio`), not over HTTP.
- Documented fields: `billingCycle.billingPeriodEnd` (reset time), `monthlyLimit.val` / `usage.totalUsed.val` (to compute a percentage), `on_demand_enabled` / `onDemandCap`.
- At the time of that report this method returned `-32601 Method not found` against Grok CLI ~0.1.210, i.e. **not reliably available yet**. — documented-by-community, explicitly flagged as unreliable by its own source.
- Not directly usable by a macOS menu-bar app anyway (it's a stdio protocol to a spawned CLI process, not an HTTP API) unless OkTally is willing to shell out to the user's local `grok` binary.

### 2.3 Unofficial REST-ish endpoints (`pi-xai-oauth`)
- `GET https://cli-chat-proxy.grok.com/v1/user` — account/retention state (also referenced by `pi-grok`'s `/xai-status`).
- `GET https://cli-chat-proxy.grok.com/v1/billing?format=credits` — described in both `pi-grok` and `pi-xai-oauth` docs as returning "subscription credit snapshots" / "usage percentage, reset times, prepaid balance, bounded history." `pi-xai-oauth`'s own docs hedge this as "unofficial" and describe defensive parsing ("validated fields only," "bounded-JSON walker," size-bounded response handling) — implying the response shape is not stable/documented and these tools guard against it changing under them.
- This looks like the most directly usable candidate for OkTally (plain HTTPS GET, bearer auth, JSON) if it proves accessible — but **no source showed me a literal captured JSON response**, only field-name summaries from tool authors. Treat as documented-by-community, low-to-medium confidence on exact field names.

### 2.4 What this means for OkTally
There is **no officially documented xAI "usage/limits" API** analogous to Anthropic's Claude usage endpoint. Everything above is reverse-engineered by community tool authors from either the grok.com web app's own network calls (gRPC-web, §2.1) or the official Grok CLI's proxy (§2.3), and multiple issue threads (OmniRoute #6844, #7610) explicitly complain that **no community tool has this working reliably yet** — #7610 states Grok Build in OmniRoute currently has "No Quota Tracking... unlike Claude Code and Codex providers." That is itself a useful data point: as of this research, this is an open/unsolved problem even in more mature multi-provider proxy projects, not just something OkTally hasn't found yet.

**Recommended fallback if no usage endpoint proves reliable**: fall back to parsing `429`/rate-limit response headers or error bodies from ordinary chat requests (the pattern several sources allude to but don't confirm field names for), or surface "usage unknown, subscription active" rather than a numeric bar — same defensive posture recommended for Cursor in `plan2-cursor.md`.

## 3. Quota structure — SuperGrok vs SuperGrok Heavy

Two different quota systems are described, for two different products, and they should not be conflated:

1. **Consumer grok.com/app chat quota** (what a typical SuperGrok subscriber experiences in the chat UI): third-party blog summaries (jingrey.com, not xAI-authored — **documented-by-community, lower confidence, may be outdated**) describe **fixed daily counters per feature**, resetting at midnight UTC, separate pools per feature:
   - SuperGrok ($30/mo, per that source): ~1,000 messages/day, 50 images/day, 10 video clips/day, 100 DeepSearch queries/day, 120 voice minutes/day, 256K context.
   - SuperGrok Heavy ($100/mo): ~5,000 messages/day, 200 images/day, 50 video clips/day, 500 DeepSearch queries/day, 480 voice minutes/day, 512K context.
   - No intra-day rolling window (e.g. no 2-hour bucket) per this source — a single daily reset per feature category.
2. **Grok Build / grok-cli (coding agent) quota**: per OmniRoute issue #6844, xAI has moved this product to a **shared weekly usage pool measured as a percentage**, replacing what used to be static per-day request/token counts (OmniRoute's own old static model was "864 requests / 18M tokens per day" before this shift broke it). This is period-based (has a `billingPeriodEnd`/reset timestamp) but percentage-of-pool, not a simple counter.

**inferred**: these are likely two distinct backend quota systems (consumer chat app vs. the coding-agent product), and OkTally should decide which one it's tracking. Given the task framing ("SuperGrok subscription... uses it via OAuth... browser/device-code"), and that the OAuth flows researched here are specifically the coding-agent/CLI-style flows (pi-grok, hermes-agent, official `grok` CLI), **the OAuth path researched in §1 is most directly wired to the Grok Build/coding-agent quota (§2, weekly percentage pool)**, not the consumer chat daily-counters (§3.1). If the user's actual use case is the grok.com chat app itself, a different (browser-cookie-based, not OAuth) integration would likely be needed — closer to the Cursor legacy-cookie pattern in `plan2-cursor.md` than to anything in this document.

### Which OkTally `QuotaShape` fits

- **If tracking Grok Build/coding-agent usage (the OAuth-based flow actually researched here)**: closest fit is a **percentage-pool / `creditBalance`-style shape** (same shape recommended for Cursor) — a 0–100% consumption value against a period that resets on a `billingPeriodEnd` timestamp, i.e. **not** `rollingWindow` (no sliding window was described anywhere) and **not** a simple `periodicCounter` in the sense of counting discrete requests against a fixed integer cap — it's closer to Cursor's dollar-denominated pool, except denominated in percent-of-pool rather than dollars.
- **If tracking the consumer chat daily limits** (per §3.1, if that ever gets confirmed with a real endpoint): that would fit OkTally's **`periodicCounter`** shape well — several independent fixed integer caps (messages/images/video/DeepSearch/voice), each resetting once daily at a fixed UTC time, no rolling window.
- **inferred**, since no OkTally source code / `QuotaShape` enum definitions were located in this repo during this research pass (repo is empty/not yet scaffolded per the environment — `Is directory a git repo: No`) — this recommendation is based on the shape vocabulary used in the sibling `plan2-cursor.md` and `plan2-minimax.md` research docs in this same folder, not on reading OkTally's actual Swift types.

## 4. Summary of source confidence

| Claim | Confidence |
|---|---|
| OAuth issuer is `auth.x.ai` (and/or `accounts.x.ai`); OIDC-based; `refresh_token`/`expires_at`/`oidc_client_id` fields exist | confirmed-from-source (local `~/.grok/auth.json` schema, this machine) + documented-by-community (hermes-agent docs) |
| Both device-code and PKCE-authorization-code flows are supported by xAI's OAuth | documented-by-community (pi-grok, pi-xai-oauth, hermes-agent — 3 independent sources agree) |
| Exact `/authorize`, `/oauth/token`, `/oauth/device/code` paths and literal client_id | not found — open question |
| Official Grok CLI stores tokens at `~/.grok/auth.json` | confirmed-from-source (this machine) + documented-by-community (pi-xai-oauth explicitly targets this same path) |
| hermes-agent stores tokens at `~/.hermes/auth.json` | documented-by-community |
| Refresh token ~7-day lifetime, proactive + on-401 refresh | documented-by-community (OmniRoute #7610, hermes-agent docs) |
| `grok.com/grok_api_v2.GrokBuildBilling/GetGrokCreditsConfig` gRPC-web endpoint for coding-agent quota (`credit_usage_percent`, reset time) | documented-by-community (OmniRoute #6844), unverified live |
| `x.ai/billing` ACP JSON-RPC method | documented-by-community, explicitly reported as currently broken/unimplemented (`-32601`) |
| `cli-chat-proxy.grok.com/v1/billing?format=credits` and `/v1/user` unofficial REST endpoints | documented-by-community (pi-grok, pi-xai-oauth), no captured response JSON seen |
| No community tool has reliable Grok Build quota tracking yet (open problem even in OmniRoute) | documented-by-community (OmniRoute #7610 explicitly states this) |
| Grok Build/coding-agent quota = shared weekly percentage pool (not daily fixed counters) | documented-by-community (OmniRoute #6844) |
| Consumer chat app (grok.com) quota = fixed daily counters per feature, no intra-day window | documented-by-community (third-party blog, jingrey.com — weakest source in this document) |
| This machine has an authenticated official Grok CLI installed at `~/.grok` | confirmed-from-source |

## Implementation pin (Task 11 investigation gate — Path A)

The Task 11 gate asked whether the literal OAuth `client_id` this document left
as an open question (§1.2, §4) could be found in a legitimate public source,
by reading the two working open-source OAuth clients end-to-end rather than
stopping at their README summaries. It can. Cloned both repos to a scratch
directory (never inside this project's git tree) and read the actual
request-construction code, not just prose descriptions.

**client_id — cross-confirmed by two independent, working implementations:**

```
b1a00492-073a-47ea-816f-4c329264a828
```

- `github.com/stnly/pi-grok`, commit `ae1ef2a1a839dab328766a7e8ce11aa52336259f`,
  `oauth.ts:25` — `const CLIENT_ID = process.env.PI_XAI_OAUTH_CLIENT_ID || "b1a00492-073a-47ea-816f-4c329264a828";`
  This is the production default (env-var override, not a test-only stub);
  the same literal also appears in that repo's `device-code.test.ts:10` and
  `login.test.ts:8` as the value used to construct real requests in tests.
- `github.com/BlockedPath/pi-xai-oauth`, commit `b6ba011c018614013e6e19e412a4f5cf6f03fd19`,
  `extensions/xai/constants.ts:11` — `export const XAI_OAUTH_CLIENT_ID = "b1a00492-073a-47ea-816f-4c329264a828";`
  Independently written package, same value, no shared authorship evident.

Two unrelated OAuth client codebases agreeing on the same UUID, used in live
request bodies rather than documentation prose, is strong enough corroboration
to use directly — this is reading what a working public client sends, not
reverse-engineering traffic or guessing.

**Endpoints (also cross-confirmed by both repos):**

| Purpose | URL | Source |
|---|---|---|
| OIDC discovery | `https://auth.x.ai/.well-known/openid-configuration` | pi-grok `oauth.ts:19`; pi-xai-oauth `constants.ts:5` |
| Device authorization | `https://auth.x.ai/oauth2/device/code` | pi-grok `oauth.ts:20`; pi-xai-oauth `constants.ts:6` (`XAI_OAUTH_DEVICE_URL`) |
| Token (device poll + refresh) | `https://auth.x.ai/oauth2/token` | pi-grok `oauth.ts:21`; pi-xai-oauth `constants.ts:7` (`XAI_OAUTH_TOKEN_URL`) |
| Authorization (PKCE, not used by OkTally's Path A) | `https://auth.x.ai/oauth2/authorize` | pi-xai-oauth `constants.ts:4` (`XAI_OAUTH_AUTHORIZATION_URL`) |

Device grant type: `urn:ietf:params:oauth:grant-type:device_code` (pi-grok
`oauth.ts:22`; pi-xai-oauth `constants.ts:17`). Device-code request body:
`client_id`, `scope`, and a `referrer=grok-build` field (pi-grok
`oauth.ts:906-912`) — the referrer's exact required-ness is unconfirmed, but
copying a known-working request shape carries no cost, so OkTally's request
omits it (kept the request to the RFC 8628 minimum: `client_id` + `scope`)
rather than asserting a server-side requirement neither repo's docs state
explicitly. If device-code requests ever fail in the field, `referrer` is the
first thing to try adding.

**Scopes** (identical in both repos): `openid profile email offline_access
grok-cli:access api:access conversations:read conversations:write`
— pi-grok `oauth.ts:28`; pi-xai-oauth `constants.ts:12-13`.

**Quota endpoint — corrects this document's §2.1 guess.** The original
research guessed a gRPC-web `grok.com/grok_api_v2.GrokBuildBilling/GetGrokCreditsConfig`
endpoint from an OmniRoute issue thread, without a captured request/response.
Reading pi-grok's actual working `usage.ts` shows the real mechanism is
simpler and plain JSON, not gRPC-web:

1. `GET https://cli-chat-proxy.grok.com/v1/user` (bearer token) → resolve
   `userId` (camelCase field, direct JSON, no snake_case mapping layer) —
   pi-grok `account.ts:82`; base URL pinned in pi-xai-oauth `constants.ts:26-29`
   (`XAI_CLI_BASE_URL`, `XAI_CLI_USER_URL`).
2. `GET https://cli-chat-proxy.grok.com/v1/billing?format=credits` (bearer
   token + `x-userid: <that userId>` header) → JSON body:
   `{ subscriptionTier, onDemandEnabled, config: { creditUsagePercent,
   monthlyLimit: { val }, used: { val }, currentPeriod: { start, end },
   billingPeriodStart, billingPeriodEnd, history: [...] } }` — pi-grok
   `usage.ts:14-33` (documented response shape from the same file that parses
   it) and `usage.ts:345-380` (the two pinned calls); URL also pinned
   literally in pi-xai-oauth `constants.ts:30` (`XAI_CLI_BILLING_URL`).

Required headers on every proxy call (both repos agree):
`X-XAI-Token-Auth: xai-grok-cli`, `x-authenticateresponse:
authenticate-response`, plus `Authorization: Bearer <token>` — pi-grok
`models.ts:101-111` (`buildProxyHeaders`).

`creditUsagePercent` absent in the response means 0% (xAI's JSON encoding
omits zero rather than sending it explicitly) per this doc's original §2.1
note — carried forward into the Swift implementation.

**What this means for the gate decision:** client_id, both auth endpoints,
and the quota endpoint are now pinned from source, not guessed — **Path A**.
Implemented as `Sources/OkTally/Auth/DeviceCodeFlow.swift` (RFC 8628 generic
helper), `Sources/OkTally/Plugins/SuperGrok/SuperGrokOAuth.swift` (the pinned
config above), `SuperGrokAPIClient.swift` (the two-call billing lookup), and
`SuperGrokUsageProvider.swift` (maps `creditUsagePercent` → `rollingWindow("weekly",
used: percent, limit: 100, resetAt: currentPeriod.end ?? billingPeriodEnd)`).

**Residual risk, honestly stated:** none of this is xAI's own documentation —
it is read from two community client implementations that could be wrong,
stale, or specific to the "Grok Build" coding-agent product rather than the
consumer SuperGrok chat app (see this doc's original §3 distinction, which
still applies: this plugin tracks the coding-agent quota, not the chat app's
daily message/image/video counters). If xAI changes or revokes this
`client_id`/these endpoints, OkTally's login will start failing with a normal
`DeviceCodeError`/`SuperGrokUsageError`, not silently — no different in kind
from the risk already accepted for Codex/Claude/MiniMax/Cursor's own
community-sourced OAuth pins in this same plan.

## Sources

- https://github.com/stnly/pi-grok
- https://github.com/BlockedPath/pi-xai-oauth
- https://hermes-agent.nousresearch.com/docs/guides/xai-grok-oauth
- https://github.com/NousResearch/hermes-agent/blob/main/website/docs/guides/xai-grok-oauth.md
- https://github.com/diegosouzapw/OmniRoute/issues/6844
- https://github.com/diegosouzapw/OmniRoute/issues/7610
- https://github.com/diegosouzapw/OmniRoute/issues/3755
- https://github.com/diegosouzapw/OmniRoute/issues/2760
- https://github.com/can1357/oh-my-pi/issues/5978
- https://jingrey.com/tools/grok-supergrok-rate-limits/
- Local machine: `~/.grok/auth.json`, `~/.grok/config.toml`, `~/.grok/models_cache.json` (keys/schema only, inspected on this Mac)
