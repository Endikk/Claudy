# How Claudy works

[← README](../README.md)

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

Without one, transcripts are read from `~/.claude/projects` and also from
`~/.config/claude/projects` (`$XDG_CONFIG_HOME/claude/projects` when that variable is set), the
location some Claude Code releases wrote to. `ccusage` reads both for the same reason. A response
found in both folders counts once. A `projects` folder moved to another disk behind a symbolic
link is followed.

Counted tokens are the sum of the four counters (`input`, `output`, `cache_creation`,
`cache_read`). Cache reads dominate: a busy week routinely passes a billion tokens, hence the "B"
unit in the interface.

Claude Code writes the same response across several transcript lines, one per content block.
Claudy **deduplicates** on `(message.id, requestId)`, the key `ccusage` uses too. Without it,
totals would be inflated roughly twofold.

The copies are not identical. The early lines carry the output count reached so far, and only the
last one carries the final count. Claudy keeps the largest copy, which is the final one. Keeping
the first copy, as earlier versions did, undercounted output tokens by about 40 %. A resumed
session (`--resume`) copies earlier responses into a new transcript: those are deduplicated the
same way, across files, whatever order the disk lists them in.

A project's name comes from the line's `cwd` field, never from the transcript folder name, which
is a transliteration that loses accents and separators (`~/Documents/Naïve/My-App` becomes
`-Users-…-Documents-Na-ve-My-App`).

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

### Enterprise: a monthly spend cap

Enterprise plans are billed on usage. They have no 5-hour or weekly window: the API answers
`five_hour: null` and `seven_day: null`, and the quota is a monthly spend cap set by the
organisation, carried in a `spend` block:

```json
"spend": {
  "used":  { "amount_minor": 4631,  "currency": "USD", "exponent": 2 },
  "limit": { "amount_minor": 50000, "currency": "USD", "exponent": 2 }
}
```

`4631` at exponent 2 is $46.31. When `spend` is missing, Claudy reads `extra_usage`
(`used_credits`, `monthly_limit`, `decimal_places`), the older shape of the same budget.

On such an account the card leads with **Spend · month**: the percentage worked out from the two
amounts (the API's own `percent` is rounded), the amounts themselves ("$46.31 of $500.00") and the
reset date. Caps reset at 00:00 UTC on the 1st; the API does not send that instant, so it is
derived from the rule. The pace marker reads the share of the month elapsed. The weekly and
per-model columns step aside, having no quota to show. At the cap, the laptop explodes as it does
at 100 % of a session.

Pro and Max carry a `spend` block too: their extra-usage cap. Claudy only reads it when both
windows are absent, so it never hides a live session.

An account with no cap, or with spending turned off, has no quota at all. The gauges then show
"—", as for any missing measurement.

### Sessions and agents

The Sessions tab lists every Claude Code session open on this Mac and the subagents each one runs,
from files Claude Code keeps anyway; nothing is installed in Claude Code for it:

- `~/.claude/sessions/<pid>.json`, one per open Claude Code process, gives each session its id,
  name and status, rewritten as it changes: `busy` while it works, `idle` at its prompt, `waiting`
  when it asks the user something, with what it waits for in `waitingFor` ("permission prompt",
  "input needed"). A file whose process is gone belongs to a closed session and is ignored.
- `<projects>/<folder>/<session>.jsonl`, the session's transcript, for the last thing the user
  asked it. Claude Code writes it down itself in `last-prompt` lines; Claudy reads the transcript's
  tail once, then only what is appended, and keeps nothing else from it.
- `<projects>/<folder>/<session>/subagents/agent-<id>.meta.json` holds what an agent was asked
  and, once it is over, `finished`.
- `agent-<id>.jsonl` beside it is the agent's transcript. Claudy reads only its tool calls (the
  tool and the file it names), from a cursor per file, as it does for usage.

Sessions waiting for the user come first, the longest wait on top, in an amber row that names
what they wait for and offers "Open": it brings forward the app the session runs in, found up its
process tree (Terminal, iTerm, Ghostty, VS Code, Cursor). Claudy activates that app; it cannot
pick one window among several, so with two VS Code windows open the last one used comes forward.
Then come the sessions at work, then those at rest with how long they have been idle. Sessions a
program drives through the Agent SDK (`entrypoint` `sdk-cli`, `sdk-ts`) are listed only while they
run agents: nobody sits at them.

A click unfolds a session: its folder, its app, when it opened, its agent count, the last thing
asked of it, "Open <app>", and "Interrupt" while it works or waits. Agents have no process of
their own, so there is nothing narrower to stop: after a confirmation that names the session,
Claudy sends the session's Claude Code process the signal Ctrl+C sends in its terminal
(`SIGINT`). The turn stops and every agent of that session with it; the session itself stays
open, at its prompt or mid-turn. Claude Code then marks the agents finished, so they show as
done. A command an agent had already started runs to its end on its own. Before the signal goes
out, the pid is checked again against the start time the session file records: a pid reused by
another process after a crash is never signalled.

Each agent sits under its session and shows what it was asked, for how long it has run, where it
is and its track: its tool calls over the last ten minutes, one bar per fifteen seconds, writes
in coral (the header carries the legend). Each agent's Claudy has its own colour, kept while it
runs; it types while the agent works and turns grey after a minute of silence. Three minutes of
silence are called out on the right, in amber ("silent 4 min"): a permission nobody answered, a
hung tool. A finished agent stays ten minutes, marked done with the number of files it wrote; an
unfinished one silent for thirty minutes is taken as interrupted. No file says how far along an
agent is, so no percentage is shown. A click unfolds an agent: its number of calls and start
time, the files it wrote, its last three calls.

The menu bar popover and the open island put the waiting sessions first, then the agents in
short, four lines, with the way to the widget past that. The menu bar item adds an amber raised
hand while a session waits, then the lead agent's Claudy and the count after the figure. The
notch at rest puts the count in the left ear in the lead agent's colour, or, while a session
waits, a raised hand on glass turned amber; a click on the ears opens that session's app.

### MCP servers left behind

Claude Code runs MCP servers as child processes that talk over their standard input, with no
port, so the ports list never saw them. When a session ends badly they stay behind, adopted by
launchd, often holding hundreds of megabytes each. The Ports tab lists them under the ports, with
the memory each tree holds and the total, and kills them like an orphaned port.

A process is listed when all of this holds:

- it is yours, its command line names an MCP server (`chrome-devtools-mcp`, `mcp-server-fetch`,
  `@modelcontextprotocol/...`), and its binary is not inside an app bundle;
- launchd adopted it: whatever started it is gone;
- its environment carries Claude Code's markers (`CLAUDECODE`, `CLAUDE_PROJECT_DIR`), and its
  `CLAUDE_CODE_SESSION_ID`, when it has one, names no open session;
- no Claude Code process sits above it, and it does not hold a port already listed.

Only processes that pass the cheap checks get their environment read, and nothing but those
three markers is kept from it: an environment holds tokens. A daemon a plugin keeps on purpose,
and the servers it runs itself, are not listed while that daemon lives.

A kill goes to the whole tree, `SIGTERM` then `SIGKILL`, after checking again that the process is
the one listed (its start time) and that no live Claude Code sits above it. A tree is signalled
through its process group only when the server leads that group: otherwise the dead session's
group could hold something else.

### Notifications

Claudy posts a macOS notification when something deserves a look while the widget is out of
sight. Each kind has its own switch under Notifications in the right-click menu:

| Kind | When | Default |
|---|---|---|
| Session at 80% | The 5-hour session crosses 80 %, once per window | on |
| Limit before the reset | At the pace so far, the session fills more than ten minutes before it resets; said once per window, from 50 % on | on |
| Session back | A session window seen full has reset | on |
| A session waits for you | A session has waited twenty seconds for a permission or an answer; the banner is taken back once it no longer waits | on |
| An agent falls silent | An agent has said nothing for three minutes | on |
| An agent is done | An agent seen at work finishes | off |

A click on a banner about a session brings its app forward. The first reading after launch only
sets the scene: a threshold already crossed then is not announced. macOS asks for permission the
first time Claudy has something to say, not at launch. If notifications are turned off for Claudy
in System Settings, the submenu says so and leads there.

### Keyboard shortcut

⌃⌥C, from any app, shows or hides Claudy where it stands: the card comes and goes, the menu bar
item's popover opens and closes, the island opens and closes. It goes through Carbon's hot keys,
which need no accessibility permission. When another app already holds ⌃⌥C, the menu says so
rather than promising it. ⌥⌘C was the obvious pick, but the Finder copies a file's path with it.

### CSV export

"Export usage as CSV…" in the right-click menu writes the last seven days from the local
transcripts, one line per hour, project and model:

```
hour,project,model,input_tokens,output_tokens,cache_read_tokens,cache_write_tokens,list_price_usd
2026-11-10T09:00,Claudy,claude-opus-5-5,18204,9310,2210440,86020,4.1200
```

`list_price_usd` is what those tokens would cost at Anthropic's list prices, the weight Claudy
already ranks models and projects by. It is not a bill: a subscription is not charged per token.
Hours are local. A field that a spreadsheet would read as a formula is prefixed with `'`.

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

## Privacy

The network is used only to talk to Anthropic: `usage` (quotas), `profile` (account identity), and
— when you use Claudy's own sign-in — the OAuth flow in your browser plus the standard token
renewal. Nothing else is sent: no telemetry, no conversation content, no third-party server.

By default Claudy borrows Claude Code's token **read-only**, through `/usr/bin/security` (or from
`.credentials.json` when Claude Code keeps it there), and never refreshes or writes it back; its
`refresh_token` is not even kept in memory. If you sign in through
Claudy itself, that token lives in a keychain item **of its own** ("Claudy-credentials"), and
signing out deletes it. Offline, the app keeps working locally and states that its quotas are
unavailable. The sandbox is disabled solely to allow reading `~/.claude`.
