# Notch island: Claudy around the MacBook notch

Date: 2026-09-29
Status: design approved, implementation not started
Scope: a third placement next to the floating widget and the menu bar item

## Problem

Claudy lives in one of two places today: a floating card on the desktop, or an item in the menu
bar. On a MacBook with a notch, the top centre of the screen is dead space, and it is the one spot
the eye crosses all day without the menu bar being in the way. A full-screen app hides the menu
bar item and usually covers the card, so the quota drops out of sight exactly when working heads
down.

## Goal

A "notch" placement, offered only on a Mac that has a notch. At rest, Claudy wraps the notch like
a Dynamic Island: the mascot on the left of the notch, the session percentage on its right. Hover
it and it drops open with the content of the menu bar popover. The user picks it with a right
click, from the same menus that already switch between the widget and the menu bar.

## Decisions made

| Question | Decision | Rationale |
|---|---|---|
| Resting shape | Two "ears" hugging the notch: mascot left, percentage right | Reads at a glance, stays the height of the notch |
| Opening | On hover, after 0.15 s; closes 0.3 s after the pointer leaves | Dynamic Island feel; the delay spares a pointer heading for the menu bar |
| Expanded content | The menu bar popover (`MenuBarView`), dark scheme, black ground | Already designed as a transient glance: rings, week, models, account, update |
| Full-screen apps | The island stays visible | The notch is a black band in full screen anyway, and this is where the menu bar item fails |
| Placements at once | One, as today | Same rule as widget vs menu bar: never the same figures twice |
| No notched screen | Fall back to the menu bar item, keep the user's choice | The island comes back by itself with the screen (lid reopened) |
| Build | Native AppKit panel, no dependency | Claudy has no package dependency; DynamicNotchKit targets transient notifications, not a resident island |

## Verified constraints

- Deployment target is macOS 13. `NSScreen.safeAreaInsets` and
  `NSScreen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea` exist since macOS 12.
- Measured on the development Mac (Mac16,7, built-in 1728 × 1117 points) on 2026-09-29:
  `safeAreaInsets.top` = 32, left area `(0, 1085, 771.5, 32)`, right area
  `(956.5, 1085, 771.5, 32)`. The notch therefore spans x 771.5 to 956.5: 185 points wide,
  32 high, centred on the screen.
- The project has no Swift package dependency (`XCRemoteSwiftPackageReference` count: 0).
- Hosting the tests, Claudy draws no window: SwiftUI windows abort on GitHub's Intel runners.
  Everything tested must be pure logic.
- `ClaudyTyping` already honours Reduce Motion (`accessibilityReduceMotion`), and so does
  `ClaudyWaving`.

## Architecture

### Placement model

`UsageViewModel.isInMenuBar: Bool` becomes:

```swift
enum Placement: String {
    case widget, menuBar, notch
}
```

- Persisted under a new key, `claudy.placement`. When that key is absent, the legacy
  `claudy.inMenuBar` decides once: `true` gives `.menuBar`, anything else `.widget`. A user who
  kept Claudy in the menu bar finds it there after the update.
- `Placement.effective(hasNotch:)` returns `.menuBar` for `.notch` when no screen has a notch,
  and the placement itself otherwise. The chosen placement is never overwritten by the fallback.
- `UsageViewModel.place(_:)` replaces `toggleMenuBar()`. It closes the profile popup, as the
  toggle does today.
- `UsageViewModel.hasNotchedScreen: Bool` (published) is kept up to date by the app delegate, so
  the SwiftUI context menu can offer or hide "Show in notch".

### Components

| File | Role |
|---|---|
| `Models/Placement.swift` | The enum, its migration from the legacy key, `effective(hasNotch:)`, and `offered(hasNotch:)`: the placements a menu proposes, the current one excluded, `.notch` only with a notched screen |
| `Services/NotchGeometry.swift` | Finds the notched screen and the notch rectangle from plain values (`frame`, `safeAreaInsets.top`, the two auxiliary areas). A screen with a top inset but no auxiliary areas counts as having no notch |
| `App/NotchLayout.swift` | Pure frame maths: the resting frame (notch plus two ears) and the expanded frame, both centred on the notch, glued to the top edge and kept inside the screen |
| `App/NotchPanel.swift` | Borderless, non-activating `NSPanel`; level `.mainMenu + 3`, above the menu bar; `.canJoinAllSpaces`, `.stationary`, `.fullScreenAuxiliary`, `.ignoresCycle`; clear, no system shadow |
| `App/NotchController.swift` | Shows and hides the island, owns the hover state and its two timers, sizes the panel, builds its right-click menu |
| `Views/NotchView.swift` | The black shape, the two ears at rest, `MenuBarView` below them once open |

Existing files touched:

- `AppDelegate.placeWidget` switches over the effective placement: exactly one of the card, the
  menu bar item and the island is shown. The existing screen-change observer (0.5 s after
  `didChangeScreenParametersNotification`) also recomputes `hasNotchedScreen` and the effective
  placement.
- `MenuBarController.showMenu` and `RootView.menu` list `Placement.offered(hasNotch:)` instead of
  their hard-coded "Show floating widget" / "Show in menu bar" entries.
- `MenuBarView`'s footer button "Floating widget" calls `place(.widget)`.
- The right-click menu of the menu bar item moves into a small shared builder, reused by the
  island: Refresh, the offered placements, Sign in / Sign out, Quit.

### Data flow

```
viewModel.$placement ─┐
                      ├─> effective placement ─> AppDelegate.placeWidget ─> card | menu bar item | island
screen changes ───────┘         (hasNotchedScreen)

viewModel.$snapshot ─> NotchView (ears + MenuBarView), through the environment, as for the card
```

`updates.greetAgain()` keeps firing when the user changes the placement, as it does today when
moving between the card and the menu bar.

## Interface

### At rest

A pure black shape, exactly the notch's height, extending it on both sides, bottom corners
rounded. Black is chosen to merge with the physical notch.

- Left ear: `ClaudyTyping` (or `ClaudyWaving` while an update greets), tinted like the menu bar
  icon, so the typing, explosion and ash states carry over unchanged.
- Right ear: the lead percentage (`snapshot.primary`), monospaced digits, white; the update dot
  or the error dot beside it when there is one.
- Each ear is about as wide as the notch is high. Starting value 48 points, tuned on the device.
  The ears overlap the menu bar by that much on each side: the end of a long app menu on the
  left, the first status item on the right. Other notch apps make the same trade.

### Open

- Hovering the island for 0.15 s opens it. The shape grows downward and `MenuBarView` appears
  under the ears, in the dark colour scheme on the black ground.
- Width: the larger of the resting width and `Theme.Metric.menuBarWidth` plus padding. Height:
  measured from the SwiftUI content through a preference key, since the popover's height varies
  (signed out, model split, update row).
- It closes 0.3 s after the pointer leaves the open shape, except while a text field in it is
  being edited (the manual sign-in code), in which case it waits for the edit to end.
- Opening counts as opening Claudy: `updates.acknowledgeGreeting()`, as a click on the card does.
- No update bubble in notch mode. The waving mascot and the dot announce the version, and the
  update row sits in the open panel.

### Window size follows the shape

The panel is resized to the resting frame when closed, so a click just below the notch reaches
the app underneath. On opening, the panel takes the expanded frame first, then the shape animates
inside it. On closing, the shape animates back first, then the panel shrinks.

Hover is tracked with an `NSTrackingArea` (`.activeAlways`, `.mouseEnteredAndExited`,
`.inVisibleRect`) on the hosting view, so it works whether or not the panel is key.

### Right click on the island

Refresh, Show in menu bar, Show floating widget, Sign in / Sign out, Quit.

### Motion

The opening uses `Theme.Motion.popup`. With Reduce Motion on, the island opens and closes without
the spring, and the mascot holds still, as it already does in the widget.

## Errors and edge cases

| Situation | Behaviour |
|---|---|
| Notch chosen, no notched screen (lid closed on an external display) | Menu bar item shown; the island returns when the screen does |
| Built-in screen is not the main one | The island stays on the built-in screen |
| Top inset present but auxiliary areas missing | Treated as no notch |
| Resolution change ("More space" / "Larger text") | Recomputed on the screen-change notification; the notch rectangle is re-read |
| Full-screen app | Island stays visible (`.fullScreenAuxiliary`, level above the menu bar) |
| Menu bar set to hide automatically | Island stays visible |

## Tests

Written first, pure logic only (see the constraint on test windows):

- `NotchGeometryTests`: 16" and 14" notched screens, a screen without a notch, an external main
  screen with the built-in one second, a top inset without auxiliary areas.
- `PlacementTests`: migration from `claudy.inMenuBar` true, false and absent; the new key wins
  over the legacy one; `effective(hasNotch:)`; `offered(hasNotch:)` for each placement, with and
  without a notch.
- `NotchLayoutTests`: resting and expanded frames centred on the notch, touching the top edge,
  never outside the screen, expanded never narrower than resting.
- The existing `MainMenuTests.testTestHostShowsNoCard` extended: no `NotchPanel` either.

By hand on the development Mac, with screenshots: switching by right click from the card, from the
menu bar item and from the island; hover open and close; a click just under the notch reaching the
app below; a full-screen app; Reduce Motion; the fallback when the notched screen goes away if an
external display is available. Then `./Scripts/preflight.sh` in full.

## Out of scope

- Live Activities style events (a session ending, a quota reset) popping the island open.
- Opening on click instead of hover, or a pinned-open mode.
- The Ports tab in the island.
- A floating pill for Macs without a notch.

## Revision (2026-09-29): the island's own open view

After trying the popover inside the island, the open state gets a view of its own,
`NotchActivityView`, laid out for the notch: wide and low (440 points), like a Live Activity.

- Round the notch, as the Dynamic Island round the camera: the mascot on its left and the session
  percentage on its right, each a short flight from its ear; the active model just below it.
- Across the full width: the session's bar with its pace marker, the distance from the pace and
  the reset, then the weekly and per-model quotas side by side; on a plan billed on usage, the
  money spent instead.
- When relevant: the update row, the error line, or the sign-in controls.

The menu bar item's popover is unchanged. The open state casts the card's shadow on its sides and
below; at rest the ears keep none.

The island is no longer black, at rest or open: it wears the card's glass, glow and hairline. On
the transparent menu bar of recent macOS versions, black ears read as blocks set on the
wallpaper. Only the notch itself stays black.
Its top corners flare into the screen's edge through a small concave shoulder (8 points), as the
notch's own corners do, rather than meeting it square.

