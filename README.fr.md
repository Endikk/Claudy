# ✳︎ Claudy

**Tes quotas Claude, en vrai, sur ton bureau.**

[![Téléchargements](https://img.shields.io/github/downloads/Endikk/Claudy/total?label=t%C3%A9l%C3%A9chargements&color=D97757)](https://github.com/Endikk/Claudy/releases)
[![Stars](https://img.shields.io/github/stars/Endikk/Claudy?color=D97757)](https://github.com/Endikk/Claudy/stargazers)
[![Licence](https://img.shields.io/badge/licence-MIT-green)](LICENSE)
![macOS](https://img.shields.io/badge/macOS-13%2B-blue)

🇬🇧 [Read this README in English](README.md)

<p align="center">
  <img src="docs/video-readme.gif" width="620" alt="Le widget Claudy en action : session 5 h, quotas hebdo, totaux du jour, sparkline 7 jours">
</p>

Widget de bureau macOS affichant ta consommation Claude : carte flottante sans bordure, toujours
au premier plan, déplaçable à la souris, en mode compact ou détaillé. Les jauges affichent les
**quotas réels de ton compte** — les mêmes chiffres que claude.ai ▸ Utilisation et `/usage` — et le
détail en tokens vient des transcripts locaux de Claude Code.

> L'interface de l'application est en anglais.

**Tes données restent chez toi.** Pas de télémétrie, pas de serveur tiers, aucune conversation lue
ni envoyée. Les seules requêtes réseau vont à l'API d'Anthropic. Le code est court et auditable.

## Installer

**Homebrew :**

```bash
brew tap Endikk/claudy
brew trust Endikk/claudy
brew install --cask claudy
```

Depuis Homebrew 6, `brew trust` est obligatoire pour tout tap tiers : Homebrew refuse de charger
du code d'un dépôt qui n'est pas le sien tant que tu ne l'as pas approuvé explicitement. C'est une
bonne chose — tu déclares faire confiance à ce dépôt précis.

**Ou en une commande (release précompilée) :**

```bash
curl -fsSL https://raw.githubusercontent.com/Endikk/Claudy/main/Scripts/install.sh | bash
```

L'app arrive dans `/Applications` (trouvable via Spotlight). Claudy n'est **pas notarisé** : c'est
une distribution gratuite, sans compte Apple Developer. La commande retire donc la quarantaine
posée au téléchargement — sans quoi Gatekeeper refuserait de lancer l'app. Si tu préfères ne rien
dé-quarantiner, compile toi-même (voie 2) : le code est court et auditable.

**Voie 2 — depuis les sources (nécessite Xcode) :**

```bash
git clone https://github.com/Endikk/Claudy.git
cd Claudy
./Scripts/build-app.sh --install
```

## Lancer (développement)

```bash
open Claudy.xcodeproj
```

puis ⌘R.

Cible : **macOS 13 Ventura** ou plus récent. Xcode 16 ou plus récent (groupes de fichiers
synchronisés : ajouter un `.swift` dans `Claudy/` suffit, rien à déclarer).

> Si `xcodebuild` refuse de démarrer avec `xcodebuild failed to load a required plug-in` /
> `IDESimulatorFoundation`, le contenu système de Xcode est plus ancien que Xcode lui-même.
> Corriger une fois avec :
> ```bash
> sudo xcodebuild -runFirstLaunch
> ```
> (ouvrir Xcode.app une fois et accepter l'installation des composants fait la même chose).

## Produire le .app

```bash
./Scripts/build-app.sh            # → build/Claudy.app
./Scripts/build-app.sh --install  # → /Applications/Claudy.app, puis le lance
./Scripts/build-app.sh --zip      # → dist/Claudy-<version>.zip (artefact de release)
```

Le script compile en Release via `xcodebuild` et vérifie le résultat (binaire universel
arm64 + x86_64 via `lipo`, signature via `codesign --verify`, plist via `plutil -lint`). La version
vient de `MARKETING_VERSION` dans le projet Xcode — unique source de vérité. Le binaire est signé
ad hoc : suffisant pour tourner, mais pas pour « Lancer au démarrage » (voir plus bas).

Depuis Xcode : *Product ▸ Archive*, puis *Distribute App ▸ Copy App*.

L'app est un agent (`LSUIElement`) : pas d'icône dans le Dock, pas de barre de menus. Tout passe
par le **clic droit sur la carte** — et ⌘R / ⌘Q restent actifs quand elle a le focus.

## Utiliser

| Geste | Effet |
|---|---|
| Glisser n'importe où sur la carte | Déplacer le widget (le temps de la session — il revient en bas à droite au lancement) |
| Clic sur la bande minimale | Passer en mode complet |
| Clic droit | Rafraîchir · Mode minimal/complet · Connexion · Toujours au premier plan · Lancer au démarrage · Quitter |
| Clic sur l'avatar | Fiche compte (nom, e-mail, plan, organisation) |
| Clic sur « Details » | Accordéon : répartition par modèle et top projets |

Rafraîchissement automatique toutes les 3 minutes, plus un relevé immédiat au réveil de la machine.

## D'où viennent les données

| Donnée | Source |
|---|---|
| Pourcentages et heures de reset des jauges | `api.anthropic.com/api/oauth/usage` |
| Tokens, modèles, projets, sessions | `<config>/projects/**/*.jsonl` — un objet `message.usage` par réponse |
| Compte, plan, organisation | `api.anthropic.com/api/oauth/profile`, repli `.claude.json` (bloc `oauthAccount`) |
| Rôle (badge Admin) | `.claude.json`, bloc `oauthAccount` |
| Nom affiché sans compte Claude | `NSFullUserName()` de la session macOS |

**Invariant : les pourcentages des jauges viennent uniquement de l'API.** Les transcripts ne
servent qu'au **détail en tokens** (totaux, répartitions, sparkline). Les deux ne sont jamais
fusionnés en un seul chiffre.

`<config>` vaut, par ordre de priorité : le réglage `claudy.configDir`, puis `$CLAUDE_CONFIG_DIR`,
sinon `~/.claude`. La variable d'environnement ne sert qu'aux lancements depuis un terminal — une
app ouverte depuis le Finder ou le Dock n'hérite pas du shell. Pour rediriger la configuration de
façon persistante :

```bash
defaults write com.claudy.Claudy claudy.configDir ~/mon-dossier-claude
```

Quand un répertoire personnalisé est défini, aucun repli vers le dossier personnel n'a lieu :
rediriger la configuration isole complètement.

Les tokens comptés sont la somme des quatre compteurs (`input`, `output`, `cache_creation`,
`cache_read`). Les lectures de cache dominent : une semaine chargée dépasse couramment le milliard
de tokens, d'où l'unité « B » dans l'interface.

Claude Code réécrit la même réponse sur plusieurs lignes du transcript (une par bloc de contenu),
avec un bloc `usage` identique. Claudy **déduplique** sur `(message.id, requestId)` — la même clé
que `ccusage` — sans quoi les totaux seraient gonflés d'un facteur ~2.

Le nom d'un projet vient du champ `cwd` de la ligne, jamais du nom de dossier de transcript —
celui-ci est une translittération qui perd accents et séparateurs
(`~/Documents/Développement/Ma-App` y devient `-Users-…-D-veloppement-Ma-App`).

### Comment les pourcentages restent justes

**Un seul chiffre, celui du compte.** Les trois jauges affichent les pourcentages et les heures de
remise à zéro que rapporte `api.anthropic.com/api/oauth/usage` — le point d'accès qu'interrogent
claude.ai ▸ Réglages ▸ Utilisation et la commande `/usage` de Claude Code. Session 5 h, hebdo tous
modèles, hebdo du modèle suivi (« Fable », « Opus »… selon le compte). Rien n'est recalculé, rien
n'est estimé.

**Le jeton est emprunté à Claude Code, en lecture seule.** C'est ce qui rend la liaison durable :
Claude Code renouvelle son jeton à chaque lancement et avant chaque expiration, donc il est
toujours frais, et Claudy n'a rien à rafraîchir. Aucun `refresh_token` n'est lu ni consommé — une
rotation déclenchée par Claudy invaliderait la session de Claude Code lui-même. La lecture passe
par `/usr/bin/security`, le binaire qui a créé l'item du trousseau et à qui son ACL fait déjà
confiance : **aucun dialogue macOS « informations confidentielles »**.

Une connexion OAuth propre à Claudy (« Sign in to Claude ») reste possible pour les machines où le
jeton de Claude Code n'est pas lisible. Elle sert de second choix : rafraîchie de façon autonome,
et abandonnée dès qu'Anthropic répond `invalid_grant` — un jeton mort cède la place à l'emprunt au
lieu de boucler indéfiniment.

Ce qui rend la liaison fiable :

- **Deux sources, jamais une invention.** L'API d'abord ; à défaut, les compteurs que Claude Code a
  déjà reçus dans ses en-têtes `anthropic-ratelimit-unified-*` et qu'une ligne de statusline peut
  déposer pour Claudy (voir ci-dessous) — mêmes valeurs, zéro requête, insensibles au rate-limit.
- **Retry unique sur 401** : jeton emprunté, on le relit (Claude Code vient peut-être d'en écrire
  un nouveau) ; jeton propre, on le rafraîchit. Jamais de boucle.
- **Dernière valeur connue + backoff** : un échec ne remet rien à zéro. La dernière valeur reste
  affichée derrière une pastille « ⟳ » datée, et les tentatives s'espacent — `Retry-After` honoré,
  sinon 5 → 15 → 30 → 60 min pour un rate-limit, et seulement 30 s → 5 min pour une panne réseau
  ou serveur passagère.
- **Journal** : chaque échec est horodaté dans `~/Library/Application Support/Claudy/api.log`
  (code HTTP, refresh), ce qui permet de distinguer un rate-limit d'un jeton mort.

Ces points d'accès ne sont pas documentés et peuvent changer sans préavis. C'est précisément
pourquoi l'app ne comble jamais leur silence.

**Quand il n'y a pas de mesure, il n'y a pas de chiffre.** Les jauges affichent « — » et une
pastille « offline ». Une version précédente estimait le pourcentage manquant à partir des
transcripts locaux (90ᵉ centile des fenêtres écoulées) : c'était faux par construction. La réponse
d'Anthropic donne `limit_dollars: null` et `used_dollars: null` — le quota n'est pas un décompte de
tokens, et aucun comptage local ne peut le reproduire. Mieux vaut ne rien afficher qu'un chiffre
qui ne veut rien dire.

Les tokens comptés dans les transcripts restent affichés, mais pour ce qu'ils sont : la
consommation **de cette machine** (« 12.4 M tokens on this machine »), l'historique 7 jours et les
répartitions par modèle et par projet. Ils ne se mélangent jamais au pourcentage du compte.

### Passerelle statusline (facultative)

À chaque réponse de l'API, Claude Code lit ses en-têtes de quota et les passe à la statusline. Une
ligne suffit à les déposer où Claudy sait les relire — utile quand l'API est momentanément
injoignable :

```bash
tee "$HOME/Library/Application Support/Claudy/usage-bridge.json" > /dev/null
```

À ajouter à la commande `statusLine` de `~/.claude/settings.json` (en fin de chaîne, pour ne pas
perturber l'affichage existant). Claudy ignore un relevé de plus de 30 min, et n'y recourt que si
l'API n'a rien donné de frais.

### Le repère de rythme

Chaque jauge porte un trait vertical : la part de sa fenêtre **déjà écoulée**. À mi-parcours d'une
session de 5 h, une consommation régulière serait pile sur le trait.

- Remplissage **à droite** du repère → consommation en avance sur l'horloge.
- Remplissage **à gauche** → sous le rythme.

Le bloc principal traduit l'écart en toutes lettres (« 15 pts ahead of pace »), les colonnes le
résument à un signe (`+15` / `−14`). Sous 4 points d'écart, l'app affiche « on pace » plutôt que de
qualifier d'avance le bruit d'une requête isolée. Au-delà de 20 points d'avance, le libellé passe
au rouge.

Le repère disparaît quand aucune fenêtre n'est en cours — il n'y a alors pas de rythme à tenir.

Au-delà de **95 %** sur n'importe quelle jauge **mesurée**, le liseré de la carte vire au rouge,
d'une intensité qui monte jusqu'à 100 %. Un signal qu'on voit du coin de l'œil, sans avoir à lire
un chiffre. Une jauge sans mesure ne le déclenche jamais : on n'alerte pas sur un chiffre qu'on
n'a pas.

Les fenêtres hebdomadaires sont **celles d'Anthropic** : 7 jours ancrés sur la vraie heure de
remise à zéro du compte (par ex. lundi 17:00), jamais une semaine calendaire inventée localement.
L'historique, la sparkline et les répartitions restent, eux, sur 7 jours glissants : une courbe qui
repart d'un point chaque lundi n'apprendrait rien.

Les barres de la section « Details » n'ont volontairement pas de repère : elles expriment une part
du total, pas une durée.

### Mode démonstration

Sans `.claude.json` ni dossier `projects`, l'app bascule sur `DemoUsageDataSource` et **l'annonce**
par une pastille « demo » dans l'en-tête. Le jeu de démonstration ne contient rien d'identifiant :
le nom vient de la session macOS, les projets portent des noms neutres. La bascule est réévaluée à
chaque rafraîchissement — installer Claude Code après coup suffit.

Si Claude Code est présent mais sans activité sur 7 jours, l'app affiche le vrai compte avec des
compteurs à zéro : elle ne substitue pas des chiffres de démonstration à une absence d'usage.

Toute autre panne (dossier `projects` illisible, droits manquants) n'entraîne **pas** de bascule en
démonstration : le dernier relevé valide reste affiché et une pastille « error » (point rouge en
mode minimal) apparaît, avec le détail au survol.

## Structure

```
Claudy/
├── App/          main.swift (entrée AppKit) · AppDelegate (fenêtre, position, menu ⌘) · FloatingPanel
├── Models/       UsageSnapshot et ses composants · QuotaModels (relevés du compte et leur source)
├── Services/     ClaudeHome (chemins) · TranscriptScanner (lecture incrémentale) ·
│                 UsageAggregator (fenêtres, jauges) · ClaudeAccountClient (API OAuth) ·
│                 ClaudeCodeCredentials (jeton emprunté, lecture seule) · ClaudeCredentials (magasin propre) ·
│                 ClaudeOAuth (repli PKCE) · UsageBridge (relais statusline) ·
│                 UsageDataSource (protocole, source locale, bascule) · DemoUsageDataSource ·
│                 AccountLoader · ModelName · LaunchAtLogin
├── ViewModels/   UsageViewModel : état + préférences + formatage
├── Theme/        Jetons de design · pont NSVisualEffectView
└── Views/        RootView (fond, modes, menu contextuel) · MinimalView · FullView · Components/
```

### Performance

Les transcripts ne font que grossir et pèsent vite plusieurs dizaines de mégaoctets.
`TranscriptScanner` mémorise donc un décalage par fichier et ne relit que la queue ajoutée, après
avoir écarté les fichiers non modifiés dans la fenêtre et les lignes ne contenant pas `"usage"`.
Mesuré sur une machine avec 13 projets et 33 Mo de transcripts pour le seul plus gros fichier :
**2,1 s au premier scan, ~110 ms ensuite**.

L'API est interrogée toutes les 3 minutes avec un cache de 60 s, et le profil n'est relu que toutes
les 6 heures. Un relevé toutes les 60 s, comme dans une version précédente, provoquait des cascades
de HTTP 429.

### Fenêtre

Quatre points techniques valent d'être connus avant de la modifier :

- **Le point d'entrée est AppKit** (`main.swift`), pas `@main struct ClaudyApp: App`. Avec un cycle
  de vie SwiftUI, la scène résiduelle nécessaire au protocole `App` (`Settings`) entre en conflit
  avec le panneau flottant et déclenche une récursion de layout AppKit ↔ SwiftUI : l'app meurt en
  `SIGSEGV` (débordement de pile) après ~3 s. Ne pas réintroduire de scène SwiftUI.
- `FloatingPanel` **doit** surcharger `canBecomeKey` : sans ça, un panneau `.borderless` ne reçoit
  ni clavier ni menu contextuel fiable.
- La taille de la fenêtre suit la taille intrinsèque SwiftUI
  (`NSHostingController.sizingOptions = [.preferredContentSize]`). Ne pas coder de hauteur en dur.
- La carte est **ancrée par son coin bas-droit** : `setContentSize` fige le coin haut-gauche
  (croissance vers le bas), donc `AppDelegate.windowDidResize` re-suspend la carte à son ancre —
  elle grandit vers le haut et reste entièrement visible. L'ancre est réinitialisée en bas à droite
  de l'écran à chaque lancement ; un déplacement à la souris la met à jour pour la session.

## Lancement au démarrage

`SMAppService.mainApp.register()` exige une app signée avec une identité stable. Le projet est
configuré en signature ad-hoc (`CODE_SIGN_IDENTITY = "-"`) pour compiler sans compte développeur :
dans cet état, l'app détecte sa propre signature et le menu contextuel affiche l'option grisée
« unavailable — app is unsigned » plutôt qu'une case qui se décocherait toute seule.

**Alternative sans signature** : Réglages Système ▸ Général ▸ Ouverture et extensions ▸ Ouvrir à
l'ouverture de session ▸ « + » ▸ Claudy.

Pour l'activer réellement dans l'app : sélectionner sa Team dans *Signing & Capabilities* et
repasser `CODE_SIGN_STYLE` en `Automatic`.

## Vie privée

Le réseau ne sert qu'à parler à Anthropic : `usage` (quotas), `profile` (identité du compte), et —
si tu utilises la connexion propre à Claudy — le flux OAuth dans ton navigateur puis le
renouvellement standard du jeton. Rien d'autre n'est envoyé : pas de télémétrie, pas de contenu de
conversation, pas de serveur tiers.

Par défaut, Claudy emprunte le jeton de Claude Code **en lecture seule**, via `/usr/bin/security`,
et ne le réécrit jamais ; son `refresh_token` n'est même pas conservé en mémoire. Si tu te connectes
depuis Claudy, ce jeton-là vit dans un item de trousseau **propre à l'app**
(« Claudy-credentials ») et la déconnexion le supprime. Hors-ligne, l'app continue de fonctionner
en local et annonce que ses quotas sont indisponibles. Le sandbox est désactivé uniquement pour
permettre la lecture de `~/.claude`.

## Contribuer

Un bug, une idée, un chiffre qui ne colle pas avec claude.ai ? Ouvre une
[issue GitHub](https://github.com/Endikk/Claudy/issues) — capture d'écran et contenu de
`~/Library/Application Support/Claudy/api.log` bienvenus. Les PR sont ouvertes ; le projet est sous
licence MIT, maintenu par [@Endikk](https://github.com/Endikk).
