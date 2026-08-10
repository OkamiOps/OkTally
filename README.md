<div align="center">

# OkTally

**Every AI coding subscription quota, in your macOS menu bar — before you hit the wall.**

[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-black?style=flat)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange?style=flat)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-blue?style=flat)](LICENSE)
[![Release](https://img.shields.io/github/v/release/OkamiOps/OkTally?style=flat)](https://github.com/OkamiOps/OkTally/releases)
[![Tests](https://img.shields.io/badge/tests-180%20passing-brightgreen?style=flat)](#development)

**English** | [Deutsch](README.de.md) | [Français](README.fr.md) | [Português (BR)](README.pt-BR.md)

<br />

<img src="docs/assets/menubar.png" width="260" alt="OkTally menu bar label showing multiple pinned quota windows" />

<br />
<br />

<img src="docs/assets/popover.png" width="400" alt="OkTally popover dashboard with hero gauge and provider cards" />

<sub>Screenshots use demo data.</sub>

</div>

---

## Why OkTally

Subscription AI tools don't warn you. Claude Code's 5-hour window closes mid-refactor, the weekly cap lands on a Thursday, and the first sign of trouble is a "you've reached your limit" message. Meanwhile the quota you *do* have sitting on another subscription goes unused, because nothing tells you it's there.

OkTally is a native macOS menu bar app that keeps every one of those quotas visible at a glance — one colored strip in the menu bar, one popover with the full picture, and a notification before you run out instead of after.

## Features

**Colored menu bar, as many pins as you want.** Pin any number of quota windows. Each renders as a provider glyph in the provider's identity color, followed by the percentage remaining, colored by how close it is to the limit — green above 30%, amber at or below 30%, red at or below 10%:

```
C 78 · X 86 · ▹ 26
```

Pin nothing and OkTally automatically shows whichever window is closest to its limit. The label is drawn as a real (non-template) image, so the colors survive in the menu bar instead of being flattened to monochrome.

**A popover that answers the question first.** A hero gauge spotlights the window closest to running out, with a countdown to its reset. Below it, a two-column grid of provider cards: a ring gauge per provider, then one row per window with percentage remaining and reset time. Providers that errored or aren't configured yet collapse into quiet rows at the bottom, out of the way.

**Preferences that feel like System Settings.** A sidebar lists every provider with a live status dot, one pane per provider, plus a General pane for reordering and removing menu bar pins.

**Notifications before the wall.** An edge-triggered alert engine fires a macOS notification the moment a threshold is crossed — once per crossing, not once per poll.

## Providers

| Provider | Auth | What you see |
| --- | --- | --- |
| **Claude Code** | OAuth, or one-click import of your existing Claude Code CLI login | 5h + weekly windows |
| **Codex** | OAuth | Weekly windows |
| **SuperGrok** | OAuth device code | Plan windows |
| **Cursor** | Automatic — reads your local Cursor app session | Balance + usage % |
| **OpenRouter** | API key | Credit balance |
| **MiniMax** | API key (global or China region) | 5h + weekly windows |
| **OpenCode** | API key | Plan usage |
| **MiMo** | In-app web session (self-recovering) or manual estimate | Monthly plan |

**Self-recovering MiMo session.** The Xiaomi console session lives in a persistent in-app web view. When its short-lived STS cookie expires, OkTally transparently reloads the console and retries — you only log in again if the underlying Xiaomi SSO session actually dies.

## Install

### DMG (recommended)

1. Download `OkTally-1.0.0.dmg` from the [Releases page](https://github.com/OkamiOps/OkTally/releases).
2. Open it and drag **OkTally** to Applications.
3. The app is not notarized: on first launch, right-click (Ctrl-click) `OkTally.app` → **Open** → **Open**.

### Build from source

Requires Xcode Command Line Tools with Swift 5.9 or newer.

```bash
git clone https://github.com/OkamiOps/OkTally.git
cd OkTally
bash Scripts/build_app.sh    # builds .build/OkTally.app
```

Optional extras:

```bash
bash Scripts/install_launch_agent.sh   # start OkTally at login
bash Scripts/make_dmg.sh               # package a drag-to-install DMG
```

> **Recommended when building from source:** create a self-signed code-signing certificate named `OkTally Dev` (Keychain Access → Certificate Assistant → Create a Certificate… → Self-Signed Root, Code Signing). Ad-hoc signatures change the app's identity on every build, which invalidates Keychain ACLs and forces you to log in again. `build_app.sh` picks the certificate up automatically when it exists.

## Getting started

1. Click the OkTally item in the menu bar, then open **Preferences**.
2. Connect each provider you use — OAuth login, API key, or the MiMo web login.
3. Back in the popover, pin the windows you care about with the pin icon.
4. Reorder or remove pins in **Preferences → General**.

## Development

```bash
swift test    # 180 unit tests
```

Each provider is a plugin conforming to a single `UsageProvider` protocol and normalizes its data into one `QuotaShape` model — rolling window, periodic counter, credit balance, metered, or estimated — so the UI never has to special-case a vendor. A scheduler polls providers on per-provider intervals, and presentation logic lives in pure models such as `MenuBarLabelModel`, which keeps the label and dashboard rendering fully testable without a running app. Design documents live in `docs/superpowers/`.

## Privacy

Everything runs locally on your Mac.

- OAuth tokens and API keys are stored in the **macOS Keychain**, never in plaintext.
- Usage history lives in a local **SQLite** database.
- No telemetry, no analytics, no external servers — OkTally talks only to the providers' own APIs.

## License

[MIT](LICENSE) © OkamiOps
