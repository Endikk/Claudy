# Developing Claudy

[← README](../README.md)

## Run (development)

```bash
open Claudy.xcodeproj
```

then ⌘R.

Target: **macOS 13 Ventura** or newer. Xcode 16 or newer (synchronised file groups: dropping a
`.swift` into `Claudy/` is enough, nothing to declare).

> If `xcodebuild` refuses to start with `xcodebuild failed to load a required plug-in` /
> `IDESimulatorFoundation`, Xcode's system content is older than Xcode itself. Fix it once with:
> ```bash
> sudo xcodebuild -runFirstLaunch
> ```
> (opening Xcode.app once and accepting the component installation does the same thing).

## Build the .app

```bash
./Scripts/build-app.sh            # → build/Claudy.app
./Scripts/build-app.sh --install  # → /Applications/Claudy.app, then launches it
./Scripts/build-app.sh --zip      # → dist/Claudy-<version>.zip (release artefact)
```

The script builds Release through `xcodebuild` and verifies the result (universal arm64 + x86_64
binary via `lipo`, signature via `codesign --verify`, plist via `plutil -lint`). The version comes
from `MARKETING_VERSION` in the Xcode project — the single source of truth. The binary is ad-hoc
signed: enough to run, but not enough for "Launch at login" (see below).

From Xcode: *Product ▸ Archive*, then *Distribute App ▸ Copy App*.

The app is an agent (`LSUIElement`): no Dock icon, no menu bar. Everything goes through a
**right-click on the card** — and ⌘R / ⌘Q stay active while it has focus.

## Tests

```bash
xcodebuild test -project Claudy.xcodeproj -scheme Claudy -destination 'platform=macOS'
```

The tests run inside the app, which serves as their host. Whatever either of them logs goes to
`$TMPDIR/Claudy/api.log`, never to your own `api.log`, and the account client is built with stub
token stores, so no test reads or writes the keychain.

## Before a release

```bash
./Scripts/preflight.sh
```

About a minute and a half, then a verdict. One Release build serves every step: the tests; in the
same run, the first read of synthetic histories of 20 MB, 250 MB and 1 GB, as is and confined to
the efficiency cores (the closest this Mac comes to a slower one), under Rosetta too when it is
installed; then the real app on a stand-in Claude folder, where the sign-in card must show within
a second and a half and leave by itself once a session file appears; last, the cask's style.
Nobody's own history, account or log is touched; the Claudy in use closes for a few seconds and
reopens.

The same script runs on GitHub's Macs (`.github/workflows/preflight.yml`) on every push to
`develop` that changes more than documentation, and by hand from the Actions tab: Apple silicon on
macOS 15 and 26, Intel on macOS 15. There it builds for the machine's own architecture, reads the
20 MB and 1 GB histories only, and allows three times the time. macOS 13, the oldest Claudy
supports, is no longer offered there.

GitHub's Intel Mac is a virtual machine whose graphics device Metal cannot load SwiftUI's shaders
for: any SwiftUI window aborts there, every released version of Claudy included. The tests do not
need one (hosting them, Claudy only installs its menu), the one test that renders is skipped
there, and so is the real-app step.

## Structure

```
Claudy/
├── App/          main.swift (AppKit entry) · AppDelegate (window, position, ⌘ menu) · FloatingPanel
├── Models/       UsageSnapshot and its parts · QuotaModels (account readings and their source)
├── Services/     ClaudeHome (paths) · TranscriptScanner (incremental read) ·
│                 UsageAggregator (windows, gauges) · ClaudeAccountClient (OAuth API) ·
│                 ClaudeCodeCredentials (read-only borrowed token) · ClaudeCredentials (own store) ·
│                 ClaudeOAuth (PKCE fallback) · UsageBridge (status-line relay) ·
│                 UsageDataSource (protocol, local source, switch) · DemoUsageDataSource ·
│                 AccountLoader · ModelName · LaunchAtLogin
├── ViewModels/   UsageViewModel: state, preferences, formatting
├── Theme/        Design tokens · NSVisualEffectView bridge
└── Views/        RootView (background, modes, context menu) · MinimalView · FullView · Components/
```

### Performance

Transcripts only grow and quickly reach tens of megabytes. `TranscriptScanner` therefore keeps an
offset per file and re-reads only the appended tail, after discarding files untouched within the
window and lines that contain no `"usage"`. Lines are sliced with `memchr` and `memmem`, and
timestamps read without `ISO8601DateFormatter`: on a 1.7 GB history (919 MB to read in the window,
18,000 responses), the first pass went from 6.2 s to **2 s** in a Release build, and later passes
take milliseconds. Measure in Release: a Debug build runs this code several times slower.

The first pass does not hold the card up. The account is read alongside it, and the sign-in card,
which shows no token count, does not wait for it at all.

The API is polled every 3 minutes with a 60-second cache, and the profile is re-read only every
6 hours. Polling every 60 seconds, as an earlier version did, produced cascades of HTTP 429.

### Window

Four technical points are worth knowing before changing it:

- **The entry point is AppKit** (`main.swift`), not `@main struct ClaudyApp: App`. Under a SwiftUI
  life cycle the residual scene required by the `App` protocol (`Settings`) fights the floating
  panel and triggers an AppKit ↔ SwiftUI layout recursion: the app dies with `SIGSEGV` (stack
  overflow) after about 3 s. Do not reintroduce a SwiftUI scene.
- `FloatingPanel` **must** override `canBecomeKey`: without it a `.borderless` panel receives
  neither keyboard input nor a reliable context menu.
- The window size follows SwiftUI's intrinsic size
  (`NSHostingController.sizingOptions = [.preferredContentSize]`). Do not hardcode a height.
- The card is **anchored by its bottom-right corner**: `setContentSize` pins the top-left corner
  (growth downward), so `AppDelegate.windowDidResize` re-hangs the card on its anchor — it grows
  upward and stays fully visible. The anchor resets to the screen's bottom right on every launch;
  a mouse drag updates it for the session.

## Launch at login

`SMAppService.mainApp.register()` requires an app signed with a stable identity. The project is
configured for ad-hoc signing (`CODE_SIGN_IDENTITY = "-"`) so it builds without a developer
account: in that state the app detects its own signature and the context menu shows the option
greyed out as "unavailable, app is unsigned", rather than a checkbox that would untick itself.

**Alternative without signing**: System Settings ▸ General ▸ Login Items & Extensions ▸ Open at
Login ▸ "+" ▸ Claudy.

To enable it properly in the app: select your Team in *Signing & Capabilities* and set
`CODE_SIGN_STYLE` back to `Automatic`.
