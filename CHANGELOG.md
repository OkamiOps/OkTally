# Changelog

All notable changes to OkTally are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Alterado

- **Requisito de sistema agora é macOS 26 (Tahoe).** Versões anteriores do macOS não
  recebem mais atualizações — a mudança libera Liquid Glass e as APIs novas de Swift
  Charts usadas no redesign da interface.

## [0.9.1-beta] — 2026-08-12

### Added

- **Plan badges** (Pro/Free/Business/Enterprise) on provider cards, overview cards and detail pages — populated by Codex (`plan_type`) and GitHub Copilot (SKU-based tier rules).
- **Update check**: OkTally checks GitHub Releases once a day and shows an orange "vX available" chip in the popover header linking to the release page. (Chosen over Sparkle deliberately: without notarization, auto-install would hit Gatekeeper anyway.)
- **English localization** (164 strings): the UI now follows the system language — English or Portuguese; dates and month labels localize too.
- **Antigravity provider** (zero-config): reads the Antigravity IDE login from its local state database, refreshes the Google OAuth token, and reports the Gemini and Claude/GPT quota groups (5h + weekly windows) from the Cloud Code quota-summary API.
- Plan badges extended to **Claude** (OAuth profile → Pro/Max/Team/Enterprise) and **Cursor** (membership type from the local session — Pro/Free/Pro Student).

## [0.9.0-beta] — 2026-08-12

### Changed

- **Stable code signing.** `build_app.sh` now signs with the first available stable identity — a self-signed `OkTally Dev` certificate, falling back to any **Apple Development** certificate on the machine — instead of requiring `OkTally Dev` specifically. This DMG is signed with a stable identity, so **Keychain logins now survive app updates**.

### Upgrade note

- Coming from 0.8.0-beta (which was ad-hoc signed), macOS treats this build as a new app the first time it touches the Keychain: reconnect OAuth providers and re-save API keys once, clicking **Always Allow** on Keychain prompts. From this version on, logins persist across updates.

## [0.8.0-beta] — 2026-08-12

First public release. Everything below is new.

### Providers

- **Claude Code** — OAuth (PKCE) or one-click import of the existing Claude Code CLI login; 5h session, weekly and Opus-weekly windows.
- **Codex** — OAuth; weekly + per-feature windows labelled by their real duration (e.g. `GPT-5.3-Codex-Spark (Semanal)`).
- **GitHub Copilot** — zero-config: reads the Copilot IDE plugin or `gh` CLI login already on the Mac; chat / completions / premium windows with reset dates.
- **Cursor** — zero-config: reads the local Cursor app session; balance + billing-cycle usage.
- **SuperGrok** — OAuth device-code flow; weekly window.
- **OpenRouter** — API key; credit balance.
- **MiniMax** — API key with global/China region toggle; 5h + weekly windows, worst-model-wins.
- **OpenCode** — API key + local database; estimated 5h / weekly / monthly windows against plan budgets.
- **MiMo** — persistent in-app Xiaomi web session with automatic recovery on expired STS cookies, or manual allowance entry.

### Menu bar & popover

- Colored, multi-pin menu bar label (`C 78 · X 86`) rendered as a real image so colors survive; automatic worst-window mode when nothing is pinned; pins persist and are reorderable.
- Popover with bottleneck hero gauge, two-column provider cards with ring gauges, friendly Portuguese window labels, per-card 24h sparkline, quiet problem rows with **Reconectar/Configurar** actions that deep-link the right Preferences pane.
- First-launch onboarding empty state with a call-to-action instead of eight gray rows.
- Smooth 0.3s animations on rings, bars and sparklines; monospaced digits everywhere numbers change.

### Overview window & analytics

- **Visão geral** window: sidebar navigation, KPI row (providers · bottleneck · estimated cost), bottleneck-first provider cards with capsule bars, per-provider detail pages with 7-day trends.
- **Análise** tab aggregating token usage across sources into stat chips (lifetime, daily peak, longest task, streaks, today/yesterday/30 days) and a GitHub-style contributions heatmap with per-day tooltips.
- Analytics sources: Codex account stats (ChatGPT profile API), Claude Code local transcripts (incremental per-file cache; input+output+cache tokens), OpenCode local session database.

### Alerts & history

- Edge-triggered alert engine with **user-configurable thresholds** (70/90/100% checkboxes + low-balance USD field) and a master notifications toggle.
- Usage history persisted to SQLite with a 30-day retention policy; sparklines and trends read from it.
- Last-known-good data survives failed polls and app relaunches, with an "updated X ago" staleness caption.

### Cost estimates

- Pricing engine wired to OpenRouter's public model price table (1h cache) with suffix-based model-id fallback; OpenCode reports per-model token totals, rendered as "Custo est. (30d)" on cards.

### Reliability & privacy

- Schema-drift-tolerant decoding for undocumented provider APIs (only consumed fields, optional wherever live traffic showed null).
- Secrets in the macOS Keychain only (with silent migration from legacy plaintext locations); usage data stays local; no telemetry.
- Tri-state provider status (connected / needs reauth / not configured) so an expired login is never painted as "broken" or hidden as "fine".

[0.9.1-beta]: https://github.com/OkamiOps/OkTally/releases/tag/v0.9.1-beta
[0.9.0-beta]: https://github.com/OkamiOps/OkTally/releases/tag/v0.9.0-beta
[0.8.0-beta]: https://github.com/OkamiOps/OkTally/releases/tag/v0.8.0-beta
