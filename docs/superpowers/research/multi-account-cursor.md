---
title: "Multi-account — Cursor: live verification gate (Task 6.0)"
tags: [oktally, cursor, auth, research]
created: 2026-09-28
---

# Cursor deep-login — live gate

Probes run on 2026-09-28. Anonymous probes used a random `uuid`/verifier and bogus tokens.
Authenticated probes used the **legacy** Cursor session read-only from the IDE's
`state.vscdb` (`?mode=ro`); no token, `sub` or full e-mail was printed or stored, and no
call that could mutate the IDE's session was made.

## 1. Poll endpoint shape — PARTIALLY VERIFIED

- `GET https://api2.cursor.sh/auth/poll?uuid=<random>&verifier=<random>` →
  `404 text/plain "Not found"` — the "not done yet" answer the plan expected.
- `GET https://cursor.com/loginDeepControl?challenge=…&uuid=…&mode=login&redirectTarget=cli`
  → `200` (page served).
- The `200` success body can only be seen after a real browser login. Implemented per
  the community implementations cited in the plan: JSON with `accessToken` and
  `refreshToken` (extra fields ignored). **Owner QA must confirm.**

## 2. Session token works on both usage endpoints — VERIFIED

With the IDE's session token (`Authorization: Bearer`):

- `POST aiserver.v1.DashboardService/GetCurrentPeriodUsage` → `200`
  (`planUsage`, `billingCycleStart/End`, …) — what `CursorUsageProvider` reads.
- `POST aiserver.v1.DashboardService/GetSandUsageStatus` → `200`
  (`usagePercent`, `nextResetTimestampUtc`, `grokPlanLabel`, …) — what the GrokBot twin reads.

The token is a JWT: `type=session`, `scope=openid profile email offline_access`,
`aud=https://cursor.com`, `sub=google-oauth2|…`, lifetime `exp − time` = **60 days**.
`cursorAuth/accessToken == cursorAuth/refreshToken` (confirms the plan's premise).
A deep-login session is the same kind of token, so the same endpoints apply.

## 3. Refresh path — NOT VERIFIED → fallback implemented

- `POST api2.cursor.sh/auth/exchange_user_api_key` (Bearer bogus) →
  `401 {"code":"error","message":"Invalid User API Key"}`. This endpoint exchanges a
  *user API key*, not a session refresh token — not a refresh path for us.
- `POST api2.cursor.sh/oauth/token` `{"grant_type":"refresh_token", …}` with a bogus
  refresh token → `200 {"access_token":"","id_token":"","shouldLogout":true}`, with or
  without a `client_id` (the response does not discriminate the client).
- A real refresh was **deliberately not attempted** with the IDE's token: it is the
  owner's live IDE session and a server-side rotation could log the IDE out.

**Implemented fallback (plan):** no silent refresh. The stored session JWT is used until
its `exp`; once expired, the provider throws `OAuthError.noRefreshToken`, which
`ProviderErrorPresentation` classifies as `needsReauth` ("Reconnect" → sign in again).
With a 60-day session this is a re-login roughly every two months per extra account.
A future improvement could try `oauth/token` and treat `shouldLogout:true` / empty
`access_token` as `needsReauth`, once verified with a throwaway session.

## 4. E-mail source — VERIFIED

- `POST https://api2.cursor.sh/aiserver.v1.AuthService/GetEmail` with `Bearer <token>`
  and body `{}` → `200 {"email": "…"}`. **Used by OkTally** (same host and auth as the
  usage calls; no cookie juggling).
- Also works: `GET https://cursor.com/api/auth/me` with cookie
  `WorkosCursorSessionToken=<sub after "|">%3A%3A<token>` → `200` with `email`, `name`, …
- Bonus: `GET api2.cursor.sh/auth/full_stripe_profile` → `200` with `membershipType`.

Because the e-mail resolves, the "nickname required" fallback is not needed; the
nickname prompt still appears if `GetEmail` fails at enrollment time.

## Owner QA (needs a real login)

1. Preferences → "+" → Cursor → "Sign in in the browser"; log into a DIFFERENT Cursor
   account; the pane should flip to connected within a few seconds and show its e-mail.
2. The new Cursor card and its GrokBot twin show that account's numbers, not the IDE's.
3. Switch accounts inside the Cursor IDE: the extra account must keep working.
4. Re-adding the same Cursor account is refused as a duplicate.
