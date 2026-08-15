# Changelog

All notable changes to OkTally are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Pick what each spot shows**: the notch's left wing, its right wing and the menu bar
  value are now three independent selectors in Preferences ▸ Menu bar. Each one is either
  "Automatic (most critical)" — the previous behaviour, still the default — or a specific
  provider window. Idle, each notch wing shows an identity chip plus that quota's
  remaining value (the minimal ticks are gone). A chosen quota that stops existing (a
  logged-out provider) quietly falls back to automatic.

- **Analytics tab redesigned as a dashboard**: hero block with today's usage and a
  sparkline, streak and daily-peak stat cards, a per-provider stacked bar chart
  (30 d / 90 d / 12 m), a provider list with balance/share sparklines, a share donut,
  and a strip of the tightest quotas across all providers.
- The usage heatmap now fills the available width and gained a legend.
- Alert thresholds now include **50 %** and **80 %** alongside the existing 70 / 90 / 100 %.
- **Notch panel** on the MacBook's built-in display: a black panel continuous with the
  notch, with rounded "wing" corners. Idle it hugs the notch with the brand symbol on
  one side and one minimal tick per tracked quota on the other; hovering springs it open
  into a dense row per quota (identity chip, bar, % remaining, reset countdown); clicking
  opens the full popover anchored under the notch. It exists only where there is a notch
  — on an external monitor, with the lid closed, or with the new **Notch panel** switch
  in Preferences ▸ Menu bar turned off, the window is not created at all and the menu bar
  carries on alone.

### Changed

- **The menu bar now carries a single number.** It used to print one segment per pinned
  window (`C100 X56 ▷56 G99 M84`), which was unreadable at 11 pt in the system bar. It
  now shows the official brand symbol plus the *tightest* quota only, and that number is
  neutral gray unless it is actually running out (amber, then magenta) — the rest moved
  to the notch panel and the popover.
- **Menu bar popover rebuilt around one hero and a dense provider list.** The tightest
  window across all providers gets the only display-size number, a danger-colored bar
  and its own tinted block; every other provider becomes a single compact row —
  identity chip, name, window, countdown, percentage — with its extra windows hanging
  underneath. The two-column grid of equal rings is gone, along with the ragged
  column bottoms, the duplicated numbers (a ring saying "26" beside "26% left"), the
  hero provider repeated as a card, the flat sparklines and the truncated labels.
  Provider color now paints the chip and the bar while green/amber/red is reserved for
  the numbers, and the 480 pt fold shows the hero plus eight providers instead of four.
- **System requirement is now macOS 26 (Tahoe).** Older macOS versions no longer
  receive updates — the bump unlocks Liquid Glass and the new Swift Charts APIs used
  throughout the redesign.
- **Preferences rebuilt** with native grouped forms and auto-save: fields commit on
  their own as you edit them, the "Save" buttons are gone, and each provider pane now
  has an explicit "Remove key" button instead of an implicit clear-on-blank.
- Popover, Overview, Provider detail, and Preferences now share the same design system:
  colors, typography, and card chrome all come from one place, and Liquid Glass is used
  for the popover chrome — header, today strip, and action bar. Glass stays off the
  dashboards and detail cards, where it would sit behind dense numbers and charts. The
  notch panel is the deliberate exception: solid black, no glass, so it reads as the
  notch itself.

### Fixed

- **Menu bar symbol was nearly invisible**: the label is a non-template `NSImage` (the
  only way coloured numbers survive), so macOS never adapted its colour — it was drawn in
  a fixed mid grey (~5.5:1 against the dark bar, where neighbouring system icons sit at
  ~17:1). The ink is now chosen per bar appearance (~15:1 both ways) and the symbol grew
  from 13 to 15 pt.

- **The app bundle now carries its own resource bundle.** `build_app.sh` never copied
  it, so translations and bundled assets only resolved through SwiftPM's fallback to an
  absolute path inside `.build` on the building machine — copying the `.app` elsewhere
  (or deleting `.build`) would have crashed it on the first translated string.

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
