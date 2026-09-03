# Développement

[← README](../../README.fr.md)

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
