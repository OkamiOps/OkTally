# Codex CLI usage/quota data — how `/status` gets it

Research target: replicate what `codex` CLI (Rust, `openai/codex` on GitHub) does to show
5h/weekly usage percentages and credits in `/status`, so OkTally (macOS menu bar app) can
poll the same data for a ChatGPT Pro ("Codex PRO 20X") account.

Local machine: codex-cli 0.145.0 installed at `/Users/marcos/.nvm/versions/node/v24.17.0/bin/codex`,
config/auth in `~/.codex/`. Source cloned from `https://github.com/openai/codex` (default branch,
shallow clone) into a scratch dir for this research; line numbers below refer to that snapshot.

## TL;DR

There is a **dedicated read-only usage endpoint** — `GET https://chatgpt.com/backend-api/wham/usage`
— that returns plan type, rate-limit window percentages, credit balance, and spend-control info
as plain JSON. This is what `/status` (and the `account/getRateLimits` app-server RPC) calls. It
requires only `Authorization: Bearer <access_token>` + `ChatGPT-Account-Id` headers — no billed
inference call needed. Confidence: **confirmed from source** (this is the actual client code, not
inferred from headers-on-inference-response behavior, which also exists as a secondary path).

## 1. Local auth file: `~/.codex/auth.json`

Confirmed present, mode `-rw-------` (600), owned by user. Schema (keys/types only, no values
printed):

```json
{
  "auth_mode": "str",
  "OPENAI_API_KEY": "null | str",
  "tokens": {
    "id_token": "str",   // JWT
    "access_token": "str",   // JWT, used as Bearer token for backend-api calls
    "refresh_token": "str",  // opaque, used against /oauth/token
    "account_id": "str"      // sent as ChatGPT-Account-Id header
  },
  "last_refresh": "str"  // ISO8601 timestamp of last refresh
}
```

The `id_token` is a JWT whose payload (claims only, not reproduced with real values) includes an
`https://api.openai.com/auth` namespace with:

```
amr, aud, auth_provider, auth_time, email, email_verified,
https://api.openai.com/auth: {
  chatgpt_account_id, chatgpt_plan_type, chatgpt_subscription_active_start,
  chatgpt_subscription_active_until, chatgpt_subscription_last_checked,
  chatgpt_user_id, groups[], localhost, organizations[{id,is_default,role,title}], user_id
},
iss, name, rat, sid, sub, iat, exp, jti, at_hash
```

`chatgpt_plan_type` is the field that would read e.g. `"pro"` for a Codex PRO 20X account (see
`PlanType` enum below — server-side this account should map to `pro` or `prolite`/business
variants; `20X` marketing name isn't itself an API field, it's a ChatGPT-side label for a Pro-tier
usage multiplier).

`config.toml` also exists in `~/.codex/` (0600) but reading it was blocked by the local sandbox
policy for this session; not required for the endpoint contract below.

## 2. The dedicated usage/rate-limit endpoint

Source: `codex-rs/backend-client/src/client/rate_limit_resets.rs`

```rust
fn rate_limit_status_url(&self) -> String {
    match self.path_style {
        PathStyle::CodexApi  => format!("{}/api/codex/usage", self.base_url),
        PathStyle::ChatGptApi => format!("{}/wham/usage", self.base_url),
    }
}
```

`PathStyle` is chosen from the configured base URL (`client.rs`): if it contains `/backend-api`
it's `ChatGptApi`. The default base URL for ChatGPT-authenticated users is
`https://chatgpt.com/backend-api` (the client auto-appends `/backend-api` to bare
`https://chatgpt.com` or `https://chat.openai.com`), which yields:

```
GET https://chatgpt.com/backend-api/wham/usage
```

This exact URL is asserted in a unit test
(`codex-rs/backend-client/src/client/rate_limit_resets_tests.rs:24-27`):

```rust
assert_eq!(
    test_client("https://chatgpt.com/backend-api", PathStyle::ChatGptApi).rate_limit_status_url(),
    "https://chatgpt.com/backend-api/wham/usage"
);
```

(If a self-hosted/enterprise `codex-backend`-style base URL is configured instead — the
"CodexApi" path style — the same call is `GET {base_url}/api/codex/usage`.)

### Headers

Built in `codex-rs/backend-client/src/client.rs::headers()`:

- `User-Agent`: the Codex CLI UA string (`get_codex_user_agent()`), or `"codex-cli"` fallback
- `Authorization: Bearer <access_token>` — from `auth.json.tokens.access_token`
  (`codex-rs/model-provider/src/bearer_auth_provider.rs:30-33`)
- `ChatGPT-Account-Id: <account_id>` — from `auth.json.tokens.account_id`
- optional `X-OpenAI-Fedramp: true` for FedRAMP accounts (not relevant here)

No request body; it's a plain `GET`.

### Response schema

`RateLimitStatusPayload` (`codex-rs/codex-backend-openapi-models/src/models/rate_limit_status_payload.rs`),
composed with an optional `rate_limit_reset_credits` field flattened in
(`RateLimitStatusWithResetCredits`, `codex-rs/backend-client/src/types.rs:51-55`):

```jsonc
{
  "plan_type": "pro",                 // enum: guest, free, go, plus, pro, prolite,
                                        // free_workspace, team, self_serve_business_prolite,
                                        // self_serve_business_usage_based, business, ent26,
                                        // enterprise_cbp_automation, enterprise_cbp_usage_based,
                                        // education, quorum, k12, enterprise, edu, unknown
  "rate_limit": {
    "allowed": true,
    "limit_reached": false,
    "primary_window": {                // 5-hour rolling window
      "used_percent": 12,               // integer 0-100
      "limit_window_seconds": 18000,    // 5h = 300 min * 60
      "reset_after_seconds": 14340,
      "reset_at": 1783875600            // unix seconds
    },
    "secondary_window": {              // weekly rolling window
      "used_percent": 41,
      "limit_window_seconds": 604800,   // 7d = 10080 min * 60
      "reset_after_seconds": 356000,
      "reset_at": 1784220000
    }
  },
  "credits": {
    "has_credits": true,
    "unlimited": false,
    "balance": "125",                  // string, may be numeric-as-string
    "approx_local_messages": [ /* opaque */ ],
    "approx_cloud_messages": [ /* opaque */ ]
  },
  "spend_control": { /* SpendControlStatusDetails — workspace monthly credit limit, not
                          fully traced; consumed as SpendControlLimitSnapshot with
                          remaining_percent/used/limit/resets_at */ },
  "additional_rate_limits": [           // extra metered limits beyond the default "codex" one,
    {                                    // e.g. per-model or per-feature limits
      "metered_feature": "codex_other",
      "limit_name": "gpt-5.2-codex-sonic",
      "rate_limit": { "primary_window": {...}, "secondary_window": {...} }
    }
  ],
  "rate_limit_reached_type": { "type": "rate_limit_reached" },  // or workspace_owner_credits_depleted,
                                                                  // workspace_member_credits_depleted,
                                                                  // workspace_owner_usage_limit_reached,
                                                                  // workspace_member_usage_limit_reached, unknown
  "rate_limit_reset_credits": { "available_count": 2 }           // free "reset credits" a user can redeem
}
```

Notes:
- `used_percent` is an **integer** 0-100, not a float, despite the app-server protocol layer
  widening it to `f64` downstream.
- The 5h vs weekly distinction is inferred purely from `limit_window_seconds` /
  `window_minutes`, not an explicit field name. The TUI classifies windows by minutes
  (`codex-rs/tui/src/chatwidget/rate_limits.rs::get_limits_duration`):
  - ~300 min (5h, ±5%) → labeled "5h limit"
  - ~1440 min (24h) → "daily limit"
  - ~10080 min (7d) → "weekly limit"
  - ~43200 min (30d) → "monthly limit"
  - ~525600 min (365d) → "annual limit"
  For a Pro plan, `primary_window` is the 5h limit and `secondary_window` is the weekly limit.
- `plan_type` also appears embedded per-snapshot when this payload is remapped internally
  into `RateLimitSnapshot` (used elsewhere for the streaming/header path, see below).

### Related endpoints on the same backend client (for completeness)

- `GET {base}/wham/rate-limit-reset-credits` — list of redeemable "reset credit" grants
  (used when a user has a coupon that fully resets their 5h+weekly windows).
- `POST {base}/wham/rate-limit-reset-credits/consume` — redeem one, body
  `{"redeem_request_id": "...", "credit_id": "..." }` (optional credit_id).
- `GET {base}/wham/profiles/me` — **token usage profile** (lifetime tokens, peak daily tokens,
  longest running turn seconds, current/longest daily streak, daily usage buckets
  `[{start_date, tokens}]`). This is separate historical/stats data, not the live quota.
- `GET {base}/wham/accounts/check` — account/eligibility check (not fully traced).
- `GET {base}/wham/workspace-messages` — workspace-level announcements shown in `/status`
  (404 if the feature is disabled for the account, handled gracefully).

## 3. Secondary path: rate-limit headers on the inference call

Independently of the `/wham/usage` GET, the CLI **also** parses rate-limit info from HTTP
response headers on every actual model turn (`POST {base}/backend-api/codex/responses`,
i.e. the Responses API call used to run a prompt). This is in
`codex-rs/codex-api/src/rate_limits.rs::parse_all_rate_limits`, invoked from
`codex-rs/codex-api/src/sse/responses.rs:40`. Header family (per metered limit id, default
`codex`):

```
x-codex-primary-used-percent
x-codex-primary-window-minutes
x-codex-primary-reset-at
x-codex-secondary-used-percent      (actually "x-codex-secondary-primary-..." per test fixture —
x-codex-secondary-window-minutes     the "secondary" limit id gets its own primary/secondary pair)
x-codex-secondary-reset-at
x-codex-<limit>-limit-name
x-codex-credits-has-credits
x-codex-credits-unlimited
x-codex-credits-balance
x-codex-promo-message
x-codex-rate-limit-reached-type
```

There's also a websocket variant: a `codex.rate_limits` SSE/WS event type carrying the same
data as JSON (`parse_rate_limit_event`, `codex-rs/codex-api/src/endpoint/responses_websocket.rs:749`).

**Implication for OkTally:** this header path only updates after the user actually sends a
prompt through Codex CLI — it is not something OkTally can poll independently without making a
real (billed) inference call. The `/wham/usage` GET is the one to use for a menu-bar poller
since it's free, read-only, and always current.

## 4. Token refresh

Source: `codex-rs/login/src/auth/manager.rs`.

- Refresh endpoint: `POST https://auth.openai.com/oauth/token`
  (`REFRESH_TOKEN_URL` / `refresh_token_endpoint()`)
- Body (JSON): `{"client_id": "app_EMoamEEZ73f0CkXaXp7hrann", "grant_type": "refresh_token", "refresh_token": "<refresh_token from auth.json>"}`
- Response (JSON): `{"id_token": "...", "access_token": "...", "refresh_token": "..."}` (all
  optional; whichever are present get written back into `auth.json`, along with updating
  `last_refresh`)
- Revoke endpoint (logout): `POST https://auth.openai.com/oauth/revoke`
- Failure classification (`classify_refresh_token_failure`) parses an error code from the
  response body and maps it to:
  - `refresh_token_expired` → Expired
  - `refresh_token_reused` → Exhausted (token was already used/rotated — refresh tokens are
    apparently single-use/rotating)
  - `refresh_token_invalidated` → Revoked
  - anything else → `Other` (treated as possibly transient, e.g. network blip, unless HTTP
    status is 401, which is always treated as permanent failure)
- The `access_token` is itself a JWT with an `exp` claim (see section 1) — OkTally can check
  that locally before deciding to call `/wham/usage`, and treat any 401 from `/wham/usage` as
  "needs refresh"; a failed refresh (permanent reasons above) should surface as "please run
  `codex login` again" in the UI, since OkTally should not attempt interactive OAuth itself.

## 5. Practical plan for OkTally's Codex plugin

1. Read `~/.codex/auth.json`, extract `tokens.access_token` and `tokens.account_id`.
2. `GET https://chatgpt.com/backend-api/wham/usage` with
   `Authorization: Bearer <access_token>` and `ChatGPT-Account-Id: <account_id>` headers.
3. Parse `rate_limit.primary_window` (5h) and `rate_limit.secondary_window` (weekly) for
   `used_percent` / `reset_at`; parse `credits` if present; read `plan_type` for display.
4. On 401: attempt one silent refresh via `POST https://auth.openai.com/oauth/token`
   (`client_id=app_EMoamEEZ73f0CkXaXp7hrann`, `grant_type=refresh_token`,
   `refresh_token=<tokens.refresh_token>`), persist the new tokens back into `auth.json`
   (matching the CLI's own behavior so both tools stay in sync), and retry once.
5. If refresh fails permanently (expired/revoked/reused), show a "sign in again with `codex
   login`" state rather than trying to drive an OAuth flow from the menu bar app.

## Confidence & sources

- Endpoint URL, headers, request/response shapes, refresh flow: **confirmed from source**,
  read directly from `openai/codex` (Rust) at the paths cited above (cloned
  `https://github.com/openai/codex`, default branch, into a scratch dir for this research).
  Key files:
  - `codex-rs/backend-client/src/client/rate_limit_resets.rs`
  - `codex-rs/backend-client/src/client/rate_limit_resets_tests.rs` (asserts the literal
    `https://chatgpt.com/backend-api/wham/usage` URL)
  - `codex-rs/backend-client/src/client.rs` (headers/auth, `/wham/profiles/me`, etc.)
  - `codex-rs/backend-client/src/types.rs`
  - `codex-rs/codex-backend-openapi-models/src/models/rate_limit_status_payload.rs`,
    `rate_limit_status_details.rs`, `rate_limit_window_snapshot.rs`, `credit_status_details.rs`
  - `codex-rs/app-server/src/request_processors/account_processor.rs` (wires
    `account/getRateLimits` RPC → `get_rate_limits_with_reset_credits()`)
  - `codex-rs/codex-api/src/rate_limits.rs`, `codex-rs/codex-api/src/sse/responses.rs`
    (secondary header-based path)
  - `codex-rs/login/src/auth/manager.rs` (refresh/revoke endpoints, client id, request/response
    shape, failure classification)
  - `codex-rs/tui/src/status/rate_limits.rs`, `codex-rs/tui/src/chatwidget/rate_limits.rs`
    (how `/status` labels 5h vs weekly vs monthly from `window_minutes`)
- Local auth.json / id_token JWT schema (keys/types only): **confirmed from this machine**,
  `~/.codex/auth.json`, codex-cli 0.145.0.
- No external "community usage tracker" project was consulted — the primary CLI source was
  sufficient and authoritative, so no separate write-up of e.g. ccusage-style tools was done.
- Not verified end-to-end: an actual live call to `https://chatgpt.com/backend-api/wham/usage`
  was not made in this session (would require using the real access token, which per the
  security rule for this task was not printed/exfiltrated). The URL/shape above is exactly what
  the CLI's own code sends and expects, so it should work as-is, but OkTally should still
  handle unexpected-schema responses defensively (e.g. new plan types, missing fields) since
  this is an undocumented internal API subject to change without notice.

Source repo: https://github.com/openai/codex
