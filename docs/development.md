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
window and lines that contain no `"usage"`. Measured on a machine with 13 projects and 33 MB in
the single largest file: **2.1 s on the first scan, ~110 ms afterwards**.

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
greyed out as "unavailable — app is unsigned", rather than a checkbox that would untick itself.

**Alternative without signing**: System Settings ▸ General ▸ Login Items & Extensions ▸ Open at
Login ▸ "+" ▸ Claudy.

To enable it properly in the app: select your Team in *Signing & Capabilities* and set
`CODE_SIGN_STYLE` back to `Automatic`.
