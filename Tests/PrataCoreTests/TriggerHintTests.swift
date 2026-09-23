import XCTest
@testable import PrataCore

final class TriggerHintTests: XCTestCase {
    func testMenuTitleSaysHoldForPushToTalk() {
        XCTAssertEqual(TriggerHint.menuTitle(for: .pushToTalk), "Hold to Record")
    }

    func testMenuTitleSaysPressForToggle() {
        XCTAssertEqual(TriggerHint.menuTitle(for: .toggle), "Press to Record")
    }

    func testKeyLabelUsesTheModifierKeyName() {
        XCTAssertEqual(TriggerHint.keyLabel(for: .rightCommand, customShortcut: nil), "Right ⌘")
        XCTAssertEqual(TriggerHint.keyLabel(for: .rightOption, customShortcut: nil), "Right ⌥")
        XCTAssertEqual(TriggerHint.keyLabel(for: .rightControl, customShortcut: nil), "Right ⌃")
        XCTAssertEqual(TriggerHint.keyLabel(for: .fn, customShortcut: nil), "Fn")
    }

    func testKeyLabelIgnoresCustomShortcutForModifierTriggers() {
        XCTAssertEqual(TriggerHint.keyLabel(for: .rightOption, customShortcut: "⌃⌥Space"), "Right ⌥")
    }

    func testKeyLabelUsesTheRecordedCustomShortcut() {
        XCTAssertEqual(TriggerHint.keyLabel(for: .customShortcut, customShortcut: "⌃⌥Space"), "⌃⌥Space")
    }

    func testKeyLabelSaysNotSetWhenCustomShortcutIsEmpty() {
        XCTAssertEqual(TriggerHint.keyLabel(for: .customShortcut, customShortcut: nil), "Not set")
        XCTAssertEqual(TriggerHint.keyLabel(for: .customShortcut, customShortcut: ""), "Not set")
    }

    func testExplanationForPushToTalk() {
        XCTAssertEqual(
            TriggerHint.explanation(trigger: .rightCommand, mode: .pushToTalk, customShortcut: nil),
            "Hold Right ⌘ while speaking; release to paste."
        )
    }

    func testExplanationForToggle() {
        XCTAssertEqual(
            TriggerHint.explanation(trigger: .fn, mode: .toggle, customShortcut: nil),
            "Press Fn to start, press again to stop."
        )
    }

    func testExplanationUsesTheCustomShortcut() {
        XCTAssertEqual(
            TriggerHint.explanation(trigger: .customShortcut, mode: .pushToTalk, customShortcut: "⌃⌥Space"),
            "Hold ⌃⌥Space while speaking; release to paste."
        )
    }

    func testExplanationAsksForAShortcutWhenCustomIsNotSet() {
        XCTAssertEqual(
            TriggerHint.explanation(trigger: .customShortcut, mode: .toggle, customShortcut: nil),
            "Record a shortcut above to start dictating."
        )
    }
}
