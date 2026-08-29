<div align="center">

# OkTally

**Tous les quotas de vos abonnements IA dans la barre de menus macOS — avant de heurter le mur.**

[![Platform](https://img.shields.io/badge/plateforme-macOS%2026%2B-black?style=flat&logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-F05138?style=flat&logo=swift&logoColor=white)](https://swift.org)
[![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-0A84FF?style=flat)](https://developer.apple.com/xcode/swiftui/)
[![License](https://img.shields.io/badge/licence-MIT-blue?style=flat)](LICENSE)
[![Release](https://img.shields.io/github/v/release/OkamiOps/OkTally?include_prereleases&style=flat&color=orange)](https://github.com/OkamiOps/OkTally/releases)
[![Tests](https://img.shields.io/badge/tests-498%20r%C3%A9ussis-brightgreen?style=flat)](#d%C3%A9veloppement)
[![No telemetry](https://img.shields.io/badge/t%C3%A9l%C3%A9m%C3%A9trie-aucune-success?style=flat)](#confidentialit%C3%A9)

[English](README.md) | [Deutsch](README.de.md) | **Français** | [Português (BR)](README.pt-BR.md)

<br />

<img src="docs/assets/menubar.png" width="260" alt="Barre de menus OkTally avec plusieurs fenêtres de quota épinglées" />

<br />
<br />

<img src="docs/assets/popover.png" width="410" alt="Popover OkTally avec une prévision détaillée et des barres de rythme compactes pour chaque quota renouvelable par fournisseur et modèle" />

<sub>Toutes les captures utilisent des données de démonstration.</sub>

</div>

---

## Pourquoi OkTally

Les outils IA par abonnement ne préviennent pas. La fenêtre de 5 heures de Claude Code se ferme en plein refactoring, le plafond hebdomadaire tombe un jeudi, et le premier signe est le message *« vous avez atteint votre limite »*. Pendant ce temps, le quota disponible sur un autre abonnement dort, parce que rien ne vous dit qu'il est là.

OkTally est une **app native de barre de menus macOS** qui garde tous ces quotas visibles d'un coup d'œil — une bande colorée dans la barre, un popover avec la vue complète, une fenêtre d'ensemble avec analyse d'usage, et une notification **avant** l'épuisement, pas après.

## Fonctionnalités en un coup d'œil

| | Fonctionnalité | Ce qu'elle fait |
| :-: | --- | --- |
| 📌 | **Un seul chiffre dans la barre** | Épinglez autant de fenêtres que voulu ; la barre affiche le symbole de la marque et la fenêtre la *plus tendue*, colorée seulement quand ça serre |
| ↕️ | **Ordre des comptes** | Glissez la liste Contas dans Préférences ; Vue d'ensemble, popover, encoche et Analyse suivent |
| 🕳️ | **Panneau dans l'encoche** | Sur l'écran intégré du MacBook, un panneau noir collé à l'encoche : petits traits au repos, quotas complets au survol, popover au clic |
| 🎯 | **Popover goulot-d'abord** | Le quota le plus risqué reçoit une prévision détaillée ; les lignes fournisseur/modèle gardent chacune leurs barres de rythme compactes |
| 📈 | **Prévisions de rythme sur 24h** | Les limites hebdomadaires et mensuelles comparent le rythme récent au renouvellement et indiquent s'il faut ralentir, maintenir ou accélérer |
| 🪟 | **Fenêtre Vue d'ensemble** | Sidebar, ligne de KPI (fournisseurs · goulot · coût estimé), barres capsules par fenêtre, tendances 7 jours |
| 📊 | **Onglet Analyse** | Statistiques de tokens + heatmap façon GitHub, agrégées sur Codex, Claude Code et OpenCode — streaks, pic quotidien, aujourd'hui/hier/30 jours |
| 🔔 | **Alertes configurables** | Notifications macOS à 70/90/100 % (au choix) et seuil de solde bas en USD — une fois par franchissement |
| 💰 | **Coût estimé** | Tokens locaux × table de prix publique d'OpenRouter → « coût est. (30j) » sur la carte |
| 🧲 | **Détection zéro-config** | Cursor, GrokBot, GitHub Copilot et Antigravity utilisent les connexions déjà présentes sur votre Mac |
| 🔐 | **Secrets dans le trousseau** | Tokens OAuth et clés d'API jamais en clair ; tout tourne en local |

## La fenêtre Vue d'ensemble

<div align="center">
<img src="docs/assets/overview.png" width="640" alt="Fenêtre Vue d'ensemble avec KPI et cartes goulot-d'abord" />
</div>

Ouvrez-la depuis le popover (« Visão geral »). La sidebar liste chaque fournisseur avec un point de statut en direct ; la grille met la **fenêtre la plus contrainte de chaque fournisseur en premier** — bloc-héros teinté, barre capsule, compte à rebours — les autres fenêtres en lignes compactes avec un sparkline 7 jours dessous.

## L'onglet Analyse

<div align="center">
<img src="docs/assets/analytics.png" width="560" alt="Onglet Analyse avec chips de statistiques et heatmap d'usage" />
</div>

| Source | D'où viennent les chiffres | Notes |
| --- | --- | --- |
| **Codex** | API de statistiques du compte (ChatGPT) | Vrais tokens lifetime, tâche la plus longue, streaks |
| **Claude Code** | Transcriptions locales (`~/.claude/projects`) | Cache incrémental par fichier — premier scan un peu long, ensuite <0,1s |
| **OpenCode** | Base de sessions locale | Tokens par jour, cache/reasoning inclus |

L'onglet **Análise** somme toutes les sources dans une heatmap + chips (total, pic quotidien, streak actuel/record, aujourd'hui, hier, 30 jours), avec la ventilation par fournisseur en dessous. Les chiffres locaux sont des estimations honnêtes — pas une facture.

## Fournisseurs

| Fournisseur | Auth | Fenêtres de quota | Analyse | Coût |
| --- | --- | --- | :-: | :-: |
| **Claude Code** | OAuth, ou import en un clic de la session CLI | Session 5h + hebdo (+ Opus) | ✅ local | — |
| **Codex** | OAuth | Hebdo + fenêtres par fonctionnalité (ex. Spark) | ✅ compte | — |
| **GitHub Copilot** | **Zéro-config** — lit la session Copilot/gh CLI | Chat, complétions, premium | — | — |
| **Cursor** | **Zéro-config** — lit la session locale de Cursor | Solde + % du cycle | — | — |
| **GrokBot** | **Zéro-config** — réutilise la session locale de Cursor | Quota hebdomadaire GrokBot séparé | — | — |
| **Antigravity** | **Zéro-config** — lit la session de l'IDE Antigravity | Groupes Gemini et Claude/GPT, 5h + hebdo | — | — |
| **SuperGrok** | OAuth device code | Fenêtre hebdo | — | — |
| **OpenRouter** | Clé d'API | Solde de crédits | — | source des prix |
| **MiniMax** | Clé d'API (globale ou Chine) | 5h + hebdo | — | — |
| **OpenCode** | Clé d'API + base locale | 5h / hebdo / mensuel (estimé) | ✅ local | ✅ |
| **MiMo** | Session web intégrée (auto-récupérable) ou saisie manuelle | Plan mensuel | — | — |

**Tolérant au drift de schéma.** Des API majoritairement non documentées : OkTally ne décode que les champs consommés, les traite comme optionnels dès que le trafic réel a montré `null`, et conserve les **dernières bonnes données** à l'écran (« mis à jour il y a X ») quand un poll échoue.

## Installation

### DMG (recommandé)

Nécessite macOS 26 (Tahoe) ou ultérieur. Les versions antérieures de macOS ne sont plus prises en charge et ne recevront plus de mises à jour.

1. Téléchargez `OkTally-0.9.6.dmg` depuis la [page Releases](https://github.com/OkamiOps/OkTally/releases).
2. Ouvrez-le et glissez **OkTally** dans Applications.
3. L'app n'est pas notariée : au premier lancement, clic droit (Ctrl-clic) sur `OkTally.app` → **Ouvrir** → **Ouvrir**.

### Compiler depuis les sources

Nécessite les Xcode Command Line Tools avec Swift 6.2+ (le manifeste déclare `swift-tools-version: 6.2`).

```bash
git clone https://github.com/OkamiOps/OkTally.git
cd OkTally
bash Scripts/build_app.sh    # construit .build/OkTally.app
```

> **Recommandé :** créez un certificat auto-signé nommé `OkTally Dev` (Trousseau d'accès → Assistant de certification), sinon les signatures ad-hoc invalident les ACL du trousseau à chaque build.

## Premiers pas

1. Cliquez sur OkTally dans la barre de menus — le premier lancement affiche l'appel **connectez votre premier fournisseur**.
2. Ouvrez les **Préférences** et connectez chaque fournisseur — OAuth, clé d'API, ou rien du tout (Cursor/GrokBot/Copilot).
3. Glissez les comptes dans **Préférences → Contas** dans l'ordre voulu.
4. Dans le popover, épinglez les fenêtres importantes avec l'icône d'épingle.
5. Réglez les seuils d'alerte (70/90/100 % + solde bas) dans **Préférences → Général**.
6. Ouvrez **Visão geral** pour le tableau de bord complet et l'onglet **Análise**.

## Développement

```bash
swift test    # 498 tests unitaires
```

Chaque fournisseur est un plugin derrière un unique protocole `UsageProvider` et normalise ses données dans un modèle `QuotaShape`, si bien que l'UI n'a jamais à traiter un vendeur comme un cas particulier. Les documents de conception vivent dans `docs/superpowers/`.

## Confidentialité

Tout tourne en local sur votre Mac.

- Tokens OAuth et clés d'API dans le **trousseau macOS**, jamais en clair.
- Historique d'usage dans une base **SQLite** locale (rétention 30 jours).
- L'analyse Claude Code / OpenCode lit des fichiers **déjà sur votre machine** — rien n'est envoyé.
- Pas de télémétrie, pas d'analytics, pas de serveurs externes.

## Licence

[MIT](LICENSE) © OkamiOps
