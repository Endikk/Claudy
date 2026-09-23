# "Ports" tab: killing the ports Claude Code leaves open

Date: 2026-09-03
Status: design approved, attribution spike conclusive, implementation not started
Scope: local only (no distribution, no release)

## Problem

Claude Code starts servers to test things (`npm run dev`, `bun`, `python -m http.server`)
and does not always shut them down. When the Claude session ends, launchd re-adopts these
processes: their ancestry disappears, nothing shows any more that they came from Claude, and they
hold a port for days.

Observed on the development machine on 2026-09-03, among 27 listeners:
`bun … claude-mem/worker-server`, port 37701, PPID 1, started 2 days earlier.

## Goal

A tab in the Claudy widget that lists the listening ports attributable to Claude Code
and lets the user kill them one by one. Nothing else. The widget remains a quota widget:
the tab is a clearly separate annex, not a second purpose.

## Decisions made

| Question | Decision | Rationale |
|---|---|---|
| Scope | Orphans included | Without them, the tool misses exactly the cases that cause trouble |
| Attribution | Inherited environment variables | Proven: survives orphaning, no state to maintain |
| UI surface | Segmented control in the card (`usage` / `ports`) | Stays in the widget, alert badge visible, no extra window |
| Kill policy | Manual, one click per row | Killing is irreversible; no automation |
| Engine | Scan inside Claudy | Claudy is already running; do not write to the user's Claude config |

## Attribution spike: results (2026-09-03)

`ps -Eww -p <pid>` exposes the environment of any process owned by the same user. Measurements:

| PID | Process | Markers |
|---|---|---|
| 46694 | `python -m http.server 4000`, started by Claude during a session | `CLAUDECODE=1` |
| 95778 | `bun … claude-mem/worker-server`, orphaned for 2 days | `CLAUDE_PROJECT_DIR=…` |
| 5771 | `next-server` port 3000 | none |
| 49057 | `npm run dev` | none |

Three conclusions that shape the design:

1. **The environment survives orphaning.** The 2-day-old worker remains attributable without
   any persistence. The registry considered at first is removed from the architecture.
2. **The machine's `next dev` and `npm run dev` do not come from Claude.** The `probable`
   heuristic based on `cwd`, planned for the first version, would have flagged them wrongly: it is
   removed. `CLAUDE_PROJECT_DIR` gives the project directly, without guessing.
3. Ancestry remains useful, but for another reason: identifying the **live** Claude
   session so that it is never killed.

Check to run early in the implementation: the same read from the GUI app, not
launched from a terminal. The kernel rule is "same uid", not "same session", so the
result is expected to be identical, but this gets verified instead of assumed.

## Verified constraints

- `ENABLE_APP_SANDBOX = NO` and `ENABLE_HARDENED_RUNTIME = NO` in `project.pbxproj`:
  reading the environment and sending signals is possible, no entitlement to add.
- Style precedent for subprocesses: `Services/ClaudeCodeCredentials.swift`
  (absolute executable path, explicit timeout, `DiagnosticLog` trace, never a shell).
- No test target exists in the project today.

## Architecture

| File | Role | ~lines |
|---|---|---|
| `Models/PortModels.swift` | `ListeningPort`, `PortAttribution`, `PortScanState` | 80 |
| `Services/ProcessEnvironment.swift` | `KERN_PROCARGS2` in Swift: argv skipped, env region isolated | 90 |
| `Services/ProcessTable.swift` | one `ps` pass, PPID tree, ancestor walk | 100 |
| `Services/PortScanner.swift` | `lsof`, join, attribution | 120 |
| `Services/PortReaper.swift` | kill behind guardrails, signal injected for tests | 90 |
| `ViewModels/PortsViewModel.swift` | published state, cadence, kill action | 110 |

New views: `Views/PortsView.swift`, `Views/Components/PortRow.swift`,
`Views/Components/TabSwitcher.swift`.
Modified views: `Views/FullView.swift` (header + switched body), `Theme/Theme.swift`
(two metrics). `ViewModels/UsageViewModel.swift` only gains the tab enum.

`ProcessEnvironment` reads `KERN_PROCARGS2` directly through `sysctl` rather than running one
`ps -E` per process: one syscall instead of a fork, and above all the environment region
is isolated cleanly (by skipping `argc` arguments) instead of being searched for in text where
a command line containing `CLAUDECODE=` would produce a false positive. `ps -Eww` remains
the fallback if `sysctl` fails.

### Data flow

```
tick (30 s in the background, 5 s with the tab visible, immediate on opening)
  └─ PortScanner.scan()                     off the main thread
       ├─ lsof -nP -iTCP -sTCP:LISTEN -a -u <uid> -F pcn
       ├─ ps -Ao pid=,ppid=,lstart=,args=   tree, to protect live sessions
       └─ ProcessEnvironment(pid) per candidate listener  → attribution
  └─ publication on the main thread
```

No persistence. The displayed age comes from `lstart`, read on every scan.

### Parsing

- `lsof -F pcn`: field output (`p<pid>`, `c<command>`, `n<address>`), not columns,
  which truncate and escape names (`Code\x20H` observed while probing). lsof also emits
  fields that were not requested, `f<fd>` in particular: the parser ignores any unknown field.
- `ps -Ao pid=,ppid=,lstart=,args=`: `lstart` takes exactly 5 tokens
  (`Thu Sep  3 19:10:26 2026`), so the split is deterministic: pid, ppid, 5 tokens, rest = args.

Both parsers are pure functions on `String`, testable against fixtures.

## Attribution

**`confirmed`**: the process environment carries at least one Claude Code marker
(`CLAUDECODE`, `CLAUDE_CODE_ENTRYPOINT` or `CLAUDE_PROJECT_DIR`). True for descendants
of a live session as well as for orphans of dead sessions.

**`orphan`**: `confirmed`, but no live `claude` ancestor. Shown in amber: this is the
main target of the tab.

**Nothing else is attributed.** No directory heuristic, no command
matching. A port without a marker does not appear in the list.

**Hard denylist.** For a port published by a container, the listener is the runtime, not the
Claude process: killing it would kill the whole runtime. OrbStack, Docker and
`com.docker.backend` are never attributable, whatever their markers.

## Interface

`TabSwitcher` in the `FullView` header: two segments `usage` / `ports`, with a numbered badge
on `ports` only when orphans exist. Width unchanged at 340, same
materials, no raw values: everything goes through `Theme`.

Port row: number in coral monospaced digits, command, `project · age` (the project
comes from `CLAUDE_PROJECT_DIR`), an amber `orphan` badge, a cross revealed on hover.

A carefully written empty state, since it is the most frequent one: "No port left open by Claude."

## Kill: guardrails

1. **Re-check before signalling**: `(pid, startedAt, port)` still identical to what is
   displayed. Otherwise, refuse: between the render and the click, the process may have died and its PID
   been reassigned to another one.
2. **Categorical refusals**: `pid <= 1`, Claudy's pid, any ancestor of Claudy, and any
   root process of a live Claude session.
3. `killpg(pgid, SIGTERM)` when the group is neither Claudy's nor 1, otherwise
   `kill(pid, SIGTERM)`.
4. Wait 3 s, polling every 100 ms, then `SIGKILL`, then a failure reported on the row.
5. "Kill all" only applies to orphans, behind a confirmation that lists the affected
   rows by name.

## Privacy

A process environment contains secrets. `ProcessEnvironment` never returns the
environment: it exposes a presence test for the three Claude keys and the value of
`CLAUDE_PROJECT_DIR` alone. Nothing is written to disk, nothing is logged.

The tab only reads the local process table and sends no network request. The README's
"no telemetry" promise holds and must be restated explicitly for this
feature.

## Errors

- `lsof` missing or a non-zero exit code: the tab shows `scan unavailable` with the
  reason, never a crash, trace in `DiagnosticLog`.
- `sysctl` refused: fall back to attribution by ancestry alone, with a visible note
  in the tab that orphans can no longer be detected in that case. No intermediate tier
  through `ps -Eww`: same kernel permissions as `sysctl`, one more fork, no gain.
- `EPERM` / `ESRCH` on kill: reason shown inline, on the affected row.

## Tests

The project has no test target: adding one is part of the scope.

- `ps` parser and `lsof -F` parser on fixture strings, unknown fields included;
- `KERN_PROCARGS2` splitting on a hand-built buffer: a command line containing
  `CLAUDECODE=1` must not produce an attribution;
- attribution on synthetic process trees, orphans and denylist included;
- reaper guardrails with an injected `SignalSending`.

No test sends a signal to a real process.

## Out of scope

Auto-kill at the end of a session, a LaunchAgent scanning while Claudy is closed, UDP and Unix
sockets, container ports. Each one will get its own ticket.
