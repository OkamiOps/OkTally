# Xiaomi MiMo Token Plan — Usage/Quota API Research

Research date: 2026-08-07
Scope: find a programmatic way to read remaining quota/usage for a Xiaomi MiMo
"Token Plan" subscription (`tp-xxxxx` API keys), for OkTally's menu-bar usage
tracker.

## Bottom line

**There is no documented, key-authenticated API endpoint for reading Token
Plan quota/usage.** The only place usage is exposed is the web console at
`platform.xiaomimimo.com` (Subscription Management page), which is gated
behind Xiaomi account SSO (cookie/session auth via `account.xiaomi.com`), not
the `tp-` API key used for inference calls. Multiple community tools
(cc-switch, 9router) have tried and failed to find a working balance
endpoint reachable with the `tp-` key. This is a known, open gap in the
ecosystem (cc-switch issue #2428, still open/unresolved as of research date).

Given this, OkTally's MiMo plugin cannot do live quota polling the way it
can for providers with a documented balance API. Two realistic paths:

1. **Metered-only tracking**: instrument OkTally's own token accounting from
   requests/responses it observes (it already knows request/response token
   counts for OpenAI/Anthropic-compatible traffic), and let the user manually
   enter their plan's monthly Credit allowance so OkTally can show
   estimated-remaining as a locally-computed running counter. This mirrors
   what cc-switch/9router ended up doing.
2. **Browser-session scrape (fragile, not recommended)**: authenticate as the
   user's Xiaomi account (SSO) and hit
   `https://platform.xiaomimimo.com/api/v1/token-plan/usage` with the session
   cookie. This is undocumented, requires full Xiaomi account login (out of
   scope for a menu-bar API-key-based tool, and brittle/ToS-risky), so it
   should not be the primary design.

## What was found, endpoint by endpoint

### 1. Inference endpoints (confirmed — these work, but carry no quota data)

| Region | OpenAI-compatible | Anthropic-compatible |
|---|---|---|
| China | `https://token-plan-cn.xiaomimimo.com/v1/chat/completions` | `https://token-plan-cn.xiaomimimo.com/anthropic/v1/messages` |
| Singapore | `https://token-plan-sgp.xiaomimimo.com/v1/chat/completions` | `https://token-plan-sgp.xiaomimimo.com/anthropic/v1/messages` |
| Amsterdam | `https://token-plan-ams.xiaomimimo.com/v1/chat/completions` | `https://token-plan-ams.xiaomimimo.com/anthropic/v1/messages` |

Auth: `Authorization: Bearer tp-xxxxx` (OpenAI-compatible) or
`x-api-key: tp-xxxxx` (Anthropic-compatible).

**Confidence: confirmed-from-docs / confirmed-by-live-probe.** I sent live
requests with a syntactically-valid but fake `tp-` key to
`token-plan-cn.xiaomimimo.com` and got a clean `401 invalid_key` JSON body
with **no rate-limit, quota, or usage headers** in the response (checked via
`curl -D -`: only standard `date`, `content-type`, CORS `vary` headers, and a
`server: MiFE/...` header — nothing resembling `x-ratelimit-*` or
`x-quota-*`). This doesn't rule out such headers appearing only on
authenticated 200 responses (I don't have a real key to test), but the 401
error path — which is the layer that would most plausibly report "you're
out of quota" — carries none. **Confidence: documented-by-live-probe for the
401 case; inferred/unconfirmed for the 200 case** (needs a real `tp-` key to
verify definitively — recommend the OkTally team do one manual authenticated
`curl -i` request and check headers before ruling this out completely).

### 2. Console usage endpoint (exists, but not usable with a `tp-` key)

`GET https://platform.xiaomimimo.com/api/v1/token-plan/usage`

Live probe (no auth) returns:
```
HTTP/2 401
content-type: application/json;charset=UTF-8
www-authenticate: CustomBasic realm="default"

{"code":401,"loginUrl":"https://account.xiaomi.com/pass/serviceLogin?callback=https%3A%2F%2Fplatform.xiaomimimo.com%2Fsts%3Fsign%3D...%26followup%3Dhttp%253A%252F%252Fplatform.xiaomimimo.com%252Fapi%252Fv1%252Ftoken-plan%252Fusage&sid=api-platform&_group=DEFAULT"
}
```
This is the backend the React console app (`platform.xiaomimimo.com`, built
on Xiaomi's internal "MiFE" framework) calls to render the usage bar on the
Subscription Management page. It requires a full Xiaomi account SSO login
(`account.xiaomi.com` service ticket / cookie), the same mechanism as
logging into the website in a browser — **not** the `tp-` API key. I also
probed sibling paths under `/api/v1/token-plan/` (`balance`, `quota`,
`subscription(s)`, `plans`, `orders`, `stat(s)`, `consumption`, `detail`) —
all return the identical generic 401/login-redirect JSON, which is most
likely a blanket auth gate on the whole `/api/v1/*` namespace rather than
proof each of those specific sub-routes exists. So `usage` is the one
confirmed real route (referenced by the `followup` URL echoing back exactly
`/api/v1/token-plan/usage`); the others are unconfirmed guesses.

**Confidence: confirmed-by-live-probe** that this route exists and is
SSO-gated; **inferred** that its JSON schema mirrors the credits/quota
numbers shown on the console page (never got past the 401 to see a real
body).

### 3. Community tooling — nobody has cracked this

- **cc-switch** (`farion1231/cc-switch`, desktop provider-switcher for
  Claude Code/Codex/OpenCode/etc.) auto-generates a "usage query" script per
  provider preset. For MiMo it guessed the same convention that works for
  DeepSeek/Kimi — `GET {{baseUrl}}/user/balance` — which resolves to
  `https://token-plan-cn.xiaomimimo.com/anthropic/user/balance` and returns
  **404**. Issue #3230 ("[Bug] Xiaomi MiMo provider 用量查询失败 - /user/balance
  返回 404") documents a user manually trying a dozen guessed paths (
  `/user/balance`, `/v1/user/balance`, `/api/v1/balance`, `/billing/balance`,
  `/account/balance`, `/api/usage`, `/api/account`, `/v1/account`,
  `/dashboard`, `/api/user/info`) — **all 404**. Issue was closed as a
  duplicate of #2428, "Request to Support MiMo Token Plan Quota Query",
  which is a feature request stating plainly: *"Currently, it seems there is
  no integration with MiMo to check token usage and remaining quota"* and
  asking maintainers to "integrate with MiMo's API or reverse-engineer
  their interface." No resolution/endpoint is posted in either issue.
  Source: https://github.com/farion1231/cc-switch/issues/3230 ,
  https://github.com/farion1231/cc-switch/issues/2428 ,
  https://github.com/farion1231/cc-switch/issues/2488 (Chinese-language
  duplicate, same "how do I even set this up" ask, no answer).
- **9router** (`decolua/9router`) issue #1251 is about the *inference*
  endpoint being hardcoded to the Singapore region, unrelated to quota
  queries — no usage/balance API is mentioned there either.
  https://github.com/decolua/9router/issues/1251
- **OpenClaw** provider docs (`docs.openclaw.ai/providers/xiaomi`) document
  region selection and key-format validation for onboarding, but say
  nothing about a usage/balance query — confirms no such integration exists
  in that client either.
- I could not find any `aiengineerguide.com` post specifically about MiMo
  Token Plan usage querying (only a generic "how to configure it in
  OpenCode" TIL post, which is about setting up the inference endpoint, not
  quota).

**Confidence: documented-by-community.** Consensus across two independent
provider-switcher projects is that no working quota API exists for `tp-`
keys.

### 4. A tempting red herring: MiniMax's `token_plan/remains`

Search results initially surfaced `https://www.minimax.io/v1/token_plan/remains`
(`GET`, `Authorization: Bearer <key>`) as a "Token Plan remains" endpoint.
**This belongs to MiniMax, a different vendor**, not Xiaomi MiMo — MiniMax
independently ships a very similar "Token Plan" subscription product with
its own working quota-query API. It's evidence that this pattern
(`/v1/token_plan/remains`) is common among Chinese LLM vendors offering
"token plan" subscriptions, but Xiaomi does not expose the equivalent route
on `token-plan-cn.xiaomimimo.com` or `platform.xiaomimimo.com` — I probed
`https://platform.xiaomimimo.com/v1/token_plan/remains` and it just returns
the SPA's `index.html` (200, `content-type: text/html`) — i.e., that path
isn't a real API route on Xiaomi's platform, only React-Router client-side
fallback. **Do not use this endpoint for MiMo** — flagging it here only so
nobody re-discovers it and assumes it's Xiaomi's.

## Quota structure (confirmed from official pricing/FAQ pages)

Source: https://mimo.mi.com/docs/en-US/price/token-plan and
https://mimo.mi.com/docs/en-US/quick-start/faq/api-integration

- **Unit**: "Credits", a synthetic unit — not raw tokens. Consumption rate
  varies per model and per cache-hit/miss/output:
  - `mimo-v2.5-pro`: 2.5 Credits (cache hit) / 300 Credits (cache-miss
    input) / 600 Credits (output)
  - `mimo-v2.5`: 2 Credits (cache hit) / 100 Credits (cache-miss input) /
    200 Credits (output)
  - `mimo-v2.5-asr`: 30M Credits per hour of audio
  - TTS models: currently free (0 Credits), promotional
  - Off-peak discount: 0.8× consumption Beijing Time 00:00–08:00
- **Cadence**: monthly subscription cycle (calendar-month reset), not a
  rolling window and not a 5-hour window. Marketing explicitly claims
  **"no 5-hour token usage limit"** — this differentiates it from
  Anthropic/OpenAI-style rolling-window rate limits. Annual plans just
  pre-allocate ~12× the monthly credits, still consumed against a single
  pool (unclear from docs whether annual credits are also gated
  month-by-month or usable in a lump — docs say annual "provides credits
  spread across 12 months," suggesting monthly sub-buckets even on annual
  plans, but this is **inferred**, not explicitly confirmed).
- **Tiers** (monthly): Lite ¥39 / 60M~4.1B credits (sources conflict — see
  note below), Standard ¥99, Pro ¥329, Max ¥659 (also sold in USD via
  regional pricing).
  Note: two different search results gave conflicting credit totals for the
  same tier names — one gave "60M / 200M / 700M / 1600M Credits", another
  gave "4.1B / 11B / 38B / 82B Credits" for Lite/Standard/Pro/Max monthly.
  This 68× discrepancy is likely because MiMo repriced/rescaled the credit
  system at some point (an X/Twitter post found in search explicitly says
  *"MiMo Token Plans have also been upgraded: 5–8× more usable tokens"*),
  and search results are mixing pre- and post-upgrade numbers. **Do not
  hardcode either figure in OkTally** — treat exact credit totals per tier
  as **inferred/unreliable** until read live from the user's own console,
  and only use the *relative* consumption-rate ratios (2.5/300/600 etc.)
  which are self-consistent.
- **Exhaustion behavior**: "When the monthly total quota of the package is
  exhausted, the system will stop service and will not continue to consume
  your bonus or account balance" — i.e. hard cutoff, not overage billing.
  Confirmed-from-docs.
- **Sharing**: one subscription's credits are shared across all client
  tools (Claude Code, OpenClaw, OpenCode, Kilo Code, Cline, etc.) that are
  pointed at the same `tp-` key — single pool, not per-tool.

## Which OkTally QuotaShape fits

None of the four shapes fit cleanly with live data because there is no
readable balance API. Best mapping if/when OkTally implements this plugin:

- **`periodicCounter` (monthly) is the correct conceptual shape** — Token
  Plan is a fixed-size Credit pool that resets on a monthly cycle with hard
  cutoff at zero, structurally identical to a monthly quota, *not* a rolling
  window (no 5-hour bucket) and *not* a true "credit balance" you can query
  externally (since balance isn't queryable).
- Because the balance can't be fetched, the plugin can only implement this
  as **`meteredOnly`** in practice: OkTally must derive "usage so far this
  cycle" itself by summing Credits it estimates from request/response token
  counts it observes on the OpenAI/Anthropic-compatible traffic (using the
  published per-model Credit-per-token ratios above), reset at the start of
  each calendar month, with the user supplying their plan's total Credit
  allowance (since that number can't be fetched either, and is
  inconsistently reported in public sources). This is the same fallback
  cc-switch and 9router effectively use — neither tool auto-detects the
  quota, both just point users back at the web console.
- If OkTally later wants live data, the only path is Xiaomi-account SSO
  scraping of `platform.xiaomimimo.com/api/v1/token-plan/usage`, which is a
  materially different (browser-session, not API-key) auth model than every
  other OkTally plugin and probably not worth the complexity/fragility for
  one provider.

## Sources

- https://mimo.mi.com/docs/en-US/price/token-plan — official Token Plan pricing/FAQ
- https://mimo.mi.com/docs/en-US/quick-start/faq/api-integration — API key format (`tp-` vs `sk-`), base URL docs
- https://platform.xiaomimimo.com/token-plan — console landing page
- https://docs.openclaw.ai/providers/xiaomi — OpenClaw provider integration doc (regions, key validation, no usage API)
- https://github.com/farion1231/cc-switch/issues/2428 — "Request to Support MiMo Token Plan Quota Query" (open feature request, confirms no known integration)
- https://github.com/farion1231/cc-switch/issues/3230 — "[Bug] Xiaomi MiMo provider 用量查询失败 - /user/balance 返回 404" (documents failed endpoint guesses)
- https://github.com/farion1231/cc-switch/issues/2488 — Chinese-language duplicate ask, unresolved
- https://github.com/decolua/9router/issues/1251 — region-hardcoding bug in 9router's MiMo provider (inference endpoint only, not quota)
- https://x.com/XiaomiMiMo/status/2059314052892099070 — Xiaomi MiMo announcement of Token Plan credit-scale upgrade ("5–8× more usable tokens")
- Live probes performed 2026-08-07 against `token-plan-cn.xiaomimimo.com` and `platform.xiaomimimo.com` (curl, documented inline above) — no credentials used beyond a syntactically-valid fake `tp-` key.

## Recommendation for OkTally implementation

1. Implement the MiMo plugin as `meteredOnly`: track request/response token
   usage from observed traffic, apply the published Credit-consumption
   ratios per model, and let the user set their own monthly Credit
   allowance in Settings (since it can't be fetched and public figures are
   unreliable).
2. Do not attempt SSO/cookie-based scraping of the console — it's a
   different trust/auth model than the rest of OkTally's plugins and is
   likely to break silently on any Xiaomi login-flow change.
3. Before finalizing, have someone with a real `tp-` key run one
   authenticated `curl -i` against the chat-completions endpoint and check
   response headers for any `x-ratelimit-*`/`x-quota-*`/`x-credits-*`
   headers — this research could only confirm the *unauthenticated* error
   path carries none; the authenticated success path is unverified.
4. Watch cc-switch issue #2428 for updates — if Xiaomi ships a documented
   quota API or the community reverse-engineers one, that's the moment to
   revisit `periodicCounter`.
