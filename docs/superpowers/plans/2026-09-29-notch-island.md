# Notch island Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a third placement for Claudy on Macs with a notch: two ears around the notch at rest, the menu bar popover underneath on hover, chosen from the right-click menus.

**Architecture:** `Placement` (widget, menuBar, notch) replaces the `isInMenuBar` flag, with a pure `effective(hasNotch:)` that falls back to the menu bar when no screen has a notch. Pure value types find the notch (`NotchGeometry`), compute the window frames (`NotchLayout`) and time the hover (`NotchHover`); a thin `NotchController` glues them to a borderless `NotchPanel` hosting `NotchView`. One shared `ClaudyMenu` builds the right-click menu of the menu bar item and of the island.

**Tech Stack:** Swift 5 language mode, AppKit + SwiftUI, XCTest, Xcode 16+ synchronised groups (a new `.swift` file in `Claudy/` or `ClaudyTests/` needs no project edit).

**Spec:** `docs/superpowers/specs/2026-09-29-notch-island-design.md`

## Global Constraints

- Deployment target macOS 13. APIs used: `NSScreen.safeAreaInsets`, `auxiliaryTopLeftArea`, `auxiliaryTopRightArea` (macOS 12+), `NSHostingView.sizingOptions` (macOS 13+).
- No Swift package dependency.
- Everything in the repo is English (UI strings, comments, docs, commit messages). `README.fr.md` is the only French file and stays in sync with `README.md`.
- No em dash in new comments, docs or UI copy.
- Tests draw no window (SwiftUI windows abort on GitHub's Intel runners) and never write `UserDefaults.standard`: the test host is the app itself (`com.claudy.Claudy`) and shares the user's real preferences.
- Timings: open after 0.15 s of hover, close 0.3 s after the pointer leaves. Ear width: 48 points. Panel level: `.mainMenu + 3`. Collection behaviour: `.canJoinAllSpaces`, `.stationary`, `.fullScreenAuxiliary`, `.ignoresCycle`.
- Work on branch `feat/notch-island` (created off `develop`). Commit messages: `type: description`, ending with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.
- Test command for one class: `xcodebuild test -project Claudy.xcodeproj -scheme Claudy -destination 'platform=macOS' -only-testing:ClaudyTests/<ClassName> 2>&1 | tail -25`. Full suite: same without `-only-testing`.

## Review Focus

1. A pointer crossing the ears on its way to the menu bar: the island stays shut. Pinned in Task 3 (`testAPointerCrossingOnItsWayToTheMenuBarLeavesItShut`).
2. Content growing while open (update row, sign-in controls appearing): the window grows at once and never clips the shape; shrinking waits for the animation. Pinned in Task 2 (`testGrowingTakesTheLargerFrameAtOnce`, `testShrinkingWaitsForTheShapeToClose`).
3. The built-in screen is not the main one and sits left of an external display (negative x): the island lands on the built-in screen, in global coordinates. Pinned in Task 1 (`testTheBuiltInScreenIsFoundBehindAnExternalMainScreen`) and Task 2 (`testOnASecondScreenTheFramesUseGlobalCoordinates`).
4. The island hidden while open or while an opening is pending (placement changed from its own menu, lid closed): it comes back closed with nothing pending. Pinned in Task 3 (`testResetCancelsAPendingOpen`, `testResetClosesWithoutCallingClose`).
5. Notch chosen, notched screen gone: the menu bar item shown in its place offers only the widget, never "Show in menu bar". Pinned in Task 4 (`testANotchChoiceShownInTheMenuBarOffersOnlyTheWidget`).

---

### Task 1: Find the notch

**Files:**
- Create: `Claudy/Services/NotchGeometry.swift`
- Test: `ClaudyTests/NotchGeometryTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct ScreenMetrics: Equatable { var frame: CGRect; var safeAreaTop: CGFloat; var leftAreaWidth: CGFloat?; var rightAreaWidth: CGFloat? }` plus `init(_ screen: NSScreen)`.
  - `struct NotchGeometry: Equatable { let screenFrame: CGRect; let notch: CGRect; init?(_ screen: ScreenMetrics); static func find(in: [ScreenMetrics]) -> NotchGeometry?; static func current() -> NotchGeometry? }`.

- [ ] **Step 1: Write the failing test**

`ClaudyTests/NotchGeometryTests.swift`:

```swift
import XCTest
@testable import Claudy

/// The notch is what macOS leaves between the two usable parts of the menu bar. Plain values in,
/// so none of this needs a notched Mac.
final class NotchGeometryTests: XCTestCase {

    /// Measured on a 16-inch MacBook Pro (Mac16,7) at its default size, on 2026-09-29.
    private let builtIn = ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
        safeAreaTop: 32,
        leftAreaWidth: 771.5,
        rightAreaWidth: 771.5
    )

    private let external = ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
        safeAreaTop: 0,
        leftAreaWidth: nil,
        rightAreaWidth: nil
    )

    func testTheNotchSitsBetweenTheTwoUsableAreas() throws {
        let geometry = try XCTUnwrap(NotchGeometry(builtIn))

        XCTAssertEqual(geometry.notch, CGRect(x: 771.5, y: 1085, width: 185, height: 32))
        XCTAssertEqual(geometry.screenFrame, builtIn.frame)
    }

    func testAScreenWithoutTopInsetHasNoNotch() {
        XCTAssertNil(NotchGeometry(external))
    }

    func testAnInsetWithoutUsableAreasIsNotANotch() {
        var odd = builtIn
        odd.leftAreaWidth = nil
        odd.rightAreaWidth = nil

        XCTAssertNil(NotchGeometry(odd))
    }

    func testAreasCoveringTheWholeWidthLeaveNoNotch() {
        var full = builtIn
        full.leftAreaWidth = 864
        full.rightAreaWidth = 864

        XCTAssertNil(NotchGeometry(full))
    }

    func testTheBuiltInScreenIsFoundBehindAnExternalMainScreen() {
        var leftOfMain = builtIn
        leftOfMain.frame = CGRect(x: -1728, y: 0, width: 1728, height: 1117)

        let geometry = NotchGeometry.find(in: [external, leftOfMain])

        XCTAssertEqual(geometry?.notch, CGRect(x: -956.5, y: 1085, width: 185, height: 32))
        XCTAssertEqual(geometry?.screenFrame, leftOfMain.frame)
    }

    func testWithoutANotchedScreenNothingIsFound() {
        XCTAssertNil(NotchGeometry.find(in: [external]))
        XCTAssertNil(NotchGeometry.find(in: []))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Claudy.xcodeproj -scheme Claudy -destination 'platform=macOS' -only-testing:ClaudyTests/NotchGeometryTests 2>&1 | tail -25`
Expected: build fails with `cannot find 'ScreenMetrics' in scope`, then `** TEST FAILED **`.

- [ ] **Step 3: Write minimal implementation**

`Claudy/Services/NotchGeometry.swift`:

```swift
import AppKit

/// What macOS says about the top edge of one screen, as plain values.
struct ScreenMetrics: Equatable {
    var frame: CGRect
    /// `safeAreaInsets.top`: the notch's height, zero on a screen without one.
    var safeAreaTop: CGFloat
    /// Width of the menu bar left usable on each side of the notch.
    var leftAreaWidth: CGFloat?
    var rightAreaWidth: CGFloat?
}

extension ScreenMetrics {
    init(_ screen: NSScreen) {
        self.init(
            frame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            leftAreaWidth: screen.auxiliaryTopLeftArea?.width,
            rightAreaWidth: screen.auxiliaryTopRightArea?.width
        )
    }
}

/// The notch of a screen and the screen it sits on, in global screen coordinates.
struct NotchGeometry: Equatable {
    let screenFrame: CGRect
    let notch: CGRect

    /// `nil` for a screen without a notch. The notch is what the two usable areas leave between
    /// them. Only their widths are used, so the result does not depend on which coordinate space
    /// macOS reports the areas in.
    init?(_ screen: ScreenMetrics) {
        guard screen.safeAreaTop > 0,
              let left = screen.leftAreaWidth,
              let right = screen.rightAreaWidth else { return nil }
        let width = screen.frame.width - left - right
        guard width > 0 else { return nil }
        screenFrame = screen.frame
        notch = CGRect(
            x: screen.frame.minX + left,
            y: screen.frame.maxY - screen.safeAreaTop,
            width: width,
            height: screen.safeAreaTop
        )
    }

    /// The first notched screen of the list. Only a MacBook's built-in display has one, whether or
    /// not it is the main screen.
    static func find(in screens: [ScreenMetrics]) -> NotchGeometry? {
        screens.lazy.compactMap { NotchGeometry($0) }.first
    }

    static func current() -> NotchGeometry? {
        find(in: NSScreen.screens.map(ScreenMetrics.init))
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project Claudy.xcodeproj -scheme Claudy -destination 'platform=macOS' -only-testing:ClaudyTests/NotchGeometryTests 2>&1 | tail -25`
Expected: `Executed 6 tests, with 0 failures`, `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Claudy/Services/NotchGeometry.swift ClaudyTests/NotchGeometryTests.swift
git commit -m "feat: find the notch from what macOS reports about each screen" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Frame the island

**Files:**
- Create: `Claudy/App/NotchLayout.swift`
- Test: `ClaudyTests/NotchLayoutTests.swift`

**Interfaces:**
- Consumes: `NotchGeometry` (Task 1), its `init?(_ screen: ScreenMetrics)`.
- Produces: `struct NotchLayout: Equatable { let geometry: NotchGeometry; static let earWidth: CGFloat /* 48 */; var restingSize: CGSize; var restingFrame: CGRect; func frame(for size: CGSize) -> CGRect; static func step(from current: CGRect, to target: CGRect) -> (now: CGRect, settle: CGRect) }`.

- [ ] **Step 1: Write the failing test**

`ClaudyTests/NotchLayoutTests.swift`:

```swift
import XCTest
@testable import Claudy

/// The island's window hangs from the top of the notched screen, centred on the notch, and never
/// leaves the screen. It grows at once and shrinks late, so the animated shape is never cut.
final class NotchLayoutTests: XCTestCase {

    private func geometry(
        frame: CGRect = CGRect(x: 0, y: 0, width: 1728, height: 1117),
        left: CGFloat = 771.5,
        right: CGFloat = 771.5
    ) throws -> NotchGeometry {
        try XCTUnwrap(NotchGeometry(ScreenMetrics(
            frame: frame, safeAreaTop: 32, leftAreaWidth: left, rightAreaWidth: right
        )))
    }

    func testAtRestTheEarsFlankTheNotch() throws {
        let layout = NotchLayout(geometry: try geometry())

        XCTAssertEqual(layout.restingSize, CGSize(width: 185 + 2 * 48, height: 32))
        XCTAssertEqual(layout.restingFrame, CGRect(x: 723.5, y: 1085, width: 281, height: 32))
    }

    func testOpenTheShapeHangsFromTheTopCentredOnTheNotch() throws {
        let layout = NotchLayout(geometry: try geometry())

        let frame = layout.frame(for: CGSize(width: 290, height: 400))

        // The notch's centre is x = 864.
        XCTAssertEqual(frame, CGRect(x: 719, y: 717, width: 290, height: 400))
    }

    func testTheFrameNeverLeavesTheScreen() throws {
        let small = CGRect(x: 0, y: 0, width: 400, height: 300)
        let nearLeft = NotchLayout(geometry: try geometry(frame: small, left: 10, right: 200))
        let nearRight = NotchLayout(geometry: try geometry(frame: small, left: 200, right: 10))
        let tall = CGSize(width: 290, height: 400)

        XCTAssertEqual(nearLeft.frame(for: tall), CGRect(x: 0, y: 0, width: 290, height: 300))
        XCTAssertEqual(nearRight.frame(for: tall), CGRect(x: 110, y: 0, width: 290, height: 300))
    }

    func testOnASecondScreenTheFramesUseGlobalCoordinates() throws {
        let screen = CGRect(x: -1728, y: 200, width: 1728, height: 1117)
        let layout = NotchLayout(geometry: try geometry(frame: screen))

        XCTAssertEqual(layout.restingFrame, CGRect(x: -1004.5, y: 1285, width: 281, height: 32))
    }

    func testGrowingTakesTheLargerFrameAtOnce() throws {
        let layout = NotchLayout(geometry: try geometry())
        let open = layout.frame(for: CGSize(width: 290, height: 400))

        let step = NotchLayout.step(from: layout.restingFrame, to: open)

        XCTAssertEqual(step.now, open)
        XCTAssertEqual(step.settle, open)
    }

    func testShrinkingWaitsForTheShapeToClose() throws {
        let layout = NotchLayout(geometry: try geometry())
        let open = layout.frame(for: CGSize(width: 290, height: 400))

        let step = NotchLayout.step(from: open, to: layout.restingFrame)

        XCTAssertEqual(step.now, open)
        XCTAssertEqual(step.settle, layout.restingFrame)
    }

    func testAWindowWithoutFrameYetTakesTheTargetAsIs() throws {
        let layout = NotchLayout(geometry: try geometry())

        let step = NotchLayout.step(from: .zero, to: layout.restingFrame)

        XCTAssertEqual(step.now, layout.restingFrame)
        XCTAssertEqual(step.settle, layout.restingFrame)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Claudy.xcodeproj -scheme Claudy -destination 'platform=macOS' -only-testing:ClaudyTests/NotchLayoutTests 2>&1 | tail -25`
Expected: build fails with `cannot find 'NotchLayout' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Claudy/App/NotchLayout.swift`:

```swift
import CoreGraphics

/// Where the island's window goes: hung from the top edge of the notched screen, centred on the
/// notch, never past the screen's sides.
struct NotchLayout: Equatable {
    let geometry: NotchGeometry

    /// Width of each ear: the mascot on the left of the notch, the percentage on its right.
    static let earWidth: CGFloat = 48

    /// The notch plus one ear on each side, the notch's height.
    var restingSize: CGSize {
        CGSize(width: geometry.notch.width + 2 * Self.earWidth, height: geometry.notch.height)
    }

    var restingFrame: CGRect { frame(for: restingSize) }

    /// The window for a shape of `size`, open or not.
    func frame(for size: CGSize) -> CGRect {
        let screen = geometry.screenFrame
        let width = min(size.width, screen.width)
        let height = min(size.height, screen.height)
        let x = min(max(geometry.notch.midX - width / 2, screen.minX), screen.maxX - width)
        return CGRect(x: x, y: screen.maxY - height, width: width, height: height)
    }

    /// The frame to take now and the one to settle on once the shape stops moving. Both frames
    /// hang from the same top edge, so their union is the larger one: growing is immediate and
    /// the opening shape is never cut, shrinking waits until the closing shape fits.
    static func step(from current: CGRect, to target: CGRect) -> (now: CGRect, settle: CGRect) {
        (current.isEmpty ? target : current.union(target), target)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project Claudy.xcodeproj -scheme Claudy -destination 'platform=macOS' -only-testing:ClaudyTests/NotchLayoutTests 2>&1 | tail -25`
Expected: `Executed 7 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Claudy/App/NotchLayout.swift ClaudyTests/NotchLayoutTests.swift
git commit -m "feat: frame the notch island on the notched screen" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Time the hover

**Files:**
- Create: `Claudy/App/NotchHover.swift`
- Test: `ClaudyTests/NotchHoverTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `@MainActor final class NotchHover { static let openDelay: TimeInterval /* 0.15 */; static let closeDelay: TimeInterval /* 0.3 */; private(set) var isOpen: Bool; init(openDelay:closeDelay:open: @escaping @MainActor () -> Void, close: @escaping @MainActor () -> Void, mayClose: @escaping @MainActor () -> Bool = { true }); func pointer(inside: Bool); func reset() }`.

- [ ] **Step 1: Write the failing test**

`ClaudyTests/NotchHoverTests.swift`:

```swift
import XCTest
@testable import Claudy

/// The island opens on a pointer that stays, not on one passing through on its way to the menu
/// bar, and closes a moment after the pointer leaves. Short delays keep the suite fast; the
/// logic is the same at 0.15 and 0.3 s.
@MainActor
final class NotchHoverTests: XCTestCase {

    private var opens = 0
    private var closes = 0
    private var mayClose = true

    private func makeHover() -> NotchHover {
        NotchHover(
            openDelay: 0.05,
            closeDelay: 0.05,
            open: { [unowned self] in opens += 1 },
            close: { [unowned self] in closes += 1 },
            mayClose: { [unowned self] in mayClose }
        )
    }

    /// Several times either delay.
    private func settle() async {
        try? await Task.sleep(nanoseconds: 250_000_000)
    }

    func testAPointerCrossingOnItsWayToTheMenuBarLeavesItShut() async {
        let hover = makeHover()

        hover.pointer(inside: true)
        hover.pointer(inside: false)
        await settle()

        XCTAssertEqual(opens, 0)
        XCTAssertFalse(hover.isOpen)
    }

    func testAPointerThatStaysOpensIt() async {
        let hover = makeHover()

        hover.pointer(inside: true)
        await settle()

        XCTAssertEqual(opens, 1)
        XCTAssertTrue(hover.isOpen)
    }

    func testLeavingClosesItAfterTheDelay() async {
        let hover = makeHover()
        hover.pointer(inside: true)
        await settle()

        hover.pointer(inside: false)
        XCTAssertEqual(closes, 0, "closing must wait for the delay")
        await settle()

        XCTAssertEqual(closes, 1)
        XCTAssertFalse(hover.isOpen)
    }

    func testComingBackBeforeTheDelayKeepsItOpen() async {
        let hover = makeHover()
        hover.pointer(inside: true)
        await settle()

        hover.pointer(inside: false)
        hover.pointer(inside: true)
        await settle()

        XCTAssertEqual(closes, 0)
        XCTAssertTrue(hover.isOpen)
        XCTAssertEqual(opens, 1, "already open: no second opening")
    }

    func testAnEditInProgressKeepsItOpenUntilTheNextExit() async {
        let hover = makeHover()
        hover.pointer(inside: true)
        await settle()

        mayClose = false
        hover.pointer(inside: false)
        await settle()
        XCTAssertEqual(closes, 0)
        XCTAssertTrue(hover.isOpen)

        mayClose = true
        hover.pointer(inside: false)
        await settle()
        XCTAssertEqual(closes, 1)
    }

    func testResetCancelsAPendingOpen() async {
        let hover = makeHover()

        hover.pointer(inside: true)
        hover.reset()
        await settle()

        XCTAssertEqual(opens, 0)
        XCTAssertFalse(hover.isOpen)
    }

    func testResetClosesWithoutCallingClose() async {
        let hover = makeHover()
        hover.pointer(inside: true)
        await settle()

        hover.reset()
        await settle()

        XCTAssertFalse(hover.isOpen)
        XCTAssertEqual(closes, 0, "the caller hiding the island closes it itself")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Claudy.xcodeproj -scheme Claudy -destination 'platform=macOS' -only-testing:ClaudyTests/NotchHoverTests 2>&1 | tail -25`
Expected: build fails with `cannot find 'NotchHover' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Claudy/App/NotchHover.swift`:

```swift
import Foundation

/// When the island opens and closes as the pointer comes and goes. Opening waits a beat, so a
/// pointer crossing the ears on its way to the menu bar leaves the island shut; closing waits a
/// little longer, so grazing the edge does not snap it closed.
@MainActor
final class NotchHover {

    static let openDelay: TimeInterval = 0.15
    static let closeDelay: TimeInterval = 0.3

    private(set) var isOpen = false

    private let openDelay: TimeInterval
    private let closeDelay: TimeInterval
    private let open: @MainActor () -> Void
    private let close: @MainActor () -> Void
    /// False while the island must stay open whatever the pointer does: a text field in it is
    /// being edited.
    private let mayClose: @MainActor () -> Bool
    private var pending: Task<Void, Never>?

    init(
        openDelay: TimeInterval = NotchHover.openDelay,
        closeDelay: TimeInterval = NotchHover.closeDelay,
        open: @escaping @MainActor () -> Void,
        close: @escaping @MainActor () -> Void,
        mayClose: @escaping @MainActor () -> Bool = { true }
    ) {
        self.openDelay = openDelay
        self.closeDelay = closeDelay
        self.open = open
        self.close = close
        self.mayClose = mayClose
    }

    /// The pointer entered or left the island. Each call replaces whatever was pending.
    func pointer(inside: Bool) {
        pending?.cancel()
        pending = nil
        if inside {
            guard !isOpen else { return }
            pending = after(openDelay) { [weak self] in
                guard let self else { return }
                self.isOpen = true
                self.open()
            }
        } else {
            guard isOpen else { return }
            pending = after(closeDelay) { [weak self] in
                guard let self, self.mayClose() else { return }
                self.isOpen = false
                self.close()
            }
        }
    }

    /// Closed at once with nothing pending, without calling `close`: the island is being hidden
    /// and its owner resets what it shows.
    func reset() {
        pending?.cancel()
        pending = nil
        isOpen = false
    }

    private func after(_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            action()
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project Claudy.xcodeproj -scheme Claudy -destination 'platform=macOS' -only-testing:ClaudyTests/NotchHoverTests 2>&1 | tail -25`
Expected: `Executed 7 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Claudy/App/NotchHover.swift ClaudyTests/NotchHoverTests.swift
git commit -m "feat: open the notch island on a pointer that stays" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Placement replaces the menu bar flag

Behaviour after this task is the same as today: `hasNotchedScreen` stays false until Task 5, so no menu offers the notch yet and a stored `.notch` shows the menu bar item.

**Files:**
- Create: `Claudy/Models/Placement.swift`
- Create: `Claudy/App/ClaudyMenu.swift`
- Modify: `Claudy/ViewModels/UsageViewModel.swift` (property at lines 18-19, init line 54, `toggleMenuBar` at lines 109-112, `Defaults.isInMenuBar` at lines 402-405)
- Modify: `Claudy/App/MenuBarController.swift` (`showMenu` at lines 281-297, `refresh` / `leaveMenuBar` / `accountItem` / `signIn` / `signOut` at lines 329-360)
- Modify: `Claudy/App/AppDelegate.swift` (`bind` at lines 75-96, `placeWidget` at lines 98-107)
- Modify: `Claudy/Views/RootView.swift` (menu entry at lines 146-148)
- Modify: `Claudy/Views/MenuBarView.swift` (footer button at lines 212-213)
- Test: `ClaudyTests/PlacementTests.swift`, `ClaudyTests/ClaudyMenuTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `enum Placement: String, CaseIterable { case widget, menuBar, notch }` with `static func stored(raw: String?, legacyInMenuBar: Bool) -> Placement`, `func effective(hasNotch: Bool) -> Placement`, `func offered(hasNotch: Bool) -> [Placement]`, `var menuTitle: String`, `var systemImage: String`.
  - `UsageViewModel.placement: Placement` (`@Published private(set)`), `UsageViewModel.hasNotchedScreen: Bool` (`@Published`), `UsageViewModel.place(_ placement: Placement)`.
  - `@MainActor final class ClaudyMenu: NSObject { init(viewModel: UsageViewModel); func make() -> NSMenu; func make(showing placement: Placement, hasNotch: Bool) -> NSMenu }`.

- [ ] **Step 1: Write the failing tests**

`ClaudyTests/PlacementTests.swift`:

```swift
import XCTest
@testable import Claudy

/// Where Claudy shows itself. The notch needs a notched screen; without one Claudy waits in the
/// menu bar and the choice is kept for when the screen comes back.
final class PlacementTests: XCTestCase {

    func testANewInstallStartsAsTheWidget() {
        XCTAssertEqual(Placement.stored(raw: nil, legacyInMenuBar: false), .widget)
    }

    func testAnUpdateKeepsClaudyInTheMenuBar() {
        XCTAssertEqual(Placement.stored(raw: nil, legacyInMenuBar: true), .menuBar)
    }

    func testTheSavedPlacementWinsOverTheLegacyFlag() {
        XCTAssertEqual(Placement.stored(raw: "notch", legacyInMenuBar: true), .notch)
        XCTAssertEqual(Placement.stored(raw: "widget", legacyInMenuBar: true), .widget)
    }

    func testAnUnknownValueFallsBackToTheLegacyFlag() {
        XCTAssertEqual(Placement.stored(raw: "dock", legacyInMenuBar: true), .menuBar)
        XCTAssertEqual(Placement.stored(raw: "dock", legacyInMenuBar: false), .widget)
    }

    func testTheNotchNeedsANotchedScreen() {
        XCTAssertEqual(Placement.notch.effective(hasNotch: true), .notch)
        XCTAssertEqual(Placement.notch.effective(hasNotch: false), .menuBar)
        XCTAssertEqual(Placement.widget.effective(hasNotch: false), .widget)
        XCTAssertEqual(Placement.menuBar.effective(hasNotch: true), .menuBar)
    }

    func testMenusOfferTheOtherPlacements() {
        XCTAssertEqual(Placement.widget.offered(hasNotch: true), [.menuBar, .notch])
        XCTAssertEqual(Placement.menuBar.offered(hasNotch: true), [.widget, .notch])
        XCTAssertEqual(Placement.notch.offered(hasNotch: true), [.widget, .menuBar])
    }

    func testWithoutANotchNoMenuOffersIt() {
        XCTAssertEqual(Placement.widget.offered(hasNotch: false), [.menuBar])
        XCTAssertEqual(Placement.menuBar.offered(hasNotch: false), [.widget])
    }

    /// The lid is closed on an external display: the menu bar item stands in for the island, so
    /// offering "Show in menu bar" would do nothing.
    func testANotchChoiceShownInTheMenuBarOffersOnlyTheWidget() {
        XCTAssertEqual(Placement.notch.offered(hasNotch: false), [.widget])
    }
}
```

`ClaudyTests/ClaudyMenuTests.swift`:

```swift
import AppKit
import XCTest
@testable import Claudy

private struct NoReading: UsageDataSource {
    func fetch() async throws -> UsageSnapshot { .placeholder }
}

/// The right-click menu of the menu bar item and of the island. Built with explicit placements:
/// the test host shares the user's preferences, so no test changes the saved one.
@MainActor
final class ClaudyMenuTests: XCTestCase {

    private func menu(showing placement: Placement, hasNotch: Bool) -> NSMenu {
        ClaudyMenu(viewModel: UsageViewModel(source: NoReading()))
            .make(showing: placement, hasNotch: hasNotch)
    }

    func testTheIslandOffersTheTwoOtherPlacements() {
        let titles = menu(showing: .notch, hasNotch: true).items.map(\.title)

        XCTAssertTrue(titles.contains("Show floating widget"))
        XCTAssertTrue(titles.contains("Show in menu bar"))
        XCTAssertFalse(titles.contains("Show in notch"))
    }

    func testTheMenuBarItemOffersTheNotchOnlyWithOne() {
        XCTAssertTrue(menu(showing: .menuBar, hasNotch: true).items.map(\.title).contains("Show in notch"))
        XCTAssertFalse(menu(showing: .menuBar, hasNotch: false).items.map(\.title).contains("Show in notch"))
    }

    func testEachPlacementEntryCarriesItsPlacement() {
        let placements = menu(showing: .widget, hasNotch: true).items
            .compactMap { $0.representedObject as? Placement }

        XCTAssertEqual(placements, [.menuBar, .notch])
    }

    func testRefreshComesFirstAndQuitLast() {
        let items = menu(showing: .menuBar, hasNotch: false).items

        XCTAssertEqual(items.first?.title, "Refresh")
        XCTAssertEqual(items.last?.title, "Quit Claudy")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Claudy.xcodeproj -scheme Claudy -destination 'platform=macOS' -only-testing:ClaudyTests/PlacementTests -only-testing:ClaudyTests/ClaudyMenuTests 2>&1 | tail -25`
Expected: build fails with `cannot find 'Placement' in scope` and `cannot find 'ClaudyMenu' in scope`.

- [ ] **Step 3: Write `Placement`**

`Claudy/Models/Placement.swift`:

```swift
import Foundation

/// Where Claudy shows itself: the floating card, the menu bar item, or the island around the
/// notch. One at a time.
enum Placement: String, CaseIterable {
    case widget, menuBar, notch

    /// The placement saved under `claudy.placement`. Before that key existed only the menu bar
    /// flag did, and it still decides until a placement is saved: an update leaves Claudy where
    /// the user kept it.
    static func stored(raw: String?, legacyInMenuBar: Bool) -> Placement {
        if let raw, let placement = Placement(rawValue: raw) { return placement }
        return legacyInMenuBar ? .menuBar : .widget
    }

    /// What is actually shown. The island needs a notch: without one Claudy waits in the menu
    /// bar, and the choice itself is kept for when the screen comes back.
    func effective(hasNotch: Bool) -> Placement {
        self == .notch && !hasNotch ? .menuBar : self
    }

    /// What a menu proposes: every placement but the one on screen, the notch only when a
    /// screen has one. Measured from the effective placement, so the menu bar item standing in
    /// for the island does not offer the menu bar.
    func offered(hasNotch: Bool) -> [Placement] {
        let shown = effective(hasNotch: hasNotch)
        return Placement.allCases.filter { $0 != shown && ($0 != .notch || hasNotch) }
    }

    var menuTitle: String {
        switch self {
        case .widget: "Show floating widget"
        case .menuBar: "Show in menu bar"
        case .notch: "Show in notch"
        }
    }

    /// The SF Symbol beside the entry in the card's context menu.
    var systemImage: String {
        switch self {
        case .widget: "macwindow"
        case .menuBar: "menubar.arrow.up.rectangle"
        case .notch: "rectangle.topthird.inset.filled"
        }
    }
}
```

- [ ] **Step 4: Move the view model to `Placement`**

In `Claudy/ViewModels/UsageViewModel.swift`, replace:

```swift
    /// The widget lives in the menu bar instead of floating over the desktop.
    @Published var isInMenuBar: Bool { didSet { Defaults.isInMenuBar = isInMenuBar } }
```

with:

```swift
    /// Where Claudy shows itself: the floating card, the menu bar item or the island around the
    /// notch. Changed through `place(_:)`.
    @Published private(set) var placement: Placement { didSet { Defaults.placement = placement } }
    /// A connected screen has a notch. Kept up to date by the app delegate; the menus offer the
    /// island only then.
    @Published var hasNotchedScreen = false
```

In `init`, replace `self.isInMenuBar = Defaults.isInMenuBar` with `self.placement = Defaults.placement`.

Replace:

```swift
    func toggleMenuBar() {
        isProfileVisible = false
        isInMenuBar.toggle()
    }
```

with:

```swift
    func place(_ placement: Placement) {
        isProfileVisible = false
        self.placement = placement
    }
```

In `private enum Defaults`, replace:

```swift
    static var isInMenuBar: Bool {
        get { store.bool(forKey: "claudy.inMenuBar") }
        set { store.set(newValue, forKey: "claudy.inMenuBar") }
    }
```

with:

```swift
    /// The legacy `claudy.inMenuBar` flag is read, never written: it still decides for a user
    /// who has not picked a placement since the notch arrived.
    static var placement: Placement {
        get {
            Placement.stored(raw: store.string(forKey: "claudy.placement"),
                             legacyInMenuBar: store.bool(forKey: "claudy.inMenuBar"))
        }
        set { store.set(newValue.rawValue, forKey: "claudy.placement") }
    }
```

- [ ] **Step 5: Write the shared menu**

`Claudy/App/ClaudyMenu.swift`:

```swift
import AppKit

/// The right-click menu of the menu bar item and of the island: refresh, the other placements,
/// the account, quit. Its items target this object, so each owner keeps its own alive.
@MainActor
final class ClaudyMenu: NSObject {

    private let viewModel: UsageViewModel

    init(viewModel: UsageViewModel) {
        self.viewModel = viewModel
    }

    /// The menu for Claudy as it stands now.
    func make() -> NSMenu {
        make(showing: viewModel.placement, hasNotch: viewModel.hasNotchedScreen)
    }

    func make(showing placement: Placement, hasNotch: Bool) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(entry("Refresh", #selector(refresh)))
        for offered in placement.offered(hasNotch: hasNotch) {
            let item = entry(offered.menuTitle, #selector(place(_:)))
            item.representedObject = offered
            menu.addItem(item)
        }
        if let account = accountItem() {
            menu.addItem(.separator())
            menu.addItem(account)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Claudy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        return menu
    }

    private func entry(_ title: String, _ action: Selector?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    /// Sign in or out, whichever applies. Nothing before the first reading, which has yet to say
    /// which; nothing on the demo set, which has no account. An item without an action shows
    /// disabled while a sign-in is already under way.
    private func accountItem() -> NSMenuItem? {
        if viewModel.isSignedIn {
            return entry("Sign out of Claude", #selector(signOut))
        }
        guard viewModel.hasLoaded, !viewModel.snapshot.isDemo else { return nil }
        return entry("Sign in to Claude…", viewModel.isSigningIn ? nil : #selector(signIn))
    }

    @objc private func refresh() {
        Task { await viewModel.refresh(userInitiated: true) }
    }

    @objc private func place(_ sender: NSMenuItem) {
        guard let placement = sender.representedObject as? Placement else { return }
        viewModel.place(placement)
    }

    @objc private func signIn() {
        viewModel.startSignIn()
    }

    @objc private func signOut() {
        viewModel.signOut()
    }
}
```

- [ ] **Step 6: Use it from the menu bar item**

In `Claudy/App/MenuBarController.swift`, add under `private var cancellables = Set<AnyCancellable>()`:

```swift
    /// The right-click menu. Its items target it, so it lives as long as the item.
    private lazy var menuContent = ClaudyMenu(viewModel: viewModel)
```

Replace the body of `showMenu(from:)` with:

```swift
    private func showMenu(from button: NSStatusBarButton) {
        popover.performClose(nil)
        item?.menu = menuContent.make()
        button.performClick(nil)
        item?.menu = nil
    }
```

Delete `refresh()`, `leaveMenuBar()`, `accountItem()`, `signIn()` and `signOut()` from `MenuBarController` (they now live in `ClaudyMenu`).

- [ ] **Step 7: Place the widget from the placement**

In `Claudy/App/AppDelegate.swift`, in `bind()`, replace the two `viewModel.$isInMenuBar` subscriptions with:

```swift
        // Fires once on subscription too, which places the widget on launch.
        viewModel.$placement
            .combineLatest(viewModel.$hasNotchedScreen)
            .map { placement, hasNotch in placement.effective(hasNotch: hasNotch) }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] placement in self?.placeWidget(placement) }
            .store(in: &cancellables)

        // Moving Claudy elsewhere greets again while an update is pending.
        viewModel.$placement
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updates.greetAgain() }
            .store(in: &cancellables)
```

Replace `placeWidget(inMenuBar:)` with:

```swift
    /// The card, or the menu bar item for any other placement: the notch falls back to the menu
    /// bar wherever the island cannot show.
    private func placeWidget(_ placement: Placement) {
        if placement == .widget {
            menuBar.hide()
            panel?.orderFrontRegardless()
        } else {
            panel?.orderOut(nil)
            menuBar.show()
        }
    }
```

- [ ] **Step 8: Offer the placements in the card and the popover**

In `Claudy/Views/RootView.swift`, replace:

```swift
        Button(action: viewModel.toggleMenuBar) {
            Label("Show in menu bar", systemImage: "menubar.arrow.up.rectangle")
        }
```

with:

```swift
        ForEach(viewModel.placement.offered(hasNotch: viewModel.hasNotchedScreen), id: \.self) { placement in
            Button {
                viewModel.place(placement)
            } label: {
                Label(placement.menuTitle, systemImage: placement.systemImage)
            }
        }
```

In `Claudy/Views/MenuBarView.swift`, replace:

```swift
            Button("Floating widget", action: viewModel.toggleMenuBar)
                .help("Leave the menu bar and show the widget on the desktop")
```

with:

```swift
            Button("Floating widget") { viewModel.place(.widget) }
                .help("Show the widget on the desktop instead")
```

- [ ] **Step 9: Run the new tests, then the full suite**

Run: `xcodebuild test -project Claudy.xcodeproj -scheme Claudy -destination 'platform=macOS' -only-testing:ClaudyTests/PlacementTests -only-testing:ClaudyTests/ClaudyMenuTests 2>&1 | tail -25`
Expected: `Executed 12 tests, with 0 failures`.

Run: `grep -rn "isInMenuBar\|toggleMenuBar\|leaveMenuBar" Claudy ClaudyTests`
Expected: no output.

Run: `xcodebuild test -project Claudy.xcodeproj -scheme Claudy -destination 'platform=macOS' 2>&1 | tail -25`
Expected: `** TEST SUCCEEDED **`, no failure.

- [ ] **Step 10: Commit**

```bash
git add Claudy/Models/Placement.swift Claudy/App/ClaudyMenu.swift Claudy/ViewModels/UsageViewModel.swift \
  Claudy/App/MenuBarController.swift Claudy/App/AppDelegate.swift Claudy/Views/RootView.swift \
  Claudy/Views/MenuBarView.swift ClaudyTests/PlacementTests.swift ClaudyTests/ClaudyMenuTests.swift
git commit -m "refactor: a placement enum replaces the menu bar flag" -m "The saved flag still decides until a placement is saved, so an update leaves Claudy where it was. The menu bar item's right-click menu moves into a builder the island will share." -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: The island

**Files:**
- Create: `Claudy/App/NotchPanel.swift` (`NotchPanel`, `NotchHostingView`)
- Create: `Claudy/Views/NotchView.swift` (`NotchModel`, `NotchView`, `NotchShape`)
- Create: `Claudy/App/NotchController.swift`
- Modify: `Claudy/App/AppDelegate.swift` (launch, screen observer, `placeWidget`)
- Test: `ClaudyTests/MainMenuTests.swift` (`testTestHostShowsNoCard`)

**Interfaces:**
- Consumes: `NotchGeometry.current()` (Task 1); `NotchLayout(geometry:)`, `.restingFrame`, `.frame(for:)`, `NotchLayout.step(from:to:)`, `NotchLayout.earWidth` (Task 2); `NotchHover(open:close:mayClose:)`, `.pointer(inside:)`, `.reset()` (Task 3); `Placement`, `UsageViewModel.placement`, `.hasNotchedScreen`, `ClaudyMenu(viewModel:).make()` (Task 4); existing `MenuBarView`, `ClaudyTyping`, `ClaudyWaving`, `UpdateDot`, `Theme`.
- Produces: `@MainActor final class NotchController { init(viewModel:updates:); func show(on: NotchGeometry); func hide(); func panelResignedKey() }`; `AppDelegate.notch` (`private(set) lazy var`).

- [ ] **Step 1: Write the failing test**

In `ClaudyTests/MainMenuTests.swift`, replace:

```swift
    /// Hosting the tests, Claudy installs its menu and nothing else: no card, no menu bar item,
    /// no reading of the account. Drawing a window aborts on GitHub's Intel machines.
    func testTestHostShowsNoCard() {
        XCTAssertFalse(NSApp.windows.contains { $0 is FloatingPanel })
    }
```

with:

```swift
    /// Hosting the tests, Claudy installs its menu and nothing else: no card, no menu bar item,
    /// no island, no reading of the account. Drawing a window aborts on GitHub's Intel machines.
    func testTestHostShowsNoCard() {
        XCTAssertFalse(NSApp.windows.contains { $0 is FloatingPanel })
        XCTAssertFalse(NSApp.windows.contains { $0 is NotchPanel })
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Claudy.xcodeproj -scheme Claudy -destination 'platform=macOS' -only-testing:ClaudyTests/MainMenuTests 2>&1 | tail -25`
Expected: build fails with `cannot find type 'NotchPanel' in scope`.

- [ ] **Step 3: Write the window**

`Claudy/App/NotchPanel.swift`:

```swift
import AppKit
import SwiftUI

/// The island's window: borderless and non-activating, above the menu bar, on every space and
/// over full-screen apps, where the notch is a black band anyway.
final class NotchPanel: NSPanel {

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        // Key only for the manual sign-in code: a click on a button leaves the front app's focus.
        becomesKeyOnlyIfNeeded = true
    }

    /// Without this a borderless panel never takes the keyboard, and the code could not be typed.
    override var canBecomeKey: Bool { true }

    /// AppKit keeps windows under the menu bar; the island belongs over it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// The island's content view. It reports the pointer entering and leaving the whole window, key
/// or not, and answers a right click with Claudy's menu.
final class NotchHostingView<Content: View>: NSHostingView<Content> {

    var onHover: ((Bool) -> Void)?
    var contextMenu: (() -> NSMenu?)?
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    /// SwiftUI's own hover areas (the chart, the model split) report here too: only the area
    /// covering the whole island speaks for the pointer, or crossing the chart would close it.
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        if event.trackingArea === tracking { onHover?(true) }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if event.trackingArea === tracking { onHover?(false) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        if let menu = contextMenu?() { return menu }
        return super.menu(for: event)
    }

    /// A click on a button of the open island acts at once, key window or not.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
```

- [ ] **Step 4: Write the view**

`Claudy/Views/NotchView.swift`:

```swift
import SwiftUI

/// The island's state, shared by `NotchController` and `NotchView`.
@MainActor
final class NotchModel: ObservableObject {
    /// Hover opened it: the popover content hangs under the ears.
    @Published var isOpen = false
    /// The notch the ears hug, in points.
    @Published var notchSize: CGSize = .zero
    /// The black shape's size as last laid out. The controller fits the window to it.
    @Published var shapeSize: CGSize = .zero
}

/// Claudy around the notch. At rest a black band the notch's height extends it on both sides:
/// the mascot in the left ear, the lead percentage in the right one. Open, the menu bar popover
/// hangs underneath on the same black. Black to merge with the notch itself.
struct NotchView: View {
    @EnvironmentObject private var viewModel: UsageViewModel
    @EnvironmentObject private var updates: UpdateChecker
    @ObservedObject var model: NotchModel

    private static let restingRadius: CGFloat = 9
    private static let openRadius: CGFloat = 20
    /// Room given to the typing mascot. The sprite snaps to whole device pixels inside it, which
    /// lands on the menu bar icon's size; the rest leaves room for the explosion.
    private static let mascotHeight: CGFloat = 20
    /// The menu bar icon's pixel, for the waving sprite, which takes its cell directly.
    private static let waveCell: CGFloat = 0.5

    /// The 5h session, or the monthly spend on a plan billed on usage.
    private var lead: UsageWindow { viewModel.snapshot.primary }
    private var tint: Color { Theme.tint(lead.accent, at: lead.percent) }
    private var percent: String { lead.isMeasured ? "\(Int(lead.percent * 100))%" : "—" }
    private var shape: NotchShape {
        NotchShape(bottomRadius: model.isOpen ? Self.openRadius : Self.restingRadius)
    }

    var body: some View {
        VStack(spacing: 0) {
            ears
            if model.isOpen {
                MenuBarView()
                    .transition(.opacity)
            }
        }
        .background(shape.fill(Color.black))
        .clipShape(shape)
        .environment(\.colorScheme, .dark)
        // Its own size whatever the window's: the controller sizes the window from it.
        .fixedSize()
        .background(GeometryReader { proxy in
            Color.clear.preference(key: ShapeSizeKey.self, value: proxy.size)
        })
        .onPreferenceChange(ShapeSizeKey.self) { model.shapeSize = $0 }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var ears: some View {
        HStack(spacing: 0) {
            mascot
                .frame(width: NotchLayout.earWidth)
            Color.clear
                .frame(width: model.notchSize.width)
            reading
                .frame(width: NotchLayout.earWidth)
        }
        .frame(height: model.notchSize.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Claudy, \(lead.title) \(percent)")
    }

    @ViewBuilder
    private var mascot: some View {
        if updates.isGreeting && !viewModel.snapshot.isOverloaded {
            ClaudyWaving(tint: tint, cell: Self.waveCell)
        } else {
            ClaudyTyping(tint: tint, isTyping: viewModel.snapshot.session.isRunning,
                         isOverloaded: viewModel.snapshot.isOverloaded)
                .frame(width: Self.mascotHeight * ClaudyTyping.aspectRatio, height: Self.mascotHeight)
        }
    }

    private var reading: some View {
        HStack(spacing: 3) {
            Text(percent)
                .font(Theme.Font.value(12.5, .semibold))
                .foregroundStyle(.primary.opacity(lead.isMeasured ? 0.92 : 0.45))
            if updates.available != nil {
                UpdateDot(size: 5)
            }
            if let message = viewModel.errorMessage {
                Circle()
                    .fill(Theme.danger)
                    .frame(width: 5, height: 5)
                    .help(message)
            }
        }
    }
}

/// Square on top, flush with the screen edge; rounded at the bottom. The radius animates between
/// the ears and the open panel.
struct NotchShape: Shape {
    var bottomRadius: CGFloat

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let radius = min(bottomRadius, rect.height / 2, rect.width / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: radius)
        path.closeSubpath()
        return path
    }
}

private struct ShapeSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
```

- [ ] **Step 5: Write the controller**

`Claudy/App/NotchController.swift`:

```swift
import AppKit
import SwiftUI
import Combine

/// Claudy around the notch: the ears at rest, the menu bar popover underneath on hover. The app
/// delegate shows it instead of the card and the menu bar item when the user picks it and a
/// screen has a notch.
@MainActor
final class NotchController {

    private let viewModel: UsageViewModel
    private let updates: UpdateChecker
    private let model = NotchModel()
    /// The island's right-click menu. Its items target it, so it lives as long as the island.
    private lazy var menu = ClaudyMenu(viewModel: viewModel)
    private lazy var hover = NotchHover(
        open: { [weak self] in self?.open() },
        close: { [weak self] in self?.close() },
        mayClose: { [weak self] in !(self?.isEditingText ?? false) }
    )
    private var panel: NotchPanel?
    private var layout: NotchLayout?
    /// Shrinks the window once the shape has finished closing.
    private var settle: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var resignObserver: NSObjectProtocol?

    /// Long enough for `Theme.Motion.popup` to come to rest.
    private static let settleDelay: TimeInterval = 0.45

    init(viewModel: UsageViewModel, updates: UpdateChecker) {
        self.viewModel = viewModel
        self.updates = updates
    }

    deinit {
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
    }

    /// Puts the island on the notch. A new notch rectangle (another resolution, another screen)
    /// closes it first, so the window never spans the old place and the new one.
    func show(on geometry: NotchGeometry) {
        let panel = panel ?? makePanel()
        if layout?.geometry != geometry {
            let layout = NotchLayout(geometry: geometry)
            self.layout = layout
            collapse()
            model.notchSize = geometry.notch.size
            panel.setFrame(layout.restingFrame, display: true)
        }
        panel.orderFrontRegardless()
    }

    /// Takes the island away, closed, with nothing left pending.
    func hide() {
        collapse()
        if let layout { panel?.setFrame(layout.restingFrame, display: false) }
        panel?.orderOut(nil)
    }

    /// A click elsewhere ended the edit that held the island open: close it if the pointer left.
    func panelResignedKey() {
        guard let panel else { return }
        panel.makeFirstResponder(nil)
        if !panel.frame.contains(NSEvent.mouseLocation) {
            hover.pointer(inside: false)
        }
    }

    private func makePanel() -> NotchPanel {
        let host = NotchHostingView(rootView: NotchView(model: model)
            .environmentObject(viewModel)
            .environmentObject(updates))
        // The window follows the shape through `fit`, not through SwiftUI's own sizing.
        host.sizingOptions = []
        host.onHover = { [weak self] inside in self?.hover.pointer(inside: inside) }
        host.contextMenu = { [weak self] in self?.menu.make() }

        let panel = NotchPanel()
        panel.contentView = host
        self.panel = panel

        model.$shapeSize
            .removeDuplicates()
            .sink { [weak self] size in self?.fit(size) }
            .store(in: &cancellables)

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                (NSApp.delegate as? AppDelegate)?.notch.panelResignedKey()
            }
        }
        return panel
    }

    private func collapse() {
        hover.reset()
        settle?.cancel()
        model.isOpen = false
    }

    private func open() {
        // Opening the island counts as opening Claudy: the wave has been seen.
        updates.acknowledgeGreeting()
        withAnimation(motion) { model.isOpen = true }
    }

    private func close() {
        withAnimation(motion) { model.isOpen = false }
    }

    /// No spring with Reduce Motion on: the island is simply open or closed.
    private var motion: Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : Theme.Motion.popup
    }

    /// The manual sign-in code is being typed in the open island.
    private var isEditingText: Bool {
        (panel?.firstResponder as? NSTextView)?.isFieldEditor == true
    }

    /// Fits the window to the shape: at once when it grows, after the animation when it shrinks.
    private func fit(_ shape: CGSize) {
        guard let panel, let layout, shape.width > 0, shape.height > 0 else { return }
        let step = NotchLayout.step(from: panel.frame, to: layout.frame(for: shape))
        if step.now != panel.frame { panel.setFrame(step.now, display: true) }
        settle?.cancel()
        guard step.settle != step.now else { return }
        settle = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.settleDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.panel?.setFrame(step.settle, display: true)
        }
    }
}
```

- [ ] **Step 6: Wire it into the app delegate**

In `Claudy/App/AppDelegate.swift`:

Under `private(set) lazy var menuBar = ...`, add:

```swift
    private(set) lazy var notch = NotchController(viewModel: viewModel, updates: updates)
```

In `applicationDidFinishLaunching`, just before `bind()`, add:

```swift
        viewModel.hasNotchedScreen = NotchGeometry.current() != nil
```

In the screen observer's closure, replace `(NSApp.delegate as? AppDelegate)?.clampPanelToScreen()` with `(NSApp.delegate as? AppDelegate)?.screensChanged()`, and add after `clampPanelToScreen()`'s definition:

```swift
    /// Screens came or went, or changed resolution: the card goes back on screen, and the island
    /// follows the notch, or hands over to the menu bar item when no screen has one.
    private func screensChanged() {
        clampPanelToScreen()
        let geometry = NotchGeometry.current()
        viewModel.hasNotchedScreen = geometry != nil
        // Same placement, new resolution: the notch rectangle moved with it.
        if let geometry, viewModel.placement == .notch {
            notch.show(on: geometry)
        }
    }
```

Replace `placeWidget(_:)` from Task 4 with:

```swift
    /// Exactly one of the card, the menu bar item and the island.
    private func placeWidget(_ placement: Placement) {
        if placement != .widget { panel?.orderOut(nil) }
        if placement != .menuBar { menuBar.hide() }
        if placement != .notch { notch.hide() }
        switch placement {
        case .widget:
            panel?.orderFrontRegardless()
        case .menuBar:
            menuBar.show()
        case .notch:
            // `effective` says notch only with a notched screen, but it may have gone since.
            if let geometry = NotchGeometry.current() {
                notch.show(on: geometry)
            } else {
                menuBar.show()
            }
        }
    }
```

- [ ] **Step 7: Run the tests**

Run: `xcodebuild test -project Claudy.xcodeproj -scheme Claudy -destination 'platform=macOS' 2>&1 | tail -25`
Expected: `** TEST SUCCEEDED **`. Fix any compiler warning the new files introduce (Swift 5 mode may warn on the `onPreferenceChange` closure under recent SDKs: wrap the body in `MainActor.assumeIsolated { ... }` if it does).

- [ ] **Step 8: Check it on the notched Mac**

Before: note the user's saved placement with `defaults read com.claudy.Claudy claudy.placement 2>/dev/null; defaults read com.claudy.Claudy claudy.inMenuBar`.

Run: `./Scripts/build-app.sh && osascript -e 'quit app "Claudy"'; open build/Claudy.app`

Check each item, with a screenshot (`screencapture -x -R 600,0,528,480 <scratchpad>/notch-<n>.png`, then look at it):
1. Right-click the menu bar item: "Show in notch" is listed. Choose it: the menu bar item goes, the ears appear around the notch, mascot left, percentage right.
2. Pointer across the ears quickly toward the menu bar: the island stays shut.
3. Pointer resting on the ears: after a short beat the island drops open with the rings, the week chart, the model split; moving over the chart and the split does not close it.
4. Pointer away: it closes after a moment; a click just under the notch (where the open panel was) reaches the app below.
5. Right-click the ears: Refresh, Show floating widget, Show in menu bar, account entry, Quit. "Show floating widget" brings the card back; the card's right-click offers "Show in notch".
6. A full-screen app (Safari, green button): the ears stay visible over the black band.
7. System Settings > Accessibility > Display > Reduce motion on: opening has no spring, the mascot is still. Turn it back off.
8. With an external display, if one is at hand: close the lid, the menu bar item appears on the external display; reopen, the island returns.

After: `osascript -e 'quit app "Claudy"'`, restore the saved placement (`defaults delete com.claudy.Claudy claudy.placement` when it had none before), then `open /Applications/Claudy.app`.

- [ ] **Step 9: Commit**

```bash
git add Claudy/App/NotchPanel.swift Claudy/Views/NotchView.swift Claudy/App/NotchController.swift \
  Claudy/App/AppDelegate.swift ClaudyTests/MainMenuTests.swift
git commit -m "feat: show Claudy around the notch" -m "On a Mac with a notch, the right-click menus offer a third placement: the mascot and the session percentage on either side of the notch, the menu bar popover underneath on hover. It stays over full-screen apps and falls back to the menu bar item when no screen has a notch." -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Documentation

**Files:**
- Modify: `README.md` (Use section, lines 69-78)
- Modify: `README.fr.md` (Utiliser section, lines 70-79)
- Modify: `docs/development.md` (Structure and Window sections)

**Interfaces:**
- Consumes: the behaviour of Tasks 4 and 5.
- Produces: nothing code depends on.

- [ ] **Step 1: README.md**

Replace `The app is an agent: no Dock icon, no menu bar. Everything goes through the card.` with:

```markdown
The app is an agent: no Dock icon, no menu bar of its own. It shows as a floating card, as an item
in the menu bar, or, on a Mac with a notch, as an island around the notch. Right-click any of them
to move it.
```

Replace the row `| Right-click | Refresh · Mode · Sign in · Always on top · Launch at login · Quit |` with:

```markdown
| Right-click | Refresh · Mode · Placement (card, menu bar, notch) · Sign in · Always on top · Launch at login · Quit |
| Hover the notch island | Open the quotas, the week and the split by model under the notch |
```

- [ ] **Step 2: README.fr.md, same changes in French**

Replace `L'app est un agent : pas d'icône dans le Dock, pas de barre de menus. Tout passe par la carte.` with:

```markdown
L'app est un agent : pas d'icône dans le Dock, pas de barre de menus à elle. Elle s'affiche en carte
flottante, dans la barre des menus ou, sur un Mac à encoche, en île autour de l'encoche. Un clic
droit sur l'une ou l'autre permet de la déplacer.
```

Replace the row `| Clic droit | Rafraîchir · Mode · Connexion · Toujours au-dessus · Lancement au démarrage · Quitter |` with:

```markdown
| Clic droit | Rafraîchir · Mode · Emplacement (carte, barre des menus, encoche) · Connexion · Toujours au-dessus · Lancement au démarrage · Quitter |
| Survol de l'île | Ouvrir les quotas, la semaine et la répartition par modèle sous l'encoche |
```

- [ ] **Step 3: docs/development.md**

In the Structure block, replace the `App/` line with:

```
├── App/          main.swift (AppKit entry) · AppDelegate (window, position, ⌘ menu) · FloatingPanel ·
│                 MenuBarController · ClaudyMenu (shared right-click menu) · Notch* (the island)
```

Replace the `Models/` line with:

```
├── Models/       UsageSnapshot and its parts · QuotaModels (account readings and their source) · Placement
```

Add `NotchGeometry` to the end of the `Services/` list (after `LaunchAtLogin`).

In the Window section, change "Four technical points" to "Five technical points" and add this bullet at the end of the list:

```markdown
- **The notch island** (`NotchPanel`) sits at `.mainMenu + 3`, over the menu bar and over
  full-screen apps. Its window follows the black shape (`NotchLayout.step`): it grows at once
  when the island opens and shrinks only once the shape has closed, so a click just under the
  notch reaches the app below. Only the tracking area covering the whole window counts as the
  pointer entering or leaving: SwiftUI's own hover areas report to the same view.
```

- [ ] **Step 4: Check the language rule**

Run: `grep -nE "[À-ÿ]" README.md docs/development.md docs/superpowers/plans/2026-09-29-notch-island.md Claudy/**/*.swift ClaudyTests/*.swift | grep -v "README.fr.md"`
Expected: only the `×` of screen sizes and the existing `…` / `—` UI glyphs; no French word.

Run: `grep -rn "—" Claudy/App/Notch*.swift Claudy/Views/NotchView.swift Claudy/App/ClaudyMenu.swift Claudy/Models/Placement.swift`
Expected: only the `"—"` placeholder string in `NotchView.percent` (the same glyph the card shows for an unmeasured quota), no em dash in comments.

- [ ] **Step 5: Commit**

```bash
git add README.md README.fr.md docs/development.md
git commit -m "docs: the notch island and the right-click placements" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Verify the branch

**Files:** none changed unless a check fails.

- [ ] **Step 1: Full test suite**

Run: `xcodebuild test -project Claudy.xcodeproj -scheme Claudy -destination 'platform=macOS' 2>&1 | grep -E "Executed|TEST (SUCCEEDED|FAILED)" | tail -3`
Expected: `** TEST SUCCEEDED **`, 0 failures.

- [ ] **Step 2: Preflight**

Run: `./Scripts/preflight.sh`
Expected: a passing verdict (about two minutes; it closes and reopens the installed Claudy).

- [ ] **Step 3: Whole-branch review**

Dispatch the `ecc:swift-reviewer` agent on `git diff develop...feat/notch-island`, with the spec path. Fix CRITICAL and HIGH findings, each in its own `fix:` commit, and rerun Step 1.

- [ ] **Step 4: Hand over**

Report to the user: commits on `feat/notch-island`, test count, preflight verdict, screenshots from Task 5 Step 8, review findings and what was done with them. Merging into `develop` and releasing follow the usual release steps, on the user's go.
