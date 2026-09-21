# Changelog

All notable changes to this project are documented here. Dates are release dates.

## Unreleased

### Fixed

- **Subagent and workflow usage was never counted.** Only the top-level transcript of each
  session was read, while Claude Code writes subagents to `<session>/subagents/**/agent-*.jsonl`.
  On an agent-heavy week that was more than half of the tokens, missing from the history, the
  splits and the gauges' local counts. Every transcript below `projects/` is now read.
- **One project showed up as several.** A project was the last folder of the directory the
  model was in, so a `cd` into `App` or `src` opened a new row and two unrelated `api` folders
  merged. It is now the Git repository holding that directory, worktrees included; a folder
  outside any repository (a scratchpad) goes to the repository its session worked in.
- **Shares ranked raw tokens.** Cache reads are nine tokens in ten and cost a tenth of an input
  token, and an Opus token costs five Haiku ones, so a background Haiku job outranked real work.
  Model and project shares, and the active model, are now weighted by each model's list price.
  Dated snapshots of one version (`claude-haiku-4-5-20251001`) merge into one row.

## 1.4.0 — 6 September 2026

Claude Code leaves servers running. This release lists them and closes them.

### Added

- **Ports tab.** Lists the TCP ports Claude Code left listening, orphaned ones included, and
  kills them one click at a time. A process is attributed to Claude only by the markers it
  inherited in its environment (`CLAUDECODE`, `CLAUDE_CODE_ENTRYPOINT`, `CLAUDE_PROJECT_DIR`),
  which survive the session that set them — so a server orphaned days ago is still recognised,
  and a `npm run dev` you started yourself is never listed. Container runtimes are never
  attributed: their listener is the runtime, not the container. Nothing is killed without a
  click, and killing re-checks the process identity first, so a reused PID is refused.

### Fixed

- **A five-digit port number wrapped across three lines.** Its column was pinned at 44 points,
  narrow enough that `37701` broke mid-number. The number no longer wraps and the column widens
  to fit it.
- **The header read "claudy" in lowercase.** It is the product's name and takes a capital.
- **The session state read "idle".** It now reads "inactive", which says the same thing without
  the jargon.

## 1.3.0 — 2 September 2026

The counter now shows the account's own figures, or nothing at all.

### Fixed

- **Every token refresh had been failing since 18 August.** Tokens are renewed at
  `platform.claude.com`, not at `console.anthropic.com`, which the app was still using. The
  refresh grant also now sends its `scope`; without it a renewed token loses `user:profile` and
  the API stops returning quotas altogether.
- **Silent fallback to an invented percentage.** When the account gave no quota the app filled the
  gap with the 90th percentile of local transcript windows. That was wrong by construction:
  Anthropic's response carries `limit_dollars: null` and `used_dollars: null`, so the quota is not
  a token tally and no local count can reproduce it. Gauges now read "—" behind an "offline" badge.
- **A stale reading past its reset time was served as current.** The window had reopened at zero
  since, making the figure wrong rather than merely old. Such windows are now dropped, and the
  whole reading is abandoned when none survives.
- **An expired borrowed token sent the card back to onboarding**, wiping a valid reading. The last
  known reading is now served, dated; onboarding returns only if there never was one.
- **A brief network drop froze the counter for five minutes.** Backoff now follows the nature of
  the fault: 30 s → 5 min for a transient network or server error, 5 → 15 → 30 → 60 min for a rate
  limit or a refused token, with `Retry-After` honoured throughout.
- **The refresh button could not break an ongoing backoff.** A user-initiated refresh now lifts it.
- **A gauge at 0 % or without a measurement still drew a coloured dot**, which read as consumption
  that did not exist.

### Changed

- **The OAuth token is borrowed from Claude Code, read-only.** Claude Code renews it on every
  launch and before every expiry, so it is always fresh and Claudy has nothing to refresh. The
  `refresh_token` is never read or spent — rotating it would invalidate Claude Code's own session.
  The read goes through `/usr/bin/security`, the binary that created the keychain item and which
  its ACL already trusts, so no macOS "confidential information" dialog appears. Claudy's own OAuth
  sign-in remains as a second choice and is abandoned on `invalid_grant`.
- **Polling every 3 minutes instead of every 60 seconds**, with a 60-second cache and the profile
  re-read only every 6 hours. The old rhythm produced cascades of HTTP 429.
- **The origin of the figures is always stated.** A badge reads "relay", "⟳" (last known reading,
  dated), "offline" or "demo", and hovering explains it in one sentence.
- **Token counts are labelled as local**: "12.4 M tokens on this machine" rather than an
  extrapolated "X of Y tokens". They never mix with the account percentage.
- **The interface, source comments and documentation are now in English.** A French README remains
  at [README.fr.md](README.fr.md).

### Added

- **Optional status-line bridge.** Claude Code receives its quota counters in the
  `anthropic-ratelimit-unified-*` headers of every API response. One status-line command relays
  them to Claudy: same values, no request, immune to rate limiting. Documented in the README.

### Removed

- The `claudy.limit.session`, `claudy.limit.weekly` and `claudy.limit.model` preferences, which
  only ever tuned the estimation mode that no longer exists.

### Verified

Against the live API, at three different values (23 %, 25 %, 39 %): session, weekly and per-model
gauges matched to the digit, with identical reset times.

## 1.2.2 — 17 August 2026

**Broken-glass effect removed.** The overload crack is gone: it read as a fake broken screen, out
of step with the rest of the card. Past 95 %, the red hairline remains the signal — discreet, kept
to the edge, never touching the content.

## 1.2.1 — 1 August 2026

**The crack moves behind the content.** At the 95 % threshold the card still splits, but the
fracture now lives in the background: not a single line crosses the figures or the labels. The card
stays fully legible at 100 % load.

**Fracture redrawn.** An impact in the top-right corner, a tight web around the point of impact,
three long fractures running into the body of the card — instead of a network of lines spread over
the whole surface. The effect is rendered in depth (displaced glass shard, blurred hollow, offset
bright edge) rather than in painted lines, and its opacity is capped: a signal caught out of the
corner of the eye, not a drawing that takes over the card. The red hairline follows the same
restraint.

**Animated README.** The still capture gives way to a moving demonstration.

## 1.2.0 — 1 August 2026

**Claudy's own Claude sign-in.** The app now obtains its own token through an OAuth sign-in in the
browser, stored in its own keychain item. It no longer reads Claude Code's secrets, so macOS stops
showing the "confidential information" warning. Sign out from the account card or the right-click
menu.

**Full-card onboarding.** With no session open, the card no longer shows estimated quotas: it
introduces Claudy and offers to sign in. No invented figures.

**Cracks past 95 %.** An impact and its fractures spread across the card, the hairline turns red,
and the intensity rises to 100 %.

**Position and gestures.**
- The card settles into the screen's physical bottom-right corner, 8 pt from the edges, on every
  launch and every size change.
- A click on the minimal strip expands it; a click on the header or the session block folds it back.
- It grows upward, so the interface stays fully visible.

**Miscellaneous.** French day initials on the sparkline (D L M M J V S). Dead code removed after a
symbol-by-symbol audit. SHA-256 digest pinned in the Homebrew cask.

## 1.1.0 — 31 July 2026

- Gauges wired to the account's **real quotas** (`api.anthropic.com/api/oauth/usage`): the same
  percentages and reset times as claude.ai.
- Account identity read from `/api/oauth/profile`.
- Autonomous token renewal, single retry on 401, exponential backoff, last known value kept on
  failure, log at `~/Library/Application Support/Claudy/api.log`.
- Application icon, one-command install script, Homebrew cask.
- Removed the "Sign out" and "Team stats" buttons, which did nothing.

## 1.0.0 — 31 July 2026

First release: floating widget, incremental transcript reading, response deduplication on
`(message.id, requestId)` — without which totals were inflated roughly 1.9-fold. Errors surfaced on
screen rather than hidden behind demo mode. Window recoverable after a display is unplugged, and a
refresh on wake.
