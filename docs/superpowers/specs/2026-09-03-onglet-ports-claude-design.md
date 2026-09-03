# Onglet « Ports » — tuer les ports laissés ouverts par Claude Code

Date : 2026-09-03
Statut : design validé, spike d'attribution concluant, implémentation non commencée
Portée : local uniquement (pas de distribution, pas de release)

## Problème

Claude Code lance des serveurs pour tester (`npm run dev`, `bun`, `python -m http.server`)
et ne les éteint pas toujours. Quand la session Claude se termine, launchd réadopte ces
process : leur ascendance disparaît, plus rien ne dit qu'ils viennent de Claude, et ils
occupent un port pendant des jours.

Constaté sur la machine de développement le 2026-09-03, sur 27 listeners :
`bun … claude-mem/worker-server`, port 37701, PPID 1, lancé 2 jours plus tôt.

## Objectif

Un onglet dans le widget Claudy qui liste les ports en écoute attribuables à Claude Code
et permet de les tuer un par un. Rien d'autre. Le widget reste un widget de quotas :
l'onglet est une annexe clairement séparée, pas une deuxième raison d'être.

## Décisions prises

| Question | Décision | Motif |
|---|---|---|
| Périmètre | Orphelins inclus | Sans eux, l'outil rate exactement les cas qui posent problème |
| Attribution | Variables d'environnement héritées | Prouvé : survit à l'orphelinage, aucun état à maintenir |
| Surface UI | Segmented control dans la carte (`usage` / `ports`) | Reste dans le widget, badge d'alerte visible, aucune fenêtre en plus |
| Politique de kill | Manuel, un clic par ligne | Tuer est irréversible ; aucune automatisation |
| Moteur | Scan interne à Claudy | Claudy tourne déjà ; ne pas écrire dans la config Claude de l'utilisateur |

## Spike d'attribution — résultats (2026-09-03)

`ps -Eww -p <pid>` expose l'environnement de tout process du même utilisateur. Mesures :

| PID | Process | Marqueurs |
|---|---|---|
| 46694 | `python -m http.server 4000`, lancé par Claude en session | `CLAUDECODE=1` |
| 95778 | `bun … claude-mem/worker-server`, orphelin depuis 2 jours | `CLAUDE_PROJECT_DIR=…` |
| 5771 | `next-server` port 3000 | aucun |
| 49057 | `npm run dev` | aucun |

Trois conclusions qui structurent le design :

1. **L'environnement survit à l'orphelinage.** Le worker de 2 jours reste attribuable sans
   aucune persistance. Le registre envisagé initialement est supprimé de l'architecture.
2. **`next dev` et `npm run dev` de la machine ne viennent pas de Claude.** L'heuristique
   `probable` par `cwd` prévue en première version les aurait marqués à tort : elle est
   supprimée. `CLAUDE_PROJECT_DIR` donne le projet directement, sans deviner.
3. L'ascendance reste utile, mais pour une autre raison : identifier la session Claude
   **vivante** afin de ne jamais la tuer.

Vérification à faire tôt dans l'implémentation : la même lecture depuis l'app GUI, non
lancée par un terminal. La règle noyau est « même uid », pas « même session », donc le
résultat est attendu identique — mais cela se vérifie au lieu de se supposer.

## Contraintes vérifiées

- `ENABLE_APP_SANDBOX = NO` et `ENABLE_HARDENED_RUNTIME = NO` dans `project.pbxproj` :
  lire l'environnement et envoyer des signaux est possible, aucun entitlement à ajouter.
- Précédent de style pour les sous-processus : `Services/ClaudeCodeCredentials.swift`
  (chemin absolu de l'exécutable, timeout explicite, trace `DiagnosticLog`, jamais de shell).
- Aucun target de test n'existe dans le projet aujourd'hui.

## Architecture

| Fichier | Rôle | ~lignes |
|---|---|---|
| `Models/PortModels.swift` | `ListeningPort`, `PortAttribution`, `PortScanState` | 80 |
| `Services/ProcessEnvironment.swift` | `KERN_PROCARGS2` en Swift : argv sauté, région env isolée | 90 |
| `Services/ProcessTable.swift` | une passe `ps`, arbre PPID, marche des ancêtres | 100 |
| `Services/PortScanner.swift` | `lsof`, jointure, attribution | 120 |
| `Services/PortReaper.swift` | kill sous garde-fous, signal injecté pour les tests | 90 |
| `ViewModels/PortsViewModel.swift` | état publié, cadence, action kill | 110 |

Vues neuves : `Views/PortsView.swift`, `Views/Components/PortRow.swift`,
`Views/Components/TabSwitcher.swift`.
Vues modifiées : `Views/FullView.swift` (header + corps commuté), `Theme/Theme.swift`
(deux métriques). `ViewModels/UsageViewModel.swift` ne gagne que l'enum d'onglet.

`ProcessEnvironment` lit `KERN_PROCARGS2` directement par `sysctl` plutôt que de lancer un
`ps -E` par process : une syscall au lieu d'un fork, et surtout la région d'environnement
est isolée proprement (saut de `argc` arguments) au lieu d'être cherchée dans un texte où
une ligne de commande contenant `CLAUDECODE=` produirait un faux positif. `ps -Eww` reste
le repli si `sysctl` échoue.

### Flux de données

```
tick (30 s en fond, 5 s onglet visible, immédiat à l'ouverture)
  └─ PortScanner.scan()                     hors main thread
       ├─ lsof -nP -iTCP -sTCP:LISTEN -a -u <uid> -F pcn
       ├─ ps -Ao pid=,ppid=,lstart=,args=   arbre, pour protéger les sessions vivantes
       └─ ProcessEnvironment(pid) par listener candidat  → attribution
  └─ publication sur le main thread
```

Aucune persistance. L'âge affiché vient de `lstart`, lu à chaque scan.

### Parsing

- `lsof -F pcn` : sortie à champs (`p<pid>`, `c<command>`, `n<adresse>`), pas de colonnes,
  qui tronquent et échappent les noms (`Code\x20H` observé en sonde). lsof émet aussi des
  champs non demandés, `f<fd>` en particulier : le parseur ignore tout champ inconnu.
- `ps -Ao pid=,ppid=,lstart=,args=` : `lstart` occupe exactement 5 tokens
  (`Thu Sep  3 19:10:26 2026`), donc découpage déterministe — pid, ppid, 5 tokens, reste = args.

Les deux parseurs sont des fonctions pures sur `String`, testables sur fixtures.

## Attribution

**`confirmed`** — l'environnement du process porte au moins un marqueur Claude Code :
`CLAUDECODE`, `CLAUDE_CODE_ENTRYPOINT` ou `CLAUDE_PROJECT_DIR`. Vrai pour les descendants
d'une session vivante comme pour les orphelins de sessions mortes.

**`orphan`** — `confirmed`, mais aucun ancêtre `claude` vivant. Affiché en ambre : c'est la
cible principale de l'onglet.

**Rien d'autre n'est attribué.** Pas d'heuristique par répertoire, pas de correspondance de
commande. Un port sans marqueur n'apparaît pas dans la liste.

**Denylist dure.** Un port publié par un conteneur a pour listener le runtime, pas le
process de Claude : le tuer tuerait le runtime entier. OrbStack, Docker et
`com.docker.backend` ne sont jamais attribuables, quels que soient leurs marqueurs.

## Interface

`TabSwitcher` dans le header de `FullView` : deux segments `usage` / `ports`, pastille
chiffrée sur `ports` seulement quand des orphelins existent. Largeur 340 inchangée, mêmes
matériaux, aucune valeur brute — tout passe par `Theme`.

Ligne de port : numéro en chiffres monospace coral, commande, `projet · âge` (le projet
vient de `CLAUDE_PROJECT_DIR`), pastille `orphelin` en ambre, croix révélée au survol.

État vide soigné, car c'est l'état le plus fréquent : « Aucun port ouvert par Claude. »

## Kill — garde-fous

1. **Re-vérification avant signal** : `(pid, startedAt, port)` toujours identiques à
   l'affichage. Sinon refus — entre le rendu et le clic, le process a pu mourir et son PID
   être réattribué à un autre.
2. **Refus catégoriques** : `pid <= 1`, le pid de Claudy, tout ancêtre de Claudy, et tout
   process racine d'une session Claude vivante.
3. `killpg(pgid, SIGTERM)` quand le groupe n'est ni celui de Claudy ni 1, sinon
   `kill(pid, SIGTERM)`.
4. Attente 3 s par sondages de 100 ms, puis `SIGKILL`, puis échec rapporté sur la ligne.
5. « Tout tuer » ne porte que sur les orphelins, derrière une confirmation qui liste
   nommément les lignes concernées.

## Vie privée

L'environnement d'un process contient des secrets. `ProcessEnvironment` ne retourne jamais
l'environnement : il expose un test de présence des trois clés Claude et la seule valeur de
`CLAUDE_PROJECT_DIR`. Rien n'est écrit sur disque, rien n'est journalisé.

L'onglet ne lit que la table de process locale et n'émet aucune requête réseau. La promesse
« aucune télémétrie » du README tient et doit être réaffirmée explicitement pour cette
fonctionnalité.

## Erreurs

- `lsof` absent ou code de sortie non nul : l'onglet affiche `scan indisponible` avec la
  raison, jamais de crash, trace dans `DiagnosticLog`.
- `sysctl` refusé : repli sur l'attribution par ascendance seule, avec une mention visible
  dans l'onglet que les orphelins ne sont alors plus détectables. Pas d'étage intermédiaire
  par `ps -Eww` : mêmes droits noyau que `sysctl`, un fork de plus, aucun gain.
- `EPERM` / `ESRCH` au kill : raison affichée en ligne, sur la ligne concernée.

## Tests

Le projet n'a pas de target de test : en ajouter un fait partie du périmètre.

- parseur `ps` et parseur `lsof -F` sur chaînes fixtures, champs inconnus compris ;
- découpage `KERN_PROCARGS2` sur un tampon fabriqué : une ligne de commande contenant
  `CLAUDECODE=1` ne doit pas produire d'attribution ;
- attribution sur arbres de process synthétiques, orphelins et denylist compris ;
- garde-fous du reaper avec un `SignalSending` injecté.

Aucun test n'envoie de signal à un vrai process.

## Hors périmètre

Auto-kill à la fin de session, LaunchAgent scannant Claudy fermé, UDP et sockets Unix,
ports de conteneurs. Chacun fera l'objet d'un ticket distinct.
