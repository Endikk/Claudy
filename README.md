# ✳︎ Claudy

**Your real Claude quotas, on your desktop.**

[![Downloads](https://img.shields.io/github/downloads/Endikk/Claudy/total?label=downloads&color=D97757)](https://github.com/Endikk/Claudy/releases)
[![Stars](https://img.shields.io/github/stars/Endikk/Claudy?color=D97757)](https://github.com/Endikk/Claudy/stargazers)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
![macOS](https://img.shields.io/badge/macOS-13%2B-blue)

🇫🇷 [Lire ce README en français](README.fr.md)

<p align="center">
  <img src="docs/video-readme.gif" width="620" alt="The Claudy widget in action: 5h session, weekly quotas, daily totals, 7-day sparkline">
</p>

A macOS desktop widget showing your Claude usage: a borderless floating card, always on top,
draggable, in compact or full mode. The gauges show your account's **real quotas** — the same
figures as claude.ai ▸ Usage and `/usage` — while the token detail comes from Claude Code's local
transcripts.

**Your data stays with you.** No telemetry, no third-party server, no conversation read or sent.
The only network requests go to Anthropic's API. The code is short and auditable.

## Install

**Homebrew:**

```bash
brew tap Endikk/claudy
brew trust Endikk/claudy
brew install --cask claudy
```

Since Homebrew 6, `brew trust` is required for any third-party tap: Homebrew refuses to load code
from a repository that is not its own until you approve it explicitly. That is a good thing — you
are declaring trust in this specific repository.

**Or in one command (prebuilt release):**

```bash
curl -fsSL https://raw.githubusercontent.com/Endikk/Claudy/main/Scripts/install.sh | bash
```

The app lands in `/Applications` (findable through Spotlight). Claudy is **not notarised**: it is
a free distribution with no Apple Developer account. The command therefore removes the quarantine
flag set at download time, without which Gatekeeper would refuse to launch the app. If you would
rather not un-quarantine anything, build it yourself (route 2): the code is short and auditable.

**Route 2 — from source (requires Xcode):**

```bash
git clone https://github.com/Endikk/Claudy.git
cd Claudy
./Scripts/build-app.sh --install
```

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

## Use

| Gesture | Effect |
|---|---|
| Drag anywhere on the card | Move the widget (for the session — it returns to the bottom right on launch) |
| Click the minimal strip | Switch to full mode |
| Right-click | Refresh · Minimal/full mode · Sign in · Always on top · Launch at login · Quit |
| Click the avatar | Account card (name, email, plan, organisation) |
| Click "Details" | Accordion: split by model and top projects |

Automatic refresh every 3 minutes, plus an immediate reading when the machine wakes.

## Where the data comes from

| Data | Source |
|---|---|
| Gauge percentages and reset times | `api.anthropic.com/api/oauth/usage` |
| Tokens, models, projects, sessions | `<config>/projects/**/*.jsonl` — one `message.usage` object per response |
| Account, plan, organisation | `api.anthropic.com/api/oauth/profile`, falling back to `.claude.json` (`oauthAccount` block) |
| Role (Admin badge) | `.claude.json`, `oauthAccount` block |
| Display name with no Claude account | `NSFullUserName()` from the macOS session |

**Invariant: the gauge percentages come from the API alone.** Transcripts only ever supply the
**token detail** (totals, splits, sparkline). The two are never merged into a single figure.

`<config>` resolves, in order: the `claudy.configDir` preference, then `$CLAUDE_CONFIG_DIR`,
otherwise `~/.claude`. The environment variable only applies to terminal launches — an app opened
from Finder or the Dock inherits no shell. To redirect the configuration persistently:

```bash
defaults write com.claudy.Claudy claudy.configDir ~/my-claude-folder
```

When a custom directory is set there is no fallback to the home folder: redirecting the
configuration isolates completely.

Counted tokens are the sum of the four counters (`input`, `output`, `cache_creation`,
`cache_read`). Cache reads dominate: a busy week routinely passes a billion tokens, hence the "B"
unit in the interface.

Claude Code rewrites the same response across several transcript lines, one per content block,
with an identical `usage` block. Claudy **deduplicates** on `(message.id, requestId)` — the same
key `ccusage` uses — without which totals would be inflated roughly twofold.

A project's name comes from the line's `cwd` field, never from the transcript folder name, which
is a transliteration that loses accents and separators (`~/Documents/Développement/My-App` becomes
`-Users-…-D-veloppement-My-App`).

### How the percentages stay true

**One figure, the account's.** The three gauges show the percentages and reset times reported by
`api.anthropic.com/api/oauth/usage` — the endpoint behind claude.ai ▸ Settings ▸ Usage and Claude
Code's `/usage`. Session 5h, weekly across all models, weekly for the scoped model ("Fable",
"Opus"… depending on the account). Nothing is recomputed, nothing is estimated.

**The token is borrowed from Claude Code, read-only.** That is what makes the link durable: Claude
Code renews its token on every launch and before every expiry, so it is always fresh and Claudy
has nothing to refresh. No `refresh_token` is read or spent — a rotation triggered by Claudy would
invalidate Claude Code's own session. The read goes through `/usr/bin/security`, the binary that
created the keychain item and which its ACL already trusts, so **no macOS "confidential
information" dialog ever appears**.

Claudy's own OAuth sign-in ("Sign in to Claude") remains available for machines where Claude
Code's token cannot be read. It is the second choice: refreshed autonomously, and abandoned as
soon as Anthropic answers `invalid_grant` — a dead token yields to the borrowed one instead of
looping forever.

What makes the link dependable:

- **Two sources, never an invention.** The API first; failing that, the counters Claude Code
  already received in its `anthropic-ratelimit-unified-*` headers, which a status-line command can
  drop for Claudy (see below) — same values, zero requests, immune to rate limiting.
- **A single retry on 401**: on a borrowed token it is re-read (Claude Code may have just written
  a new one); on Claudy's own it is refreshed. Never a loop.
- **Last known value plus backoff**: a failure resets nothing. The last reading stays on screen
  behind a dated "⟳" badge, and attempts space out — `Retry-After` honoured, otherwise 5 → 15 →
  30 → 60 min for a rate limit, and only 30 s → 5 min for a transient network or server fault.
- **Log**: every failure is timestamped in `~/Library/Application Support/Claudy/api.log` (HTTP
  code, refresh), which is what separates a rate limit from a dead token.

These endpoints are undocumented and may change without notice. That is precisely why the app
never fills their silence.

**With no measurement, there is no figure.** The gauges show "—" and an "offline" badge. An earlier
version estimated the missing percentage from local transcripts (90th percentile of elapsed
windows). That was wrong by construction: Anthropic's response carries `limit_dollars: null` and
`used_dollars: null`, so the quota is not a token tally and no local count can reproduce it.
Better to show nothing than a number that means nothing.

Tokens counted in the transcripts are still displayed, but for what they are: **this machine's**
consumption ("12.4 M tokens on this machine"), the 7-day history and the per-model and per-project
splits. They never mix with the account percentage.

### Status-line bridge (optional)

On every API response Claude Code reads its quota headers and passes them to the status line. One
line is enough to drop them where Claudy knows to read them — useful when the API is momentarily
unreachable:

```bash
tee "$HOME/Library/Application Support/Claudy/usage-bridge.json" > /dev/null
```

Add it to the `statusLine` command in `~/.claude/settings.json` (at the end of the chain, so it
does not disturb the existing display). Claudy ignores a reading older than 30 minutes, and only
falls back to it when the API has produced nothing fresh.

### The pace marker

Each gauge carries a vertical line: the share of its window **already elapsed**. Halfway through a
5-hour session, steady consumption would sit right on the line.

- Fill **to the right** of the marker → ahead of the clock.
- Fill **to the left** → behind the pace.

The main block spells the gap out ("15 pts ahead of pace"), the columns reduce it to a sign
(`+15` / `−14`). Below a 4-point gap the app says "on pace" rather than calling the noise of a
single request an advance. Past 20 points ahead, the label turns red.

The marker disappears when no window is running — there is no pace to hold.

Past **95 %** on any **measured** gauge, the card's hairline turns red, at an intensity rising to
100 %. A signal you catch out of the corner of your eye, without reading a number. An unmeasured
gauge never triggers it: nothing raises an alarm about a figure we do not have.

The weekly windows are **Anthropic's**: 7 days anchored on the account's real reset time (Monday
17:00, say), never a calendar week invented locally. The history, sparkline and splits stay on 7
rolling days: a curve restarting from a single point every Monday would teach nothing.

The bars in the "Details" section deliberately carry no marker: they express a share of the total,
not a duration.

### Demo mode

With no `.claude.json` and no `projects` folder, the app switches to `DemoUsageDataSource` and
**says so** through a "demo" badge in the header. The sample set contains nothing identifying: the
name comes from the macOS session and the projects carry neutral names. The switch is re-evaluated
on every refresh, so installing Claude Code afterwards is enough.

If Claude Code is present but has seen no activity in 7 days, the app shows the real account with
counters at zero: it does not substitute demo figures for an absence of usage.

Any other failure (unreadable `projects` folder, missing permissions) does **not** trigger demo
mode: the last valid reading stays on screen and an "error" badge appears (a red dot in minimal
mode), with the detail on hover.

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

## Privacy

The network is used only to talk to Anthropic: `usage` (quotas), `profile` (account identity), and
— when you use Claudy's own sign-in — the OAuth flow in your browser plus the standard token
renewal. Nothing else is sent: no telemetry, no conversation content, no third-party server.

By default Claudy borrows Claude Code's token **read-only**, through `/usr/bin/security`, and
never writes it back; its `refresh_token` is not even kept in memory. If you sign in through
Claudy itself, that token lives in a keychain item **of its own** ("Claudy-credentials"), and
signing out deletes it. Offline, the app keeps working locally and states that its quotas are
unavailable. The sandbox is disabled solely to allow reading `~/.claude`.

## Contributing

A bug, an idea, a figure that does not match claude.ai? Open a
[GitHub issue](https://github.com/Endikk/Claudy/issues) — a screenshot and the contents of
`~/Library/Application Support/Claudy/api.log` are welcome. PRs are open; the project is MIT
licensed, maintained by [@Endikk](https://github.com/Endikk).
