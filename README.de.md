<div align="center">

# OkTally

**Jedes KI-Abo-Kontingent in der macOS-Menüleiste — bevor du gegen die Wand läufst.**

[![Platform](https://img.shields.io/badge/Plattform-macOS%2026%2B-black?style=flat&logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-F05138?style=flat&logo=swift&logoColor=white)](https://swift.org)
[![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-0A84FF?style=flat)](https://developer.apple.com/xcode/swiftui/)
[![License](https://img.shields.io/badge/Lizenz-MIT-blue?style=flat)](LICENSE)
[![Release](https://img.shields.io/github/v/release/OkamiOps/OkTally?include_prereleases&style=flat&color=orange)](https://github.com/OkamiOps/OkTally/releases)
[![Tests](https://img.shields.io/badge/Tests-478%20bestanden-brightgreen?style=flat)](#entwicklung)
[![No telemetry](https://img.shields.io/badge/Telemetrie-keine-success?style=flat)](#datenschutz)

[English](README.md) | **Deutsch** | [Français](README.fr.md) | [Português (BR)](README.pt-BR.md)

<br />

<img src="docs/assets/menubar.png" width="260" alt="OkTally-Menüleiste mit mehreren angehefteten Kontingentfenstern" />

<br />
<br />

<img src="docs/assets/popover.png" width="410" alt="OkTally-Popover mit erweiterter Kontingentprognose und kompakten Pace-Balken für jedes erneuerbare Provider- und Modelllimit" />

<sub>Alle Screenshots zeigen Demo-Daten.</sub>

</div>

---

## Warum OkTally

Abo-basierte KI-Tools warnen nicht. Das 5-Stunden-Fenster von Claude Code schließt mitten im Refactoring, das Wochenlimit fällt auf einen Donnerstag, und das erste Anzeichen ist die Meldung *„Limit erreicht"*. Währenddessen liegt Kontingent auf einem anderen Abo ungenutzt herum, weil nichts dir sagt, dass es da ist.

OkTally ist eine **native macOS-Menüleisten-App**, die all diese Kontingente auf einen Blick sichtbar hält — ein farbiger Streifen in der Menüleiste, ein Popover mit dem Gesamtbild, ein Übersichtsfenster mit Nutzungsanalyse und eine Benachrichtigung, **bevor** es leer ist statt danach.

## Funktionen auf einen Blick

| | Funktion | Was sie tut |
| :-: | --- | --- |
| 📌 | **Eine Zahl in der Leiste** | Beliebig viele Fenster anheften; die Menüleiste zeigt das Markensymbol und das *knappste* Fenster, gefärbt nur wenn es eng wird |
| 🕳️ | **Notch-Panel** | Auf dem eingebauten MacBook-Display: ein schwarzes Panel am Notch — schmale Striche im Ruhezustand, volle Kontingentzeilen beim Hover, Popover per Klick |
| 🎯 | **Engpass-zuerst-Popover** | Das riskanteste Limit erhält eine erweiterte Prognose; dichte Provider-/Modellzeilen behalten darunter ihre eigenen kompakten Pace-Balken |
| 📈 | **24h-Pace-Prognosen** | Wochen- und Monatslimits vergleichen den jüngsten Verbrauch mit der Erneuerung und empfehlen langsamer, gleich schnell oder schneller zu nutzen |
| 🪟 | **Übersichtsfenster** | Sidebar, KPI-Zeile (Provider · Engpass · geschätzte Kosten), Kapselbalken pro Fenster, 7-Tage-Trends |
| 📊 | **Analyse-Tab** | Token-Statistiken + GitHub-artige Heatmap, aggregiert über Codex, Claude Code und OpenCode — Streaks, Tagesspitze, heute/gestern/30 Tage |
| 🔔 | **Konfigurierbare Alarme** | macOS-Benachrichtigungen bei 70/90/100 % (deine Wahl) plus USD-Schwelle für niedriges Guthaben — einmal pro Überschreitung |
| 💰 | **Kostenschätzung** | Lokale Token-Zahlen × öffentliche OpenRouter-Preistabelle → „geschätzte Kosten (30d)" auf der Karte |
| 🧲 | **Zero-Config-Erkennung** | Cursor, GrokBot, GitHub Copilot und Antigravity werden aus vorhandenen Logins erkannt |
| 🔐 | **Geheimnisse nur im Schlüsselbund** | OAuth-Tokens und API-Keys nie im Klartext; alles läuft lokal |

## Das Übersichtsfenster

<div align="center">
<img src="docs/assets/overview.png" width="640" alt="Übersichtsfenster mit KPI-Karten und Engpass-zuerst-Provider-Karten" />
</div>

Über das Popover öffnen („Visão geral"). Die Sidebar listet jeden Provider mit Live-Status-Punkt; das Raster stellt das **knappste Fenster jedes Providers zuerst** dar — getönter Hero-Block, Kapselbalken, Reset-Countdown — die übrigen Fenster als kompakte Zeilen mit 7-Tage-Sparkline darunter.

## Der Analyse-Tab

<div align="center">
<img src="docs/assets/analytics.png" width="560" alt="Analyse-Tab mit Statistik-Chips und Nutzungs-Heatmap" />
</div>

| Quelle | Woher die Zahlen kommen | Hinweise |
| --- | --- | --- |
| **Codex** | Konto-Statistik-API (ChatGPT) | Echte Lifetime-Tokens, längste Aufgabe, Streaks |
| **Claude Code** | Lokale Transkripte (`~/.claude/projects`) | Inkrementeller Datei-Cache — erster Scan dauert etwas, danach <0,1s |
| **OpenCode** | Lokale Sitzungsdatenbank | Tokens pro Tag inkl. Cache/Reasoning |

Der **Analyse**-Tab summiert alle Quellen in eine Heatmap + Chips (Gesamt, Tagesspitze, aktueller/längster Streak, heute, gestern, 30 Tage), mit Aufschlüsselung pro Provider. Lokale Zahlen sind ehrliche Schätzungen — keine Rechnung.

## Provider

| Provider | Auth | Kontingentfenster | Analyse | Kosten |
| --- | --- | --- | :-: | :-: |
| **Claude Code** | OAuth oder Ein-Klick-Import des CLI-Logins | 5h-Session + wöchentlich (+ Opus) | ✅ lokal | — |
| **Codex** | OAuth | Wöchentlich + Feature-Fenster (z. B. Spark) | ✅ Konto | — |
| **GitHub Copilot** | **Zero-Config** — liest Copilot/gh-CLI-Login | Chat, Completions, Premium | — | — |
| **Cursor** | **Zero-Config** — liest lokale Cursor-Session | Guthaben + Zyklus-% | — | — |
| **GrokBot** | **Zero-Config** — nutzt die lokale Cursor-Session mit | Separates wöchentliches GrokBot-Kontingent | — | — |
| **Antigravity** | **Zero-Config** — liest den Antigravity-IDE-Login | Gemini- und Claude/GPT-Gruppen, 5h + wöchentlich | — | — |
| **SuperGrok** | OAuth Device Code | Wochenfenster | — | — |
| **OpenRouter** | API-Key | Guthaben | — | Preisquelle |
| **MiniMax** | API-Key (global oder China) | 5h + wöchentlich | — | — |
| **OpenCode** | API-Key + lokale DB | 5h / wöchentlich / monatlich (geschätzt) | ✅ lokal | ✅ |
| **MiMo** | In-App-Websession (selbstheilend) oder manuell | Monatsplan | — | — |

**Schema-Drift-tolerant.** Größtenteils undokumentierte APIs: OkTally dekodiert nur konsumierte Felder, behandelt sie als optional, wo Live-Traffic `null` gezeigt hat, und zeigt bei fehlgeschlagenem Poll die **letzten guten Daten** (mit „aktualisiert vor X").

## Installation

### DMG (empfohlen)

Erfordert macOS 26 (Tahoe) oder neuer. Ältere macOS-Versionen werden nicht mehr unterstützt und erhalten keine Updates mehr.

1. `OkTally-0.9.5.dmg` von der [Releases-Seite](https://github.com/OkamiOps/OkTally/releases) laden.
2. Öffnen und **OkTally** nach Programme ziehen.
3. Die App ist nicht notarisiert: beim ersten Start Rechtsklick (Ctrl-Klick) auf `OkTally.app` → **Öffnen** → **Öffnen**.

### Aus dem Quellcode

Benötigt Xcode Command Line Tools mit Swift 6.2+ (das Manifest verlangt `swift-tools-version: 6.2`).

```bash
git clone https://github.com/OkamiOps/OkTally.git
cd OkTally
bash Scripts/build_app.sh    # baut .build/OkTally.app
```

> **Empfohlen:** ein selbstsigniertes Zertifikat namens `OkTally Dev` anlegen (Schlüsselbundverwaltung → Zertifikatsassistent), sonst invalidieren Ad-hoc-Signaturen bei jedem Build die Keychain-ACLs.

## Erste Schritte

1. OkTally in der Menüleiste anklicken — der erste Start zeigt einen **Provider-verbinden**-Aufruf.
2. In den **Einstellungen** jeden genutzten Provider verbinden — OAuth, API-Key oder gar nichts (Cursor/GrokBot/Copilot).
3. Im Popover die wichtigen Fenster mit dem Pin-Symbol anheften.
4. Alarmschwellen (70/90/100 % + Guthaben) unter **Einstellungen → Allgemein** anpassen.
5. **Visão geral** für das volle Dashboard und den **Análise**-Tab öffnen.

## Entwicklung

```bash
swift test    # 478 Unit-Tests
```

Jeder Provider ist ein Plugin hinter einem einzigen `UsageProvider`-Protokoll und normalisiert in ein `QuotaShape`-Modell, damit die UI nie einen Anbieter als Sonderfall behandeln muss. Designdokumente liegen in `docs/superpowers/`.

## Datenschutz

Alles läuft lokal auf deinem Mac.

- OAuth-Tokens und API-Keys liegen im **macOS-Schlüsselbund**, nie im Klartext.
- Die Nutzungshistorie liegt in einer lokalen **SQLite**-Datenbank (30 Tage Aufbewahrung).
- Claude-Code-/OpenCode-Analyse liest Dateien, **die schon auf deinem Rechner sind** — nichts wird hochgeladen.
- Keine Telemetrie, keine Analytics, keine externen Server.

## Lizenz

[MIT](LICENSE) © OkamiOps
