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

    /// The window shrank away from a pointer that did not move (a sign-out swapped the charts
    /// for the short sign-in block): no exit was reported, the resync closes it.
    func testAWindowShrinkingAwayFromAStillPointerClosesIt() async {
        let hover = makeHover()
        hover.pointer(inside: true)
        await settle()

        hover.resync(pointerInside: false)
        await settle()

        XCTAssertEqual(closes, 1)
        XCTAssertFalse(hover.isOpen)
    }

    /// Shown under a pointer already on the ears: no entry was reported, the resync opens it.
    func testAnIslandAppearingUnderThePointerOpens() async {
        let hover = makeHover()

        hover.resync(pointerInside: true)
        await settle()

        XCTAssertEqual(opens, 1)
        XCTAssertTrue(hover.isOpen)
    }

    func testAResyncThatAgreesChangesNothing() async {
        let hover = makeHover()
        hover.pointer(inside: true)
        await settle()

        hover.resync(pointerInside: true)
        await settle()

        XCTAssertEqual(opens, 1)
        XCTAssertEqual(closes, 0)
        XCTAssertTrue(hover.isOpen)
    }

    func testAfterAResetThePointerCountsAsOutside() async {
        let hover = makeHover()
        hover.pointer(inside: true)
        await settle()
        hover.reset()

        hover.resync(pointerInside: true)
        await settle()

        XCTAssertEqual(opens, 2, "shown again under the pointer, it opens again")
    }
}
