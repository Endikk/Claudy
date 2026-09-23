import AppKit
import XCTest
@testable import Claudy

/// Claudy shows no menu bar of its own, so ⌘V reaches a text field only through a key equivalent
/// in the hidden main menu. Without it, the sign-in code could only be pasted with a right click.
@MainActor
final class MainMenuTests: XCTestCase {

    private var items: [NSMenuItem] {
        NSApp.mainMenu?.items.compactMap(\.submenu).flatMap(\.items) ?? []
    }

    func testEditingShortcutsReachTheFocusedField() throws {
        let expected: [(String, Selector)] = [
            ("x", #selector(NSText.cut(_:))),
            ("c", #selector(NSText.copy(_:))),
            ("v", #selector(NSText.paste(_:))),
            ("a", #selector(NSText.selectAll(_:))),
        ]
        for (key, action) in expected {
            let item = try XCTUnwrap(items.first { $0.keyEquivalent == key }, "no ⌘\(key.uppercased())")
            XCTAssertEqual(item.action, action)
            XCTAssertEqual(item.keyEquivalentModifierMask, [.command])
            // No target: the action goes to the first responder, the field being edited.
            XCTAssertNil(item.target)
        }
    }

    func testRefreshAndQuitShortcutsAreKept() {
        XCTAssertNotNil(items.first { $0.keyEquivalent == "r" })
        XCTAssertNotNil(items.first { $0.keyEquivalent == "q" })
    }
}
