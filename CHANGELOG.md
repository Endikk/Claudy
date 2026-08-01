# Journal des versions

## 1.2.0 — 1er août 2026

**Connexion Claude propre à Claudy.** L'app obtient désormais son propre jeton via une
connexion OAuth dans le navigateur, rangé dans son propre trousseau. Elle ne lit plus les
secrets de Claude Code : macOS n'affiche plus l'avertissement « informations
confidentielles ». Déconnexion depuis la fiche compte ou le clic droit.

**Onboarding plein écran.** Sans session ouverte, la carte n'affiche plus de quotas estimés :
elle présente Claudy et propose la connexion. Aucun chiffre inventé.

**Fissures au-delà de 95 %.** Un impact et ses fêlures se propagent sur la carte, le liseré
vire au rouge, l'intensité monte jusqu'à 100 %.

**Position et gestes.**
- La carte se cale au coin bas-droit physique de l'écran, à 8 pt des bords, à chaque lancement
  et à chaque changement de taille.
- Un clic sur la bande minimale l'agrandit ; un clic sur l'en-tête ou le bloc session la replie.
- Elle grandit vers le haut : l'interface reste entièrement visible.

**Divers.** Initiales des jours en français sur la sparkline (D L M M J V S). Suppression du
code mort après audit symbole par symbole. Empreinte SHA-256 épinglée dans le cask Homebrew.

## 1.1.0 — 31 juillet 2026

- Jauges branchées sur les **quotas réels** du compte (`api.anthropic.com/api/oauth/usage`) :
  mêmes pourcentages et mêmes heures de remise à zéro que claude.ai.
- Identité du compte lue depuis `/api/oauth/profile`.
- Renouvellement autonome du jeton, retry unique sur 401, backoff exponentiel, dernière valeur
  connue conservée en cas de panne, journal dans `~/Library/Application Support/Claudy/api.log`.
- Icône d'application, script d'installation en une commande, cask Homebrew.
- Retrait des boutons « Déconnexion » et « Stats équipe » qui ne faisaient rien.

## 1.0.0 — 31 juillet 2026

Première version : widget flottant, lecture incrémentale des transcripts, déduplication des
réponses sur `(message.id, requestId)` — sans quoi les totaux étaient gonflés d'un facteur ~1,9.
Erreurs signalées à l'écran plutôt que masquées par le mode démonstration. Fenêtre récupérable
après débranchement d'un écran, rafraîchissement au réveil.
