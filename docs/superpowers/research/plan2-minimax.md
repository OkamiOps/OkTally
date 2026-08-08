# MiniMax Token Plan (Coding Plan) — Usage/Balance API Research

## Re-confirmação do endpoint (dono reportou URL errada)

**Investigado em 2026-08-08. O dono está certo: o host que o OkTally usa hoje está errado.**

### Veredito

| | Path | Method | Header | Host usado hoje no código | Host correto (oficial) |
|---|---|---|---|---|---|
| Global | `/v1/token_plan/remains` | GET | `Authorization: Bearer <key>` | `api.minimax.io` ❌ | **`www.minimax.io`** ✅ |
| China | `/v1/token_plan/remains` | GET | `Authorization: Bearer <key>` | `api.minimaxi.com` ❌ | **`www.minimaxi.com`** ✅ |

O **path** (`/v1/token_plan/remains`), o **método** (GET) e o **header** (`Authorization: Bearer <API Key>`) que já estavam no código sempre estiveram certos. O único erro é o **subdomínio**: o código usa `api.` e o correto é `www.`.

Código atual do OkTally (`Sources/OkTally/Plugins/MiniMax/MiniMaxAPIClient.swift:10-11`):
```swift
case .global: return "https://api.minimax.io"
case .china: return "https://api.minimaxi.com"
```
Deveria ser `https://www.minimax.io` e `https://www.minimaxi.com`.

### Evidência (duas fontes independentes, ambas de 2026, ambas verbatim)

**1. Doc oficial** — `platform.minimax.io/docs/token-plan/faq` (seção "How to check Token Plan usage?" → "Method 2: Use the API Endpoint"), texto exato extraído do markdown fonte (`.md` da doc, não resumo de modelo):
```bash
curl --location 'https://www.minimax.io/v1/token_plan/remains' \
--header 'Authorization: Bearer <API Key>' \
--header 'Content-Type: application/json'
```
A versão em chinês da mesma doc (`platform.minimaxi.com/docs/token-plan/faq`) confirma o equivalente para a China:
```bash
curl --location 'https://www.minimaxi.com/v1/token_plan/remains' \
--header 'Authorization: Bearer <API Key>' \
--header 'Content-Type: application/json'
```
Ambas obtidas via `curl` direto no `.md` da doc (bypass do renderer JS), portanto texto literal da MiniMax, não paráfrase.

**2. `junhoyeo/tokscale` (ferramenta comunitária ativa, código-fonte atual em 2026)** — arquivo `crates/tokscale-cli/src/commands/usage/minimax_tokenplan.rs`, lido diretamente do raw GitHub:
```rust
const TOKEN_PLAN_PATH: &str = "/v1/token_plan/remains";
const SITES: &[Site] = &[
    Site { label: "CN", base_url: "https://www.minimaxi.com", key_env: "MINIMAX_TOKEN_PLAN_CN_KEY" },
    Site { label: "Global", base_url: "https://www.minimax.io", key_env: "MINIMAX_TOKEN_PLAN_GLOBAL_KEY" },
];
```
com comentário no código: *"MiniMax runs separate token-plan backends for its domestic (minimaxi.com) and international (minimax.io) sites, each behind its own API key."* Headers usados: `Authorization: Bearer <key>`, `Content-Type: application/json`, `Accept: application/json`.

O teste unitário embutido no arquivo (`SAMPLE` JSON) confirma que o **formato de resposta que o código do OkTally já espera está correto** — `model_remains[]` com `model_name`, `current_interval_remaining_percent`, `end_time`, `current_weekly_status`, `current_weekly_remaining_percent`, `weekly_end_time`, `current_interval_total_count`, `current_interval_usage_count`, `current_weekly_total_count`, `current_weekly_usage_count`, `remains_time`, `weekly_remains_time`, mais `base_resp.status_code` / `status_msg`. Não há mudança de schema necessária, só o host.

### Testes ao vivo (sem chave válida, só para checar que os hosts existem e respondem)

Todos os quatro hosts (`api.minimax.io`, `www.minimax.io`, `api.minimaxi.com`, `www.minimaxi.com`) devolveram o mesmo erro de auth (`status_code 1004`, "Please carry the API secret key...") para `GET /v1/token_plan/remains` com uma chave inválida — ou seja, o path resolve nos quatro, o que por si só **não prova qual host é o certo** (provavelmente o mesmo backend/CDN atrás dos quatro nomes, ou um gate de auth que roda antes da checagem de rota). O que decide a questão é a doc oficial + o código-fonte do tokscale, ambos apontando explicitamente para `www.`, nunca `api.`.

Também testei o path alternativo mencionado na issue `MiniMax-AI/MiniMax-M2` #88 (`/v1/api/openplatform/coding_plan/remains` em `www.minimaxi.com`) — esse devolve uma mensagem de erro **diferente** ("cookie is missing, log in again"), confirmando que é de fato um endpoint interno do console que exige sessão de navegador, não chave de API. Não é o endpoint certo — o `/v1/token_plan/remains` é.

### Nível de confiança

**Alto.** Duas fontes independentes e atuais (doc oficial em markdown puro + código-fonte de ferramenta open-source ativa com teste unitário embutido) concordam exatamente no host, path, método e header. Nenhuma fonte aponta `api.` como correto.

### Ação recomendada

Em `Sources/OkTally/Plugins/MiniMax/MiniMaxAPIClient.swift`, trocar:
```swift
case .global: return "https://api.minimax.io"
case .china: return "https://api.minimaxi.com"
```
por:
```swift
case .global: return "https://www.minimax.io"
case .china: return "https://www.minimaxi.com"
```
Nenhuma outra mudança é necessária — path, método, header e schema de resposta já estão corretos.

---

Researched 2026-08-07 for OkTally's MiniMax usage plugin.

## TL;DR

There is a real, working, key-authenticated endpoint for Token Plan quota:

```
GET https://api.minimax.io/v1/token_plan/remains        (Global)
GET https://api.minimaxi.com/v1/token_plan/remains       (Mainland China)
Authorization: Bearer <subscription/coding-plan API key, format sk-cp-...>
```

It returns, per model, two parallel quota windows — a **5-hour rolling** window and a **weekly** window — as usage counts and remaining-percent fields, plus a `remains_time` countdown in ms. This is the same endpoint community tools (`tokscale`, VS Code MiniMax status-bar extensions) poll to build usage displays. **Confidence: documented-by-community** (not in MiniMax's public API reference docs as of this research; confirmed via multiple independent GitHub issues/repos that show real response fields).

There is a **separate, similarly-named but cookie-only endpoint** that looks like the "right" one but does not work with an API key — a known trap. Avoid `.../coding_plan/remains` and `/backend/account/token_plan_credit`.

---

## 1. Official docs (platform.minimax.io / platform.minimaxi.com)

- `platform.minimax.io/docs/token-plan/intro` (Token Plan Overview) confirms the **product model**: Token Plan is a monthly subscription accessed via a "Subscription Key," billed against a unified included quota shared across supported API resources, enforced by **two quota windows: a 5-hour rolling window and a weekly window**. Unused quota does not carry over. When exhausted, usage can spill over into purchased Credits (a prepaid balance on the same key), or you can upgrade tier / switch to pay-as-you-go / wait for reset. Credits expire 365 days after purchase.
  - Confidence: **confirmed-from-docs** (page fetched directly).
  - The page explicitly states usage is shown as **a usage bar in the console** (Account → Token Plan) and does **not** document any REST/GraphQL endpoint for programmatic querying.
- `platform.minimax.io/docs/api-reference/api-overview` lists the full public API surface (LLM chat via OpenAI/Anthropic-compatible routes, video generation, speech/T2A, image, music, file management). **No balance/usage/account-info endpoint is listed** in the public API reference.
  - Confidence: **confirmed-from-docs**.
- Conclusion: MiniMax does **not** officially/publicly document a balance-query API for Token Plan in the developer API reference — unlike their historical pay-as-you-go wallet, which (per general MiniMax knowledge) also lacks a documented public balance endpoint in the current docs tree searched. The `/v1/token_plan/remains` endpoint below appears to be an internal/console-support endpoint that happens to accept the same Bearer API key used for chat completions, discovered and reverse-engineered by the community rather than published in the reference docs.

## 2. Community tools that read Token Plan quota

- **`junhoyeo/tokscale`** (GitHub) — a terminal usage tracker for AI coding agents with a "global leaderboard." Its README explicitly lists MiniMax Token Plan support as: *"API key (env var) — Interval + weekly remaining-percent quotas (per region: CN minimaxi.com + Global minimax.io)"*, configured via env vars `MINIMAX_TOKEN_PLAN_CN_KEY` / `MINIMAX_TOKEN_PLAN_GLOBAL_KEY`. This confirms: (a) the key itself is enough (no cookie), (b) both regions are supported with distinct base URLs, (c) the data returned is framed as "interval" (5h) + "weekly" remaining percentages — matching the `/v1/token_plan/remains` schema found elsewhere.
  - Confidence: **documented-by-community**.
- **`JochenYang/minimax-status`** (GitHub) — a status-bar tool (VS Code + shell) explicitly built to show "token-plan 使用额度、剩余次数、重置时间" (usage quota, remaining count, reset time), with claude-code-statusline and OpenClaw integration. Auth flow: `minimax auth <token>` stores the key locally, then the tool polls. README output examples show: 5h quota remaining %, weekly quota remaining % (example: "5天 23小时后重置" — "resets in 5 days 23 hours" for the weekly window), plus token consumption stats broken down by yesterday / last 7 days / current month, and plan expiration date.
  - The README also flags **a second, cookie-only endpoint**: `/backend/account/token_plan_credit`, noted as **not usable from CLI/extensions** because it only accepts browser session cookies, not API keys. This is a distinct (and less useful) endpoint from `/v1/token_plan/remains`.
  - Confidence: **documented-by-community**.

## 3. Response schema (observed directly in GitHub issues against real accounts)

From `MiniMax-AI/MiniMax-M2.7` issue #48 ("Token Plan Plus yearly upgrade: total_count and usage_count return 0") and `MiniMax-AI/cli` issue #173 ("mmx quota show reports 100% remaining for video..."), both showing real JSON/CLI output from `GET /v1/token_plan/remains`, per model entry:

```json
{
  "model_name": "general",
  "current_interval_total_count": 0,
  "current_interval_usage_count": 0,
  "current_weekly_total_count": 0,
  "current_weekly_usage_count": 0,
  "current_interval_remaining_percent": 13,
  "current_weekly_remaining_percent": 100,
  "current_interval_status": 3,
  "current_weekly_status": 3,
  "remains_time": 0
}
```

- `current_interval_*` = the **5-hour rolling window** counters (interval = 5h bucket).
- `current_weekly_*` = the **weekly window** counters.
- `*_total_count` / `*_usage_count`: an allotted-vs-consumed count pair. Unit is ambiguous from the issues surfaced (likely "requests" or an internal normalized unit, not raw tokens — issue #25 on `MiniMax-M3` notes MiniMax's own FAQ does **not** specify whether the bucket fills with input tokens, output tokens, `cache_read`, `cache_write`, or a weighted blend, and reports empirically that `cache_read` tokens dominate consumption (97.3% of one session) and appear to grow monotonically — a possible billing/caching bug users were disputing at the time, not a documented mechanic).
- `*_remaining_percent`: 0–100, the number to show in a menu-bar gauge.
- `*_status`: an integer status code (values 0–3+ observed); semantics not documented — likely something like "not provisioned / active / near-limit / exhausted." Treat as opaque unless MiniMax documents it.
- `remains_time`: milliseconds until the interval/weekly window resets (a countdown, "drains passively" per the community tool description).
- The endpoint returns **one entry per model tier** the plan covers (e.g. `general` for chat/coding models, and separately a `video` entry for video generation — confirmed by issue #173, where video shows `0/0` total/usage but 100% remaining because video isn't bundled into that plan, producing a confusing "100% of a zero-size quota" edge case). **OkTally should special-case `total_count == 0` as "not entitled" rather than "fully available."**

Confidence: **documented-by-community** (real observed responses in bug reports, not from an official schema doc — field names/semantics could shift without notice since this isn't a versioned public API).

## 4. Response headers / rate-limit style quota exposure

No evidence was found that MiniMax's OpenAI-compatible or Anthropic-compatible chat-completion endpoints (`/v1/chat/completions`, `/v1/messages`) return `X-RateLimit-*` or similar quota headers on normal completion responses. All community tooling instead makes a **separate, dedicated GET call** to `/v1/token_plan/remains` to fetch quota state; none of the researched tools parse response headers from chat calls for this purpose. If OkTally wants live quota, it must poll this separate endpoint rather than piggyback on inference responses.

Confidence: **inferred** (absence of evidence across all sources checked, not an explicit documented "no headers" statement from MiniMax).

## 5. The cookie-only trap (avoid)

`MiniMax-AI/MiniMax-M2` issue #88, "API endpoint /coding_plan/remains requires cookie session instead of API Key":

- Endpoint tried: `https://www.minimaxi.com/v1/api/openplatform/coding_plan/remains`
- Auth tried: `Authorization: Bearer sk-cp-...` (also tried the `MiniMax-API-Key` header that works elsewhere)
- Result: `{"base_resp": {"status_code": 1004, "status_msg": "cookie is missing, log in again"}}`
- Issue was closed with no maintainer resolution/comment recorded.

This is a **different path** than `/v1/token_plan/remains` (note: `.../openplatform/coding_plan/remains` vs `.../v1/token_plan/remains`) and appears to be the backend the **web console's usage bar** actually calls, gated to browser session cookies only. **Do not build OkTally's plugin against this one** — it will always fail for a headless API-key client. Use `/v1/token_plan/remains` instead.

Confidence: **documented-by-community** (real, specific error payload from an actual issue report).

## 6. Region variants

- Global platform: base URL `api.minimax.io` — key prefix/behavior tied to `minimax.io` account.
- Mainland China platform: base URL `api.minimaxi.com` — separate account/key space tied to `minimaxi.com`.
- Both expose `/v1/token_plan/remains` at their respective base URL with the same Bearer-key auth pattern (per `tokscale`'s explicit dual env-var support for `MINIMAX_TOKEN_PLAN_CN_KEY` / `MINIMAX_TOKEN_PLAN_GLOBAL_KEY`).
- Keys are **not interchangeable across regions** — a global `sk-cp-...` key won't authenticate against the China base URL and vice versa. OkTally's plugin config should let the user pick region (or auto-detect via a probe call) rather than hardcoding one host.

Confidence: **documented-by-community** for the shared endpoint path; **confirmed-from-docs** for the general global-vs-China account separation (well-established MiniMax platform structure).

## 7. Which OkTally QuotaShape fits

MiniMax Token Plan doesn't map cleanly onto a single one of `rollingWindow` / `periodicCounter` / `creditBalance` / `meteredOnly` — it's a **dual-window counter**, and OkTally will likely need to represent it as two stacked trackers or extend the shape:

- **5-hour window (`current_interval_*`)**: functionally a **rollingWindow** — it drains and refills on a short, continuously-recurring cycle (not tied to a calendar boundary), analogous to Anthropic's 5-hour session limits. Use `rollingWindow` with a 5h period and `remains_time` as the reset countdown.
- **Weekly window (`current_weekly_*`)**: closer to **periodicCounter** — resets on a fixed weekly cadence with no rollover, similar to a subscription's periodic entitlement reset. Use `periodicCounter` with a 7-day period.
- **Credits overflow**: once both windows are exhausted, spend can fall through to purchased **Credits**, which behave like a **creditBalance** (prepaid, 365-day expiry, decremented per overflow usage) — but the `/v1/token_plan/remains` endpoint researched here does not appear to expose the Credits balance itself (that seems to live under the cookie-gated `/backend/account/token_plan_credit`, per `minimax-status`'s README warning). If OkTally wants to show Credits balance too, that path currently looks **blocked for headless/API-key use** — flag as an open gap rather than assume it's fetchable.
- Recommendation: model MiniMax Token Plan in OkTally as **two parallel rollingWindow/periodicCounter gauges** (5h + weekly) sourced from `/v1/token_plan/remains`, and treat Credits balance as **unavailable via API** for now (console-only) unless further reverse-engineering finds a key-auth path to it.

Confidence: **inferred** (this is OkTally-side design judgment applied to the confirmed/community-documented facts above, not something MiniMax states).

## 8. Suggested plugin request/response shape for OkTally

```
GET {base}/v1/token_plan/remains
Host: api.minimax.io | api.minimaxi.com   (region-selectable)
Authorization: Bearer <sk-cp-... Token Plan key>
```

Parse the `general` (or relevant coding/chat) model entry from the response array/object; surface:
- `current_interval_remaining_percent` → 5h rolling gauge
- `current_weekly_remaining_percent` → weekly gauge
- `remains_time` → "resets in Xh Ym" style countdown
- Guard: if `current_interval_total_count == 0` **and** `current_weekly_total_count == 0`, show "not entitled for this model" instead of "100% remaining" (per the video-quota 0/0 bug in cli issue #173).

Before shipping, OkTally should do a live probe call against a real Token Plan key to confirm the exact response envelope (array vs keyed-by-model object) since no source produced the literal raw JSON wrapper — only the per-model field list — during this research pass.

---

## Sources

- [Token Plan Overview - MiniMax API Docs](https://platform.minimax.io/docs/token-plan/intro)
- [API Overview - MiniMax API Docs](https://platform.minimax.io/docs/api-reference/api-overview)
- [Issue #88 - API endpoint /coding_plan/remains requires cookie session instead of API Key · MiniMax-AI/MiniMax-M2](https://github.com/MiniMax-AI/MiniMax-M2/issues/88)
- [Issue #48 - Token Plan Plus yearly upgrade: total_count and usage_count return 0 · MiniMax-AI/MiniMax-M2.7](https://github.com/MiniMax-AI/MiniMax-M2.7/issues/48)
- [Issue #173 - mmx quota show reports 100% remaining for video · MiniMax-AI/cli](https://github.com/MiniMax-AI/cli/issues/173)
- [Issue #25 - Token Plan quota exhausts in long sessions (cache_read) · MiniMax-AI/MiniMax-M3](https://github.com/MiniMax-AI/MiniMax-M3/issues/25)
- [junhoyeo/tokscale](https://github.com/junhoyeo/tokscale)
- [JochenYang/minimax-status](https://github.com/JochenYang/minimax-status)
- [MiniMax Token Plan: Pricing, Credits, Quotas, and Best Use — minimax-ai.chat](https://minimax-ai.chat/docs/minimax-token-plan/)
- [MiniMax API Key: Base URLs, Regions & Authentication — minimax-ai.chat](https://minimax-ai.chat/docs/minimax-api-key-base-url/)
