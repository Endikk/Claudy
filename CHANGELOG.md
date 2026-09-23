# Changelog

All notable changes to this project are documented here. Dates are release dates.

## 1.5.4 (23 September 2026)

### Added

- **Enterprise accounts.** An Enterprise plan is billed on usage: no 5-hour or weekly window, just
  a monthly spend cap set by the organisation. Claudy took that answer for a failure and showed
  "—". The card now leads with the month's spend ("$46.31 of $500.00"), the reset date on the
  1st and the usual pace marker, and the laptop explodes when the cap is reached. The account
  card says "Enterprise" rather than an internal tier name.
- **Sign in and out from the menu bar.** The popover shows who is signed in with a "Sign out"
  button, and the right-click menu offers "Sign in to Claude…" or "Sign out of Claude". Signed
  out, the popover carries the whole sign-in, including the field for pasting the code when the
  browser cannot hand it back on its own.
- **Refresh also looks for a new Claudy.** Any refresh you ask for (the button, ⌘R, the
  right-click menu) checks GitHub for a new release too, so an update published since launch
  shows up without waiting for the daily check. Clicking again and again asks GitHub once a
  minute at most. A wait imposed by Anthropic's server is lifted once a minute at most too, so
  a held ⌘R or a burst of clicks cannot send a request each.

### Fixed

- **Output tokens were undercounted by about 40 %.** Claude Code writes one response over several
  lines, and the early ones carry the output count reached so far. Claudy kept the first line, so
  every day of the history, the model and project splits and the "7 days" total came out short.
  It now keeps the final count, including for a response it read while still being written, and
  a response copied into a resumed session counts once whatever order the files are read in.
- **No tokens at all on some Macs.** A `~/.claude/projects` folder moved to another disk behind a
  symbolic link read as empty. Claudy now follows the link, and also reads
  `~/.config/claude/projects`, where some Claude Code releases keep their transcripts.
- **Sign out now signs out.** Claudy only erased its own token, then picked Claude Code's up
  again at the next reading, so the button did nothing on most Macs. Claudy now stays signed out,
  across relaunches, until you sign back in. Claude Code itself stays signed in. Signing back in
  reuses Claude Code's session with no browser round trip when it has one.
- **⌘V pastes the sign-in code.** With no menu bar of its own, Claudy had no Edit menu, so text
  fields ignored ⌘C, ⌘V and ⌘A: the code could only be pasted with a right click.
- **Update could restart into the same version.** On its own, brew refreshes the Claudy tap once
  a day at most. A release out since then read as "the latest version is already installed",
  brew reported success, and Claudy restarted into the version it was already running, dot
  included. Update now runs `brew update` first, and if the version on disk has not changed it
  offers the Terminal instead of restarting.
- **A failed refresh blanked the gauges.** Clicking refresh while Anthropic was unreachable threw
  the last reading away, and the card fell to "—" instead of showing it as stale. The last
  reading now stays, dated, as it does when an automatic refresh fails.
- **Claudy stood still on some Macs.** The mascot only typed while the account reported a 5-hour
  window, so it froze whenever there was none to read: quota unavailable, or Claude Code billing
  another account such as an API key. It now types whenever Claude Code works on this Mac too.
- **A grey box around the card.** On a light wallpaper, the card's shadow was cut at the edge of
  its window and showed as a grey frame. The glass also turned grey on grey in dark mode over a
  light wallpaper, or the reverse. The shadow now fades out inside the window, and the glass uses
  a material that follows the wallpaper less.

### Changed

- **English only.** The sign-in screen still showed its waiting message in French; it now reads
  "Waiting for the browser…". The install and build scripts, the Homebrew cask and the remaining
  source comments are in English too. The French docs are gone: [README.fr.md](README.fr.md) is
  the one French page left, and it links to the English docs.

## 1.5.3 — 22 September 2026

### Added

- **Claudy tells you when a new version is out.** It checks the latest release at launch and
  once a day. A coral dot marks the menu bar icon and the widget, and a line above the footer
  offers the update. In the menu bar, a bubble drops from the icon once per version, and Claudy
  waves hello until you open it. Switching between the widget and the menu bar waves again.
- **Update in one click.** Installed with Homebrew, Update runs the upgrade in the background:
  Claudy closes, and the new version opens a moment later. If brew cannot finish, the button
  runs the same command in Terminal so you can see why. Without Homebrew, it opens the release
  page.

## 1.5.2 — 22 September 2026

### Added

- **Claudy at 100 %.** When the 5-hour session or the weekly limit fills up, Claudy types
  frantically, the laptop sparks, smokes and explodes, and Claudy is left ashen with crossed-out
  eyes while grey smoke rises from the charred keyboard. The explosion plays once, while the
  quota fills with the widget on screen; opening Claudy on a full quota shows the dead state
  directly. Claudy comes back to life when the quota frees up. The per-model window does not
  trigger it, since another model still answers. Same in the menu bar, and a still frame when
  "Reduce motion" is on.

## 1.5.1 — 21 September 2026

### Fixed

- **The card could no longer be dragged.** Moving the window was left to the view under the
  pointer, and since the animated mascot arrived the card stayed put. The window now follows
  the drag itself, from anywhere on the card. A press that moves less than three points is still
  a click, and dropping the card does not switch its mode. Changing mode still sends it back to
  the bottom-right corner.

## 1.5.0 — 21 September 2026

Claudy can now live in the menu bar, and the numbers it shows count every agent.

### Added

- **Menu bar mode.** Right click the widget, then "Show in menu bar": the card leaves the
  desktop and Claudy sits next to the clock, with its mascot and the 5-hour percentage. Left
  click opens a popover built on charts: the three quotas as rings with their pace, seven days
  as bars, and the week split by model. Hovering a bar or a legend row highlights that model.
  Details and ports stay in the widget.
- **A mascot.** The Claude mark gives way to Claudy in pixel art, typing at a laptop while a
  session is active and resting otherwise. It follows the session tint and stops moving when
  "Reduce motion" is on.
- **Hover on the 7-day chart.** Pointing at a day shows its name, its tokens and its share of
  the week.

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
