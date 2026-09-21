<div align="center">

# ✳︎ Claudy

**Your real Claude quotas, on your desktop.**

[![Downloads](https://img.shields.io/github/downloads/Endikk/Claudy/total?label=downloads&color=D97757&style=flat-square)](https://github.com/Endikk/Claudy/releases)
[![Stars](https://img.shields.io/github/stars/Endikk/Claudy?color=D97757&style=flat-square)](https://github.com/Endikk/Claudy/stargazers)
[![Release](https://img.shields.io/github/v/release/Endikk/Claudy?color=D97757&style=flat-square)](https://github.com/Endikk/Claudy/releases/latest)
[![macOS](https://img.shields.io/badge/macOS-13%2B-black?style=flat-square)](https://www.apple.com/macos/)
[![License](https://img.shields.io/badge/license-MIT-black?style=flat-square)](LICENSE)

🇫🇷 [Lire ce README en français](README.fr.md)

<p align="center"><img src="docs/claudy-typing.gif" width="132" alt="Claudy, the pixel mascot, typing at its laptop"></p>

<p align="center"><img src="docs/video-readme.gif" width="620" alt="The Claudy widget: 5h session, weekly quotas, daily totals, 7-day sparkline"></p>

</div>

A floating macOS widget for your Claude usage. Borderless, always on top, draggable, compact or
full. The gauges show your account's **real quotas** — the same figures as claude.ai ▸ Usage and
`/usage` — while the token detail comes from Claude Code's local transcripts.

- **Real numbers, or none.** Percentages come from Anthropic's API alone. When it says nothing,
  the gauges read "—" rather than an estimate.
- **Ports tab.** Lists the TCP ports Claude Code left listening, orphaned sessions included, and
  kills them on a click. Attribution reads the Claude markers a process inherits in its
  environment, so nothing else on your machine is ever listed.
- **Nothing leaves the machine.** No telemetry, no third-party server, no conversation read or
  sent. The only network requests go to Anthropic's API.

## Install

```bash
brew tap Endikk/claudy
brew trust Endikk/claudy
brew install --cask claudy
```

<details>
<summary>Other routes</summary>

**Prebuilt release, one command:**

```bash
curl -fsSL https://raw.githubusercontent.com/Endikk/Claudy/main/Scripts/install.sh | bash
```

Claudy is **not notarised** — free distribution, no Apple Developer account — so the script
removes the quarantine flag Gatekeeper would otherwise refuse to launch past. Prefer not to
un-quarantine anything? Build it yourself below; the code is short and auditable.

**From source (requires Xcode 16+):**

```bash
git clone https://github.com/Endikk/Claudy.git
cd Claudy
./Scripts/build-app.sh --install
```

Since Homebrew 6, `brew trust` is required for any third-party tap: Homebrew refuses to load code
from a repository that is not its own until you approve it explicitly.

</details>

## Use

The app is an agent: no Dock icon, no menu bar. Everything goes through the card.

| Gesture | Effect |
|---|---|
| Drag the card | Move the widget |
| Click the minimal strip | Switch to full mode |
| `usage` / `ports` | Switch between quotas and the ports Claude left open |
| Right-click | Refresh · Mode · Sign in · Always on top · Launch at login · Quit |
| Click the avatar | Account card |
| Click "Details" | Split by model and top projects |

Refreshes every 3 minutes, and immediately when the machine wakes.

## Documentation

- [How it works](docs/how-it-works.md) — data sources, quota invariants, status-line bridge, pace
  marker, demo mode, privacy.
- [Development](docs/development.md) — running, building the `.app`, project structure, the window
  constraints worth knowing before touching it.

## Star history

<a href="https://star-history.com/#Endikk/Claudy&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=Endikk/Claudy&type=Date&theme=dark">
    <img src="https://api.star-history.com/svg?repos=Endikk/Claudy&type=Date" width="620" alt="Star history">
  </picture>
</a>

## Branches

| Branch | Role |
|---|---|
| `main` | Stable. What is released and what Homebrew installs. |
| `develop` | The moving one. Every feature lands here first and lives here until it has been used for real; `main` only ever receives what has held up. |

Open pull requests against `develop`.

## Contributing

A bug, an idea, a figure that does not match claude.ai? Open an
[issue](https://github.com/Endikk/Claudy/issues) — a screenshot and
`~/Library/Application Support/Claudy/api.log` are welcome. PRs are open.

MIT, maintained by [@Endikk](https://github.com/Endikk).
