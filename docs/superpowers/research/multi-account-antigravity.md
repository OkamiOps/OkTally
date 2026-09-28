---
title: "Multi-account — Antigravity: live verification gate (Task 5.0)"
tags: [oktally, antigravity, oauth, research]
created: 2026-09-28
---

# Antigravity app-owned Google login — live gate

Client under test: the Antigravity IDE's own installed-app client (`1071006060591-…`,
now in `Plugins/Antigravity/AntigravityOAuth.swift`). Nothing here was done with a real
login — every probe below is anonymous. No token, code or secret was printed.

## 1. Authorize endpoint accepts a loopback redirect — VERIFIED

`GET https://accounts.google.com/o/oauth2/v2/auth` with `response_type=code`, PKCE S256,
`access_type=offline`, `prompt=consent` and the scopes
`cloud-platform userinfo.email userinfo.profile cclog experimentsandconfigs`:

| redirect_uri | Google's answer |
|---|---|
| `http://localhost:51121/oauth-callback` | 302 → `accounts.google.com/v3/signin/identifier` (sign-in page) |
| `http://127.0.0.1:51121/oauth-callback` | 302 → `accounts.google.com/v3/signin/identifier` |
| `http://localhost:9999/oauth-callback` | 302 → `accounts.google.com/v3/signin/identifier` |
| `https://example.com/cb` (control) | 302 → `/signin/oauth/error`, `authError` = `redirect_uri_mismatch` |

The control proves the probe discriminates: Google validates the redirect before showing
the sign-in page, and it accepts **any loopback host/port** for this client (standard
behaviour for "Desktop app" clients, RFC 8252 §7.3). The scopes were not rejected at
this stage either.

**Deviation from the plan:** the plan pinned `redirectPort: 51121`. Because any loopback
port is accepted, OkTally uses an OS-assigned ephemeral port (`redirectPort: nil`,
`http://127.0.0.1:<port>/callback`, built by `BrowserOAuthFlow`). That avoids colliding
with the Antigravity IDE if it happens to be running its own login on 51121.

## 2. Token endpoint requires the client secret — VERIFIED

`POST https://oauth2.googleapis.com/token` with a bogus `code`:

- with `client_id` + `client_secret` → `400 invalid_grant` (client authenticated; only the
  code is bad);
- with `client_id` only → `400 invalid_request: client_secret is missing.`

Hence Task 5.1 (`OAuthConfig.clientSecret`, sent on exchange and refresh).

## 3. `refresh_token` + `id_token` on a real login — NOT VERIFIABLE HERE

Needs a real browser consent. Expected (standard Google behaviour with
`access_type=offline&prompt=consent` and `openid`-equivalent `userinfo.email` scope):
a `refresh_token` and an `id_token` carrying `email`. OkTally already captures the
`email` claim into `token.extra["email"]` (Task 2.2). If the `id_token` is absent, the
fallback `GET https://www.googleapis.com/oauth2/v2/userinfo` fills the e-mail.
Google does not rotate refresh tokens; `OAuthManager` keeps the previous one when the
refresh response omits it.

**Owner QA:** add an Antigravity account, confirm the pane shows the e-mail and that the
account keeps working after ~1 h (access-token expiry → silent refresh).

## Risk (unchanged from the plan)

Signing in to Google with the Antigravity client outside the IDE may violate
Antigravity's terms; there are community reports of Google flagging accounts. The add
pane shows this warning before the login button.
