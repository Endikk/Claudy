# Fonctionnement

[← README](../../README.fr.md)

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
