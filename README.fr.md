<div align="center">

# OkTally

**Tous les quotas de tes abonnements IA de code, dans ta barre de menu macOS — avant que tu ne heurtes le mur.**

[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-black?style=flat)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange?style=flat)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-blue?style=flat)](LICENSE)
[![Release](https://img.shields.io/github/v/release/OkamiOps/OkTally?style=flat)](https://github.com/OkamiOps/OkTally/releases)
[![Tests](https://img.shields.io/badge/tests-180%20passing-brightgreen?style=flat)](#développement)

[English](README.md) | [Deutsch](README.de.md) | **Français** | [Português (BR)](README.pt-BR.md)

<br />

<img src="docs/assets/menubar.png" width="260" alt="OkTally menu bar label showing multiple pinned quota windows" />

<br />
<br />

<img src="docs/assets/popover.png" width="400" alt="OkTally popover dashboard with hero gauge and provider cards" />

<sub>Les captures d'écran utilisent des données de démonstration.</sub>

</div>

---

## Pourquoi OkTally

Les outils IA par abonnement ne te préviennent pas. La fenêtre de 5 heures de Claude Code se ferme en plein refactoring, le plafond hebdomadaire tombe un jeudi, et le premier signe de problème est un message « tu as atteint ta limite ». Pendant ce temps, le quota que tu *as* réellement sur un autre abonnement reste inutilisé, parce que rien ne t'indique qu'il est là.

OkTally est une application native de barre de menu macOS qui garde chacun de ces quotas visible en un coup d'œil — une bande colorée dans la barre de menu, un popover avec la vue d'ensemble, et une notification avant d'être à sec plutôt qu'après.

## Fonctionnalités

**Une barre de menu colorée, autant d'épingles que tu veux.** Épingle autant de fenêtres de quota que tu le souhaites. Chacune s'affiche comme un glyphe de fournisseur dans la couleur d'identité du fournisseur, suivi du pourcentage restant, coloré selon la proximité de la limite — vert au-dessus de 30 %, ambre à 30 % ou moins, rouge à 10 % ou moins :

```
C 78 · X 86 · ▹ 26
```

Si tu n'épingles rien, OkTally affiche automatiquement la fenêtre la plus proche de sa limite. L'étiquette est dessinée comme une vraie image (non template), pour que les couleurs survivent dans la barre de menu au lieu d'être aplaties en monochrome.

**Un popover qui répond à la question en premier.** Une jauge principale met en avant la fenêtre la plus proche d'être épuisée, avec un compte à rebours jusqu'à sa réinitialisation. En dessous, une grille à deux colonnes de cartes fournisseur : une jauge en anneau par fournisseur, puis une ligne par fenêtre avec le pourcentage restant et l'heure de réinitialisation. Les fournisseurs en erreur ou pas encore configurés se replient en lignes discrètes en bas, hors du chemin.

**Des préférences qui ressemblent aux Réglages Système.** Une barre latérale liste chaque fournisseur avec un indicateur d'état en direct, un panneau par fournisseur, plus un panneau Général pour réordonner et retirer les épingles de la barre de menu.

**Des notifications avant le mur.** Un moteur d'alerte à déclenchement sur front montant envoie une notification macOS dès qu'un seuil est franchi — une fois par franchissement, pas une fois par sondage.

## Fournisseurs

| Fournisseur | Authentification | Ce que tu vois |
| --- | --- | --- |
| **Claude Code** | OAuth, ou import en un clic de ta session CLI Claude Code existante | Fenêtres 5h + hebdomadaire |
| **Codex** | OAuth | Fenêtres hebdomadaires |
| **SuperGrok** | OAuth par code d'appareil | Fenêtres de plan |
| **Cursor** | Automatique — lit ta session locale de l'app Cursor | Solde + % d'utilisation |
| **OpenRouter** | Clé API | Solde de crédits |
| **MiniMax** | Clé API (région globale ou Chine) | Fenêtres 5h + hebdomadaire |
| **OpenCode** | Clé API | Utilisation du plan |
| **MiMo** | Session web intégrée (auto-réparatrice) ou estimation manuelle | Plan mensuel |

**Session MiMo auto-réparatrice.** La session de la console Xiaomi vit dans une vue web intégrée persistante. Quand son cookie STS de courte durée expire, OkTally recharge la console de façon transparente et réessaie — tu ne dois te reconnecter que si la session SSO Xiaomi sous-jacente est réellement morte.

## Installation

### DMG (recommandé)

1. Télécharge `OkTally-1.0.0.dmg` depuis la page [Releases](https://github.com/OkamiOps/OkTally/releases).
2. Ouvre-le et glisse **OkTally** vers Applications.
3. L'application n'est pas notariée : au premier lancement, fais un clic droit (Ctrl-clic) sur `OkTally.app` → **Ouvrir** → **Ouvrir**.

### Compiler depuis les sources

Nécessite les Xcode Command Line Tools avec Swift 5.9 ou plus récent.

```bash
git clone https://github.com/OkamiOps/OkTally.git
cd OkTally
bash Scripts/build_app.sh    # compile .build/OkTally.app
```

Extras optionnels :

```bash
bash Scripts/install_launch_agent.sh   # démarrer OkTally à l'ouverture de session
bash Scripts/make_dmg.sh               # empaqueter un DMG glisser-déposer
```

> **Recommandé lors d'une compilation depuis les sources :** crée un certificat de signature de code auto-signé nommé `OkTally Dev` (Trousseau d'accès → Assistant certificat → Créer un certificat… → Racine auto-signée, Signature de code). Les signatures ad hoc changent l'identité de l'application à chaque compilation, ce qui invalide les ACL du Trousseau et t'oblige à te reconnecter. `build_app.sh` récupère automatiquement le certificat quand il existe.

## Prise en main

1. Clique sur l'icône OkTally dans la barre de menu, puis ouvre **Préférences**.
2. Connecte chaque fournisseur que tu utilises — connexion OAuth, clé API, ou connexion web MiMo.
3. De retour dans le popover, épingle les fenêtres qui t'intéressent avec l'icône d'épingle.
4. Réordonne ou retire les épingles dans **Préférences → Général** (Preferências → Geral).

## Développement

```bash
swift test    # 180 tests unitaires
```

Chaque fournisseur est un plugin conforme à un unique protocole `UsageProvider` et normalise ses données dans un seul modèle `QuotaShape` — fenêtre glissante, compteur périodique, solde de crédits, mesuré, ou estimé — de sorte que l'UI n'a jamais besoin de traiter un fournisseur comme un cas particulier. Un ordonnanceur sonde les fournisseurs à des intervalles propres à chacun, et la logique de présentation vit dans des modèles purs comme `MenuBarLabelModel`, ce qui garde le rendu de l'étiquette et du tableau de bord entièrement testable sans application en cours d'exécution. Les documents de conception vivent dans `docs/superpowers/`.

## Confidentialité

Tout tourne localement sur ton Mac.

- Les jetons OAuth et les clés API sont stockés dans le **Trousseau macOS**, jamais en clair.
- L'historique d'utilisation vit dans une base de données **SQLite** locale.
- Aucune télémétrie, aucune analytique, aucun serveur externe — OkTally ne parle qu'aux API propres des fournisseurs.

## Licence

[MIT](LICENSE) © OkamiOps
</content>
</invoke>
