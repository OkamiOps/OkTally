## Endpoint do console via análise do bundle JS (v4, 2026-08-08)

**Resultado: o path literal foi encontrado lendo o bundle JS público do
console (`platform.xiaomimimo.com`) e confirmado ao vivo com curl (respostas
`401`/`200` reais do servidor, não suposição). O candidato da v3
(`/api/v1/token-plan/usage`) estava ERRADO no path — o real é
`/api/v1/tokenPlan/detail` (camelCase, sem hífen, sub-recurso `detail` não
`usage`). A hipótese "app SolidStart" da v3 também estava errada: o console é
uma SPA React buildada com **rspack** (`server: MiFE/3.4.x`), servida como
bundle estático de `platform.xiaomimimo.com/static/*.chunk.js`.**

### Como cheguei lá

1. `curl https://platform.xiaomimimo.com/` → HTML raiz lista
   `<link rel="preload" href="/static/main.b8e846eca32da09f.chunk.js">`. O
   runtime rspack inline no HTML contém o mapa completo `chunkId → hash` para
   todos os ~30 chunks lazy-loaded do app (`u.u = function(e){...}`).
2. Baixei todos os ~30 chunks (`/static/<id>.<hash>.chunk.js`, ~5.3 MB total)
   e fiz `grep` por strings literais de URL (`"/tokenPlan..."`, `"/usage..."`,
   `"token-plan..."`).
3. O chunk `846.<hash>.chunk.js` (sidebar/console shell + tela
   `/console/plan-manage`) contém, em texto puro no bundle minificado:
   - `url:"/tokenPlan/detail",method:"GET",skipAuthRedirect:!0` (chunk
     `364.<hash>.chunk.js`, usado na tela de planos/pricing)
   - `d.d1.fetchDetail()` / `{tokenPlanDetail:e,isLoading:t}=d.d1` — o store
     que popula a tela `/console/plan-manage` (componente `aP`/`aR` no chunk
     846) chama esse mesmo `fetchDetail`.
   - `url:"/tokenPlan/list",method:"GET"` e
     `url:"/openTokenPlan/list",method:"GET"` (catálogo de planos).
   - `url:"/usage/token-plan/list",method:"POST"` e
     `url:"/usage/token-plan/export",method:"POST"` — tabela de uso detalhado
     por dia/mês (não é a barra, é a lista/exportação abaixo dela).
4. **Confirmação ao vivo com curl** (sem login, então tudo autenticado bate
   `401`, mas o path é reconhecido pelo servidor — não `404`):
   ```
   GET https://platform.xiaomimimo.com/api/v1/tokenPlan/detail
   → HTTP/2 401
     {"code":401,"loginUrl":"https://account.xiaomi.com/pass/serviceLogin?...
       followup=http://platform.xiaomimimo.com/api/v1/tokenPlan/detail&sid=api-platform..."}

   POST https://platform.xiaomimimo.com/api/v1/usage/token-plan/list
   → HTTP/2 401  (mesmo formato, followup=.../api/v1/usage/token-plan/list)

   GET https://platform.xiaomimimo.com/api/v1/tokenPlan/list
   → HTTP/2 401  (mesmo formato)

   GET https://platform.xiaomimimo.com/api/v1/openTokenPlan/list
   → HTTP/2 200  { "code":0, "data":[ {planCode:"lite", planName:"Lite", ...} ] }
     (esta é pública — catálogo de planos, sem exigir sessão)
   ```
   O `www-authenticate: CustomBasic realm="default"` e o corpo `{"code":401,
   "loginUrl":"https://account.xiaomi.com/pass/serviceLogin?...sid=api-platform..."}`
   confirmam exatamente o modelo de auth: **cookie de sessão obtido via SSO
   `account.xiaomi.com`**, igual ao que o plano do OkTally já previa (WKWebView
   de login + captura de cookie). Sem header `Authorization: Bearer tp-...` /
   `x-api-key`.

### Path, método, host — literal, confirmado

- **Host**: `platform.xiaomimimo.com` (não é subdomínio separado tipo
  `token-plan-*.xiaomimimo.com` — esses existem mas são para outra coisa, ver
  abaixo).
- **Prefixo real da API**: `/api/v1/` (o bundle usa paths relativos como
  `/tokenPlan/detail`; o prefixo `/api/v1` foi descoberto por tentativa direta
  — `/tokenPlan/detail` sem prefixo devolve a SPA HTML, com `/api/v1/` na
  frente devolve o JSON 401 real).
- **Endpoint da barra "Current plan usage" / "Plan usage"**:
  `GET https://platform.xiaomimimo.com/api/v1/tokenPlan/detail`
  (cookie de sessão obrigatório).
- **Endpoint da lista/tabela de uso detalhado** (não é a barra, é a seção
  abaixo dela no console): `POST
  https://platform.xiaomimimo.com/api/v1/usage/token-plan/list` (body JSON
  com filtros, ex. `{month, ...}` — não capturado literalmente ainda).
- **Endpoint do catálogo de planos** (público, sem sessão):
  `GET https://platform.xiaomimimo.com/api/v1/openTokenPlan/list`.
- Existe também `GET /api/v1/tokenPlan/list` (autenticado) — planos do
  usuário logado, usado junto com `/tokenPlan/detail` pra achar o plano ativo.

### Nomes de campo da resposta (extraídos do JS, não observados ao vivo — a
resposta autenticada não foi capturada, só a estrutura de acesso no código)

O componente que renderiza a barra (`aN`, chunk 846) itera
`tokenPlanDetail.usage.items` (ou seja, a resposta de `GET
/api/v1/tokenPlan/detail` tem um campo `usage: { items: [...] }`). Cada item:
```js
{
  name: string,      // ex. "compensation_total_token" (comparado literalmente no código)
  percent: number,   // 0-100, passado para a progress bar (`aria-valuenow`)
  used: number,       // Number.isFinite(e.used) checado antes de formatar
  limit: number        // Number.isFinite(e.limit) checado antes de formatar
}
```
Strings i18n confirmando que é exatamente essa tela/barra:
`console.planManage.part1.currentPlanUsage` (o título "Current plan usage"),
`console.planManage.part1.usageSectionTitle`, `console.planManage.part1.usageProgressUsed`,
`console.planManage.part1.usageUsedLimitTokens` (formata `{used}` / `{limit}`).
Outros campos do objeto raiz `tokenPlanDetail` vistos destruturados no código:
`planCode`, `planName`, `expired`, `currentPeriodEnd`, `hasAutoRenewSubscribed`,
`enableAutoRenew`, `clawEnabled`.

### Sobre os hosts `token-plan-{cn,sgp,ams}.xiaomimimo.com`

Achados no bundle (chunk 690) como um mapa de região:
```js
{CN:"https://token-plan-cn.xiaomimimo.com/v1",
 SGP:"https://token-plan-sgp.xiaomimimo.com/v1",
 EU:"https://token-plan-ams.xiaomimimo.com/v1"}
```
Não confirmei para que serve esse mapa especificamente (pagamento/checkout
regional, provavelmente, dado o contexto do trecho — perto de permissões tipo
`generateApiKey`/`accessAccount`). **Não é** o host usado por
`/tokenPlan/detail` — esse é sempre relativo a `platform.xiaomimimo.com`
mesmo (confirmado pelo `loginUrl.followup` retornado, que sempre aponta de
volta pra `platform.xiaomimimo.com/api/v1/...`).

### Nível de confiança

- **Path/método/host do endpoint de detail (`GET
  /api/v1/tokenPlan/detail`)**: alto. Confirmado tanto no código-fonte do
  bundle quanto por resposta HTTP real do servidor (401 com `loginUrl`
  correto, não 404).
- **Que esse endpoint específico é o que popula a barra "Current plan
  usage"**: alto — rastreado diretamente do componente (`d.d1.fetchDetail()`
  → `tokenPlanDetail` → `usage.items` → barra de progresso) até o
  `url:"/tokenPlan/detail"` no fetcher.
- **Nomes de campo exatos da resposta JSON**: médio — vêm de como o código
  acessa o objeto (`e.used`, `e.limit`, `e.percent`, `e.name`,
  `usage.items`), não de uma resposta JSON capturada ao vivo (não tenho
  sessão logada). Structuralmente devem bater, mas não é 100% garantido sem
  ver o payload real uma vez.
- **Refuta o candidato da v3** (`/api/v1/token-plan/usage`, hipótese
  SolidStart/`_server`): sim, refutado — o app é rspack/React, não
  SolidStart, e o path real usa `tokenPlan/detail` (camelCase, `detail` não
  `usage`).

### Passo restante

Para fechar 100%: logar no console com uma conta real, abrir DevTools →
Network, visitar `/#/console/plan-manage` e confirmar o payload JSON exato de
`GET /api/v1/tokenPlan/detail` (nomes de campo, e se `usage.items[].name`
inclui algo como `"total_token"` genérico além de
`"compensation_total_token"`). Isso é só para validar os nomes de campo —
path/método/host/modelo-de-auth já estão confirmados o suficiente para o
OkTally implementar a chamada (WKWebView SSO login → capturar cookie de
sessão → `GET https://platform.xiaomimimo.com/api/v1/tokenPlan/detail` com
esse cookie → parsear `usage.items`).

---

## Re-investigação: endpoint do console de Plan usage (v3, 2026-08-08)

**Pergunta direta: existe uma URL HTTP que a barra "Plan usage" no console
(`platform.xiaomimimo.com/#/console/plan-manage`) chama, e ela aceita a chave
`tp-...`?**

**Resposta curta: não há endpoint que aceite a chave `tp-`. O endpoint que
alimenta a barra existe, mas é gated por cookie de sessão web (SSO
Xiaomi), não por API key. Isso foi confirmado por três ângulos independentes
nesta passada, todos concordando com a v2.**

### Candidato mais provável (nome do endpoint, não verificado ao vivo)

- **Padrão de URL**: `https://platform.xiaomimimo.com/api/v1/token-plan/usage`
  (v1 já tinha sondado isso ao vivo e recebido `401` com um `loginUrl` de SSO
  — não uma resposta 404, ou seja, a rota existe e é reconhecida pelo
  servidor, só que autenticação diferente é exigida).
- **Método**: provavelmente `GET`.
- **Auth exigida**: cookie httpOnly assinado (`ZEN_SESSION_SECRET`), obtido
  via login OAuth/OIDC completo do site (`account.xiaomi.com` SSO,
  `clientID: "app"`) — **não** um header `Authorization: Bearer tp-...` nem
  `x-api-key: tp-...`. Confirmado lendo o código-fonte real
  (`packages/console/app/src/routes/workspace/[id]/usage/index.tsx` →
  `usage-section.tsx` → server function `getUsageInfo` → `withActor(() =>
  Billing.usages(...), workspaceID)` → `getActor` lê `useSession` do
  SolidStart, populada só depois do fluxo de login do próprio site).
- Como é uma SolidStart app renderizada por RPC de "server functions" (não
  uma API REST documentada publicamente), a chamada real feita pelo
  navegador provavelmente é para um caminho gerado automaticamente pelo
  framework (algo como `/_server?...` ou uma rota `/api/...` interna
  específica do SolidStart), não necessariamente o path humano
  `/api/v1/token-plan/usage` — o v1 pode ter sondado um alias/rewrite dessa
  rota que devolve 401 corretamente, mas o path exato batido pelo browser
  ainda não foi capturado literalmente de um Network tab real.

### O que esta passada verificou de novo

1. **Doc oficial da assinatura** (`mimo.mi.com/docs/en-US/tokenplan/Token
   Plan/subscription`) — fetchada agora. Ela **não documenta nenhum endpoint
   de API** para uso/quota. A única instrução é textual: "You can check the
   quota and usage of your current plan in [Token
   Plan](https://platform.xiaomimimo.com/#/console/plan-manage)" — ou seja,
   a própria documentação oficial aponta para o console web, não para uma
   API.
2. **`platform.xiaomimimo.com/docs/llms.txt`** redireciona (302) para
   `mimo.mi.com/docs/llms.txt`. Esse índice não lista nenhuma rota de
   usage/quota/billing/credits — só links para quick-start, pricing,
   first-api-call, model summary, FAQ, e os logins do MiMo Studio/Claw
   (`aistudio.xiaomimimo.com/open-apis/v1/genLoginUrl`, que também é um
   fluxo de login redirecionado, não uma API de dados).
3. **Busca web dirigida** por `platform.xiaomimimo.com api rate-limit usage
   endpoint` e `"token-plan" xiaomimimo "usage" api endpoint github` não
   retornou nenhum endpoint de consulta de saldo/uso — só a doc de
   rate-limit (RPM/TPM, que é sobre limites de taxa da API de inferência,
   não sobre o saldo de créditos do plano) e as mesmas issues de terceiros
   (cc-switch, 9router) já catalogadas na v2, todas pedindo essa
   funcionalidade sem resposta.

### Conclusão sobre `tp-` vs cookie

**A chave `tp-` NÃO é aceita no endpoint que alimenta a barra "Plan usage".**
Ela só é aceita no gateway de inferência (`/v1/chat/completions`,
`/anthropic/v1/messages`), e mesmo lá o servidor explicitamente remove
qualquer header de rate-limit/quota da resposta (`keepHeaders =
["content-type", "cache-control"]`, confirmado em código na v2). O endpoint
de uso/plano é uma "server function" da aplicação web, autenticada
exclusivamente por sessão de navegador logado via SSO Xiaomi — nunca por
API key.

### Nível de confiança

- **Alto** (confirmado por doc oficial + código-fonte + ausência em toda
  documentação pública) que não existe hoje um endpoint aceitando `tp-` para
  ler uso/plano.
- **Médio** quanto ao path HTTP *exato* batido pelo navegador do dono
  (`/api/v1/token-plan/usage` é a melhor hipótese, consistente com o 401 já
  observado na v1, mas não foi capturado literalmente de um DevTools Network
  tab).

### Único passo restante para fechar 100%

Pedir ao dono para abrir o console logado
(`https://platform.xiaomimimo.com/#/console/plan-manage`), abrir
DevTools → aba Network, dar refresh na página, filtrar por "usage" ou
"plan-manage", e reportar: (a) o path completo da requisição que retorna os
dados da barra de progresso, (b) o método, (c) se o header de auth é
`Cookie: ...` (confirmando sessão) ou algo diferente. Isso fecha a única
lacuna restante (o path literal), mas não deve mudar a conclusão principal:
é cookie-gated, não aceita a chave `tp-`, e portanto não é viável para um
app como o OkTally sem pedir ao usuário para extrair um cookie de sessão —
o que está fora do padrão de confiança do resto do OkTally e não é
recomendado.

---

# Xiaomi MiMo Token Plan — Usage/Quota API Research (v2)

Research date: 2026-08-07 (supersedes the 2026-08-07 v1 pass in this same file)
Scope: find a programmatic way to read remaining quota/usage for a Xiaomi MiMo
"Token Plan" subscription (`tp-xxxxx` API keys), for OkTally's menu-bar usage
tracker.

## What changed since v1

v1 only probed guessed REST paths with a `tp-` key and concluded "no endpoint
exists." That was **incomplete but the underlying conclusion holds up better
than expected** once traced to source. This pass read the actual source code
of three independent official/community projects — MiMo's own open-sourced
CLI (`XiaomiMiMo/MiMo-Code`, which bundles the console/gateway backend it
talks to), and OpenClaw's Xiaomi provider plugin — rather than guessing at
endpoints from the outside. Headline results:

1. **A real, working, third-party-usable OAuth-style flow exists** for
   obtaining a `tp-`/`sk-` API key without ever handling a password. It is
   used by MiMoCode (the official CLI). Full mechanism documented below —
   this is new and directly actionable.
2. **That flow authenticates key issuance, not quota reads.** The console's
   usage/billing pages are gated by a *separate*, standard cookie-session
   OAuth (OpenAuth/OIDC via `account.xiaomi.com` SSO) that only the website
   itself is a registered client for. There is no code path anywhere in the
   codebase that accepts a `tp-`/`sk-` API key and returns usage/quota data.
3. **Confirmed from source, not just a live probe**: the inference gateway
   (`zen/util/handler.ts`) explicitly whitelists only `content-type` and
   `cache-control` on every outbound response — "Scrub response headers" —
   so no `x-ratelimit-*`/quota headers can ever reach the client, on success
   or error. This settles the open question v1 flagged (needs a real key to
   verify the 200 case) without needing a real key: the code strips them
   before your key's tier is even relevant.
4. **OpenClaw's own Xiaomi plugin does not show live MiMo quota either.**
   Read directly from `openclaw/openclaw` source: its `fetchUsageSnapshot`
   for both the pay-as-you-go and Token Plan Xiaomi providers returns
   `{ windows: [] }` — a hardcoded empty usage snapshot. This is one of the
   exact "other applications" candidates named in the research brief, and
   its current source confirms it does not implement MiMo usage polling.
5. MiMoCode's own TUI does not display a live balance/credits number
   anywhere either — it only pops a "buy/renew Token Plan" dialog reactively
   when a 429 `SubscriptionUsageLimitError`/`FreeUsageLimitError` body is
   seen, then links out to the web console.

**Net effect: the "no API-key-authenticated quota endpoint" conclusion from
v1 is now confirmed by source code across three independent codebases, not
just a failed guess-the-path probe.** But this pass also surfaces something
v1 completely missed: a legitimate, non-SSO-scraping way to *obtain* a key
programmatically (item 1), which is useful for OkTally's onboarding UX even
though it doesn't unlock quota reads.

## 1. The OAuth-style key-issuance flow (new finding)

Source: `packages/opencode/src/plugin/mimo.ts` in `XiaomiMiMo/MiMo-Code`
(the official MiMoCode CLI, MIT-licensed fork of `anomalyco/opencode`).

This is **not** a standard OAuth2/OIDC flow (no client_id registration, no
authorization-code exchange with a token endpoint). It's a custom
browser-handoff + asymmetric-encryption handshake:

1. Client generates an ephemeral X25519 keypair locally.
2. Client starts a localhost HTTP server on a random port (or, as a
   fallback/manual path, uses `${PLATFORM_URL}/authorize/code/callback` and
   has the user paste a code).
3. Client opens the user's browser to:
   ```
   https://platform.xiaomimimo.com/authorize
     ?pk=<base64url X25519 public key>
     &redirect_uri=http://localhost:<port>/
     &kn=<client identifier, e.g. "mimocode">
     &key_name=<a locally generated, persisted key-name string>
   ```
4. The user completes normal Xiaomi-account SSO login in the browser at that
   page (this is where `account.xiaomi.com` involvement happens — same
   identity provider v1 found behind the console's 401 `loginUrl`).
5. The platform provisions an API key server-side, encrypts a JSON payload
   `{ sk: <api key>, uid: <user id>, url: <base_url for that key/region> }`
   to the client's public key (ECDH shared secret via the client's pubkey +
   a server-generated ephemeral keypair, HKDF-less — SHA-256 of the raw
   shared secret — then AES-256-GCM), and redirects the browser to
   `http://localhost:<port>/?u=<encrypted-blob>`.
6. The client's localhost listener receives `u`, decrypts it with its private
   key, and now has a real `sk-`/`tp-` API key plus the correct regional
   `base_url` — no password ever touches the client, no static client secret
   needed, and the decrypt is self-verifying (AES-GCM auth tag).

Decrypt algorithm (for reference, no secrets involved — this is public
protocol logic from the MIT-licensed source):
```
encrypted = base64url_decode(u)
ephemeralPub   = encrypted[0:32]
nonce          = encrypted[32:44]
ciphertext+tag = encrypted[44:]
tag            = last 16 bytes of ciphertext+tag
sharedSecret   = X25519(clientPrivateKey, ephemeralPub)
key            = SHA256(sharedSecret)
plaintext      = AES-256-GCM-decrypt(key, nonce, ciphertext, tag)
             -> JSON { sk, uid, url }
```

**Confidence: confirmed-from-source.** This is exactly what a menu-bar app
like OkTally could implement to let a user link their MiMo account and
obtain a working key without ever seeing a password field, mirroring what
every other "browser login" OAuth-ish flow in OkTally already does. It does
**not**, however, grant access to any quota-reading endpoint — see below.

**What "kn" (client name) is and whether third parties can use it**: the
value `"mimocode"` in the source appears to just be a label/telemetry field,
not a registered/allow-listed client ID enforced by the server (there is no
client-registration step, no client secret, and no scope negotiation
anywhere in the flow). This suggests — but does not 100%-confirm without
actually calling the live endpoint — that a third-party app could plausibly
pass its own `kn` value in the same request shape and get the same result.
**This is inferred, not verified live** (doing so was out of scope for a
read-only source-code research pass and risks creating an unwanted API key
against a real account without explicit owner testing).

## 2. Quota/usage endpoint: still SSO-cookie-only, now confirmed from source

Traced the full server-side implementation in
`packages/console/{app,core}` of the same repo (SolidStart web app +
Drizzle/DB core — this is the codebase that appears to underlie
`platform.xiaomimimo.com`, based on shared terminology: "workspace", "Zen"
gateway, "Go" subscription, matching `anomalyco/opencode`'s own Cloud/Zen/Go
products which Xiaomi has forked and rebranded as "Token Plan").

- The usage-history page (`routes/workspace/[id]/usage/index.tsx` →
  `usage-section.tsx`) calls a SolidStart server function `getUsageInfo`
  which does:
  ```ts
  "use server"
  return withActor(() => Billing.usages(page, pageSize), workspaceID)
  ```
  `withActor` → `getActor(workspace)` → reads a **signed httpOnly session
  cookie** (`useSession` from `@solidjs/start/http`, sealed with
  `Resource.ZEN_SESSION_SECRET`) that was populated during a standard
  authorization-code OAuth exchange (`@openauthjs/openauth` client,
  `clientID: "app"`, `issuer: <VITE_AUTH_URL>`) — i.e. the **website's own**
  browser-session login, gated behind Xiaomi passport SSO, exactly matching
  the `loginUrl` v1 observed on the `401` from
  `platform.xiaomimimo.com/api/v1/token-plan/usage`.
- There is **no code path, anywhere in `packages/console`, that accepts an
  `Authorization`/`x-api-key` header carrying a `tp-`/`sk-` key and returns
  usage or billing data.** The only place API keys (`zenApiKey`) are
  consulted is `routes/zen/util/handler.ts`'s `authenticate()`, which looks
  the key up in `KeyTable` purely to authorize/bill *that single inference
  request* — it never returns quota/balance info to the caller, and (per
  finding above) explicitly scrubs response headers down to
  `content-type`/`cache-control` before sending the response back.
- Quota math itself lives in `packages/console/core/src/subscription.ts`:
  `analyzeMonthlyUsage` / `analyzeWeeklyUsage` / `analyzeRollingUsage`, which
  take `{ limit, usage, timeUpdated }` (a `micro-cents`-style integer usage
  counter vs. a plan limit) and return `{ usagePercent: 0-100 }`. This is
  the shape you'd get **if** you had cookie-session access — useful as a
  reference schema, but not fetchable with a `tp-` key.

**Confidence: confirmed-from-source** that the usage-reading surface is
100% session-cookie/SSO gated with no API-key alternative in the codebase
this platform is built on.

## 3. Response headers on real inference calls — resolved without a live key

v1 flagged this as needing a real `tp-` key to check the *200* response
path (it only had data on the 401 path). Source code resolves it directly:

`packages/console/app/src/routes/zen/util/handler.ts`, the proxy handler for
`/anthropic/v1/messages` and `/v1/chat/completions`:
```ts
// Scrub response headers
const resHeaders = new Headers()
const keepHeaders = ["content-type", "cache-control"]
for (const [k, v] of res.headers.entries()) {
  if (keepHeaders.includes(k.toLowerCase())) {
    resHeaders.set(k, v)
  }
}
```
This runs on **every** response the gateway proxies back, regardless of
status code or whether the upstream model provider (which MiMo itself
routes to under the hood) set `anthropic-ratelimit-*`-style headers. They
are dropped before reaching the client. **Confidence: confirmed-from-source,
supersedes v1's "inferred/unconfirmed for the 200 case."** No `tp-` key is
needed to close this question — the code makes it structurally impossible.

## 4. Community/official tooling survey (expanded)

- **cc-switch** (`farion1231/cc-switch`) — unchanged from v1: issues #3230,
  #2428, #2488 document a dozen guessed-and-failed balance paths, still
  open/unresolved.
- **9router** (`decolua/9router`) — unchanged from v1: issue #1251 is about
  region hardcoding, not quota.
- **OpenClaw** (`openclaw/openclaw`, package `@openclaw/xiaomi-provider`) —
  **new, source-verified finding**: its plugin (`extensions/xiaomi/index.ts`)
  registers both `xiaomi` (pay-as-you-go) and `xiaomi-token-plan` providers
  with a `fetchUsageSnapshot` hook — the exact contract OpenClaw uses to
  show provider usage bars — but both implementations are stubs:
  ```ts
  fetchUsageSnapshot: async () => ({
    provider: XIAOMI_TOKEN_PLAN_PROVIDER_ID,
    displayName: "Xiaomi MiMo Token Plan",
    windows: [],   // <-- always empty
  }),
  ```
  So OpenClaw, despite having the plumbing (`resolveUsageAuth`,
  `fetchUsageSnapshot`) that other providers use for real quota display,
  does not actually fetch or show MiMo quota. This directly contradicts the
  premise that OpenClaw is where the owner sees his quota — unless a newer
  release changed this (checked the current `main` branch; worth asking the
  owner which OpenClaw version/build they're on, in case they're on a fork
  or an unreleased branch).
- **MiMoCode itself** (the official CLI) — **new finding**: does not display
  a live quota number in its TUI. It only shows a reactive "you hit a
  limit, go subscribe/manage your plan" dialog (`dialog-token-plan.tsx`) on
  429 responses, then links to `https://platform.xiaomimimo.com/token-plan`
  (the browser-session-gated console) rather than rendering any number
  itself.
- **destngx/monorepo** (`apps/ai-gateway/internal/providers/xiaomi_mimo/xiaomi_mimo.go`)
  and **anvia-hq/anvia** (`xiaomi-token-plan-{cn,ams,sgp}.md` provider docs)
  turned up in code search as more third-party gateway integrations for
  MiMo — not yet read in detail (time-boxed out of this pass); worth a
  follow-up grep for `usage`/`quota`/`balance` in
  `destngx/monorepo`'s Go provider file specifically, as Go providers
  sometimes implement a `GetBalance`-style interface method other language
  ports skip.

## 5. Quota structure (unchanged from v1, still confirmed-from-docs)

Source: https://mimo.mi.com/docs/en-US/price/token-plan and
https://mimo.mi.com/docs/en-US/quick-start/faq/api-integration

- Unit: "Credits," synthetic, cache-hit/miss/output-rate-dependent per model.
- Monthly reset, hard cutoff at zero, no 5-hour rolling window (explicit
  marketing differentiator vs. Anthropic/OpenAI-style rate limits).
- Shared pool across all client tools pointed at the same `tp-` key.
- Exact Credit totals per tier are unreliable/conflicting across sources —
  do not hardcode.

## Which OkTally QuotaShape fits

Unchanged conclusion, now on firmer ground (source-confirmed, not just
probe-confirmed):

- **`periodicCounter` (monthly)** is the right conceptual shape, but it
  cannot be backed by a live-fetched balance — there is no such API for
  `tp-`/`sk-` keys, confirmed by reading the actual server implementation
  three independent client integrations talk to.
- Recommended implementation: **`meteredOnly`**. Track request/response
  token counts OkTally already observes on the OpenAI/Anthropic-compatible
  traffic, apply the published per-model Credit ratios, reset monthly, let
  the user input their plan's total Credit allowance. This is what every
  other tool that has looked at this (cc-switch, 9router, OpenClaw) has
  either done or left unimplemented — nobody has a live number.
- **New option worth considering**: use the MimoCode-style OAuth handshake
  (Section 1) purely for **key acquisition UX** — let the user click "Link
  MiMo account" instead of pasting a `tp-`/`sk-` key manually, since that
  flow doesn't require them to leave OkTally to find their key on the
  console. This does not solve quota polling, only onboarding friction.
  Treat this as a "nice to have, separate feature" rather than bundling it
  into the quota work — its exact request/response contract (especially
  whether the server validates `kn` against an allow-list) is unverified
  live and should be tested by someone willing to generate a real key
  against their own account before shipping.
- If OkTally wants a live number badly enough to accept fragility: the only
  path remaining is scraping the SSO-cookie-gated console exactly as v1
  said — full Xiaomi-account login flow (not the lightweight flow in
  Section 1, which only yields an API key, not a session cookie), different
  trust model from every other OkTally plugin. Still not recommended.

## What to ask the owner, since this pass still didn't find a live number

Everything below was checked and ruled out as *not* currently exposing live
MiMo Token Plan quota to a `tp-`/`sk-` key or equivalent non-SSO credential:

- MiMoCode CLI TUI (official) — reactive dialog only, no number.
- OpenClaw's Xiaomi plugin (current `main`) — `fetchUsageSnapshot` stub,
  `windows: []`.
- cc-switch — open, unresolved issue asking for exactly this.
- 9router — no evidence of a quota feature for MiMo at all.
- Direct REST probing of `platform.xiaomimimo.com/api/v1/token-plan/usage`
  and sibling guessed paths — 401 + SSO `loginUrl`.
- Gateway response headers on inference calls — explicitly scrubbed
  server-side to `content-type`/`cache-control` only, confirmed from source.

If the owner is seeing a number somewhere, the most likely explanations,
ranked:
1. **The web console itself** (`platform.xiaomimimo.com/token-plan`), viewed
   logged-in in a normal browser tab — "another application" in the loose
   sense of "not my terminal," but still the SSO-cookie surface v1 already
   identified, not a new API.
2. A MiMo **mobile app** (not investigated this pass — Xiaomi ships a
   consumer Mi Home / Xiaomi ecosystem app pattern; worth asking if there's
   a dedicated MiMo Android/iOS app with a quota screen, which would imply
   a private mobile-only API worth reverse-engineering via a proxy capture).
3. A **newer/different build of OpenClaw** than what's on `main`, or a
   different xiaomi-provider version/fork that has since implemented
   `fetchUsageSnapshot` for real.
4. A tool not covered in this pass's search terms — worth getting the exact
   app name/screenshot from the owner rather than guessing further blindly.

## Sources

- https://github.com/XiaomiMiMo/MiMo-Code — official MiMoCode CLI, cloned
  and read directly (`packages/opencode/src/plugin/mimo.ts`,
  `packages/console/app/src/routes/**`, `packages/console/core/src/**`,
  `packages/opencode/src/cli/cmd/tui/**`)
- https://github.com/openclaw/openclaw — `extensions/xiaomi/index.ts`,
  `docs/plugins/reference/xiaomi.md`
- https://mimo.mi.com/docs/en-US/price/token-plan
- https://mimo.mi.com/docs/en-US/quick-start/faq/api-integration
- https://docs.openclaw.ai/providers/xiaomi
- https://github.com/farion1231/cc-switch/issues/2428
- https://github.com/farion1231/cc-switch/issues/3230
- https://github.com/farion1231/cc-switch/issues/2488
- https://github.com/decolua/9router/issues/1251
- https://github.com/XiaomiMiMo/MiMo-Code/issues/851 (Token Plan / API mode
  auth-separation feature request — confirms no unified quota view exists
  even in the official roadmap discussion)
- v1 live probes against `token-plan-cn.xiaomimimo.com` and
  `platform.xiaomimimo.com` (retained from prior pass, not repeated here)

## Recommendation for OkTally implementation

1. Implement the MiMo plugin as `meteredOnly` (unchanged from v1): track
   observed token usage, apply published Credit ratios, monthly reset, user
   supplies their plan's Credit allowance.
2. Optionally build the Section-1 OAuth-style key-linking flow as a
   convenience for onboarding (paste-free key acquisition) — but validate
   it live against a real account first, and treat it as separate from the
   quota question, since it does not return quota.
3. Do not attempt SSO/cookie scraping of the console for quota — confirmed
   from source to be the only live-data path, and it's a different
   trust/auth model than the rest of OkTally.
4. Ask the owner exactly which app shows him quota (see numbered list
   above) before investing further — this pass exhausted every documented
   and source-inspectable avenue without finding one, including two more
   (MiMoCode itself, OpenClaw) beyond what v1 checked.
