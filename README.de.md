<div align="center">

# OkTally

**Jedes Kontingent deiner KI-Coding-Abos, direkt in der macOS-Menüleiste — bevor du an die Wand läufst.**

[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-black?style=flat)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange?style=flat)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-blue?style=flat)](LICENSE)
[![Release](https://img.shields.io/github/v/release/OkamiOps/OkTally?style=flat)](https://github.com/OkamiOps/OkTally/releases)
[![Tests](https://img.shields.io/badge/tests-180%20passing-brightgreen?style=flat)](#entwicklung)

[English](README.md) | **Deutsch** | [Français](README.fr.md) | [Português (BR)](README.pt-BR.md)

<br />

<img src="docs/assets/menubar.png" width="260" alt="OkTally menu bar label showing multiple pinned quota windows" />

<br />
<br />

<img src="docs/assets/popover.png" width="400" alt="OkTally popover dashboard with hero gauge and provider cards" />

<sub>Screenshots zeigen Demodaten.</sub>

</div>

---

## Warum OkTally

KI-Abo-Tools warnen dich nicht. Das 5-Stunden-Fenster von Claude Code schließt sich mitten im Refactoring, das wöchentliche Limit fällt zufällig auf einen Donnerstag, und das erste Anzeichen für Ärger ist die Meldung „du hast dein Limit erreicht". Und das Kontingent, das auf einem anderen Abo noch ungenutzt herumliegt, bleibt derweil ungenutzt, weil dir niemand sagt, dass es da ist.

OkTally ist eine native macOS-Menüleisten-App, die jedes dieser Kontingente auf einen Blick sichtbar hält — ein farbiger Streifen in der Menüleiste, ein Popover mit dem vollständigen Überblick und eine Benachrichtigung, bevor dir das Kontingent ausgeht, statt danach.

## Funktionen

**Farbige Menüleiste, so viele Pins wie du willst.** Pinne beliebig viele Kontingentfenster an. Jedes wird als Anbieter-Symbol in der Identitätsfarbe des Anbieters dargestellt, gefolgt vom verbleibenden Prozentsatz, dessen Farbe sich nach der Nähe zum Limit richtet — grün über 30 %, gelb bei 30 % oder darunter, rot bei 10 % oder darunter:

```
C 78 · X 86 · ▹ 26
```

Pinnst du nichts, zeigt OkTally automatisch das Fenster, das seinem Limit am nächsten ist. Das Label wird als echtes (nicht-template) Bild gezeichnet, sodass die Farben in der Menüleiste erhalten bleiben, statt auf Monochrom reduziert zu werden.

**Ein Popover, das die Frage sofort beantwortet.** Eine Hauptanzeige rückt das Fenster in den Fokus, das seinem Limit am nächsten ist, mit einem Countdown bis zum Reset. Darunter ein zweispaltiges Raster mit Anbieter-Karten: eine Ringanzeige pro Anbieter, dann eine Zeile pro Fenster mit verbleibendem Prozentsatz und Reset-Zeit. Anbieter mit Fehlern oder ohne Konfiguration klappen zu unauffälligen Zeilen am unteren Rand zusammen, außer Sichtweite.

**Einstellungen, die sich wie die Systemeinstellungen anfühlen.** Eine Seitenleiste listet jeden Anbieter mit einem Live-Statuspunkt, ein Bereich pro Anbieter, dazu ein Allgemein-Bereich zum Umsortieren und Entfernen von Menüleisten-Pins.

**Benachrichtigungen vor der Wand.** Eine kantengetriggerte Warn-Engine löst eine macOS-Benachrichtigung genau in dem Moment aus, in dem eine Schwelle überschritten wird — einmal pro Überschreitung, nicht einmal pro Abfrage.

## Anbieter

| Anbieter | Authentifizierung | Was du siehst |
| --- | --- | --- |
| **Claude Code** | OAuth oder Ein-Klick-Import deines bestehenden Claude-Code-CLI-Logins | 5h- + wöchentliche Fenster |
| **Codex** | OAuth | Wöchentliche Fenster |
| **SuperGrok** | OAuth-Gerätecode | Plan-Fenster |
| **Cursor** | Automatisch — liest deine lokale Cursor-App-Sitzung | Guthaben + Nutzung % |
| **OpenRouter** | API-Schlüssel | Guthabenstand |
| **MiniMax** | API-Schlüssel (global oder China-Region) | 5h- + wöchentliche Fenster |
| **OpenCode** | API-Schlüssel | Plan-Nutzung |
| **MiMo** | In-App-Websitzung (selbstheilend) oder manuelle Schätzung | Monatlicher Plan |

**Selbstheilende MiMo-Sitzung.** Die Xiaomi-Konsolen-Sitzung lebt in einer persistenten In-App-Webansicht. Läuft das kurzlebige STS-Cookie ab, lädt OkTally die Konsole transparent neu und versucht es erneut — du musst dich nur dann erneut anmelden, wenn die zugrunde liegende Xiaomi-SSO-Sitzung tatsächlich abgelaufen ist.

## Installation

### DMG (empfohlen)

1. Lade `OkTally-1.0.0.dmg` von der [Releases-Seite](https://github.com/OkamiOps/OkTally/releases) herunter.
2. Öffne die Datei und ziehe **OkTally** in den Ordner „Programme".
3. Die App ist nicht notarisiert: Beim ersten Start Rechtsklick (Ctrl-Klick) auf `OkTally.app` → **Öffnen** → **Öffnen**.

### Aus dem Quellcode bauen

Erfordert die Xcode Command Line Tools mit Swift 5.9 oder neuer.

```bash
git clone https://github.com/OkamiOps/OkTally.git
cd OkTally
bash Scripts/build_app.sh    # baut .build/OkTally.app
```

Optionale Extras:

```bash
bash Scripts/install_launch_agent.sh   # OkTally beim Login starten
bash Scripts/make_dmg.sh               # eine Drag-and-drop-DMG paketieren
```

> **Empfehlung beim Bauen aus dem Quellcode:** Erstelle ein selbstsigniertes Code-Signing-Zertifikat namens `OkTally Dev` (Schlüsselbundverwaltung → Zertifikatsassistent → Zertifikat erstellen… → Selbstsigniertes Stammzertifikat, Code-Signierung). Ad-hoc-Signaturen ändern bei jedem Build die Identität der App, was Keychain-ACLs ungültig macht und dich zwingt, dich erneut anzumelden. `build_app.sh` erkennt das Zertifikat automatisch, wenn es existiert.

## Erste Schritte

1. Klicke auf das OkTally-Symbol in der Menüleiste und öffne dann **Einstellungen**.
2. Verbinde jeden Anbieter, den du nutzt — OAuth-Login, API-Schlüssel oder den MiMo-Web-Login.
3. Pinne im Popover die Fenster, die dich interessieren, mit dem Pin-Symbol.
4. Sortiere oder entferne Pins unter „Preferências → Geral" (Einstellungen → Allgemein).

## Entwicklung

```bash
swift test    # 180 Unit-Tests
```

Jeder Anbieter ist ein Plugin, das einem einzigen `UsageProvider`-Protokoll entspricht, und normalisiert seine Daten in ein gemeinsames `QuotaShape`-Modell — rollierendes Fenster, periodischer Zähler, Guthabenstand, gemessen oder geschätzt —, sodass die Oberfläche niemals anbieterspezifische Sonderfälle behandeln muss. Ein Scheduler fragt Anbieter in anbieterspezifischen Intervallen ab, und die Präsentationslogik liegt in reinen Modellen wie `MenuBarLabelModel`, was das Rendering von Label und Dashboard vollständig testbar macht, ohne dass die App laufen muss. Design-Dokumente liegen in `docs/superpowers/`.

## Datenschutz

Alles läuft lokal auf deinem Mac.

- OAuth-Tokens und API-Schlüssel werden im **macOS-Schlüsselbund** gespeichert, niemals im Klartext.
- Der Nutzungsverlauf liegt in einer lokalen **SQLite**-Datenbank.
- Keine Telemetrie, keine Analytics, keine externen Server — OkTally kommuniziert ausschließlich mit den eigenen APIs der Anbieter.

## Lizenz

[MIT](LICENSE) © OkamiOps
</content>
</invoke>
