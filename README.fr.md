<div align="center">

# ✳︎ Claudy

**Tes vrais quotas Claude, sur ton bureau.**

[![Téléchargements](https://img.shields.io/github/downloads/Endikk/Claudy/total?label=downloads&color=D97757&style=flat-square)](https://github.com/Endikk/Claudy/releases)
[![Stars](https://img.shields.io/github/stars/Endikk/Claudy?color=D97757&style=flat-square)](https://github.com/Endikk/Claudy/stargazers)
[![Version](https://img.shields.io/github/v/release/Endikk/Claudy?color=D97757&style=flat-square)](https://github.com/Endikk/Claudy/releases/latest)
[![macOS](https://img.shields.io/badge/macOS-13%2B-black?style=flat-square)](https://www.apple.com/fr/macos/)
[![Licence](https://img.shields.io/badge/licence-MIT-black?style=flat-square)](LICENSE)

🇬🇧 [Read this README in English](README.md)

<p align="center"><img src="docs/claudy-typing.gif" width="132" alt="Claudy, la mascotte en pixel art, qui tape sur son ordinateur"></p>

<p align="center"><img src="docs/video-readme.gif" width="620" alt="Le widget Claudy : session 5 h, quotas hebdomadaires, totaux du jour, sparkline 7 jours"></p>

</div>

Un widget macOS flottant pour ton usage de Claude. Sans bordure, toujours au-dessus, déplaçable,
en mode compact ou complet. Les jauges affichent les **vrais quotas** du compte — les mêmes
chiffres que claude.ai ▸ Usage et `/usage` — tandis que le détail des tokens vient des transcripts
locaux de Claude Code.

- **Des chiffres réels, ou aucun.** Les pourcentages viennent de la seule API d'Anthropic. Quand
  elle ne dit rien, les jauges affichent « — » plutôt qu'une estimation.
- **Onglet Ports.** Liste les ports TCP laissés en écoute par Claude Code, sessions orphelines
  comprises, et les ferme d'un clic. L'attribution lit les marqueurs Claude hérités dans
  l'environnement du process : rien d'autre sur la machine n'est listé.
- **Rien ne sort de la machine.** Pas de télémétrie, pas de serveur tiers, aucune conversation lue
  ni envoyée. Les seules requêtes réseau vont à l'API d'Anthropic.

## Installer

```bash
brew tap Endikk/claudy
brew trust Endikk/claudy
brew install --cask claudy
```

<details>
<summary>Autres routes</summary>

**Release précompilée, en une commande :**

```bash
curl -fsSL https://raw.githubusercontent.com/Endikk/Claudy/main/Scripts/install.sh | bash
```

Claudy n'est **pas notarisée** — distribution gratuite, pas de compte Apple Developer — donc le
script retire le drapeau de quarantaine sans lequel Gatekeeper refuserait de lancer l'app. Tu
préfères ne rien déquarantiner ? Compile toi-même ci-dessous, le code est court et auditable.

**Depuis les sources (Xcode 16+) :**

```bash
git clone https://github.com/Endikk/Claudy.git
cd Claudy
./Scripts/build-app.sh --install
```

Depuis Homebrew 6, `brew trust` est requis pour tout tap tiers : Homebrew refuse de charger du
code d'un dépôt qui n'est pas le sien tant que tu ne l'as pas approuvé explicitement.

</details>

## Utiliser

L'app est un agent : pas d'icône dans le Dock, pas de barre de menus. Tout passe par la carte.

| Geste | Effet |
|---|---|
| Glisser la carte | Déplacer le widget |
| Clic sur la bande minimale | Passer en mode complet |
| `usage` / `ports` | Basculer entre les quotas et les ports laissés ouverts par Claude |
| Clic droit | Rafraîchir · Mode · Connexion · Toujours au-dessus · Lancement au démarrage · Quitter |
| Clic sur l'avatar | Carte du compte |
| Clic sur « Details » | Répartition par modèle et principaux projets |

Rafraîchissement toutes les 3 minutes, et immédiat au réveil de la machine.

## Documentation

- [Fonctionnement](docs/fr/fonctionnement.md) — sources des données, invariants des quotas,
  passerelle statusline, repère de rythme, mode démonstration, vie privée.
- [Développement](docs/fr/developpement.md) — lancer, produire le `.app`, structure du projet,
  contraintes de fenêtre à connaître avant d'y toucher.

## Historique des stars

<a href="https://star-history.com/#Endikk/Claudy&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=Endikk/Claudy&type=Date&theme=dark">
    <img src="https://api.star-history.com/svg?repos=Endikk/Claudy&type=Date" width="620" alt="Historique des stars">
  </picture>
</a>

## Branches

| Branche | Rôle |
|---|---|
| `main` | Stable. Ce qui est publié et ce que Homebrew installe. |
| `develop` | La branche vivante. Toute nouveauté y arrive d'abord et y reste tant qu'elle n'a pas servi pour de vrai ; `main` ne reçoit que ce qui a tenu. |

Les pull requests visent `develop`.

## Contribuer

Un bug, une idée, un chiffre qui ne correspond pas à claude.ai ? Ouvre une
[issue](https://github.com/Endikk/Claudy/issues) — une capture et
`~/Library/Application Support/Claudy/api.log` sont les bienvenus. Les PR sont ouvertes.

MIT, maintenu par [@Endikk](https://github.com/Endikk).
