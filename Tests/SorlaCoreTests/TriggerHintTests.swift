import XCTest
@testable import SorlaCore

final class TriggerHintTests: XCTestCase {
    func testMenuTitleNamesTheKeyForPushToTalk() {
        XCTAssertEqual(
            TriggerHint.menuTitle(trigger: .rightCommand, mode: .pushToTalk, customShortcut: nil),
            "Start Dictation (Hold Right ⌘)"
        )
    }

    func testMenuTitleNamesTheKeyForToggle() {
        XCTAssertEqual(TriggerHint.menuTitle(trigger: .fn, mode: .toggle, customShortcut: nil), "Start Dictation (Press Fn)")
    }

    func testMenuTitleUsesTheCustomShortcut() {
        XCTAssertEqual(
            TriggerHint.menuTitle(trigger: .customShortcut, mode: .pushToTalk, customShortcut: "⌃⌥Space"),
            "Start Dictation (Hold ⌃⌥Space)"
        )
    }

    func testMenuTitleWhenTheCustomShortcutIsNotSet() {
        XCTAssertEqual(
            TriggerHint.menuTitle(trigger: .customShortcut, mode: .toggle, customShortcut: nil),
            "Start Dictation"
        )
    }

    func testMenuTitleWhileRecordingStops() {
        XCTAssertEqual(
            TriggerHint.menuTitle(trigger: .rightCommand, mode: .pushToTalk, customShortcut: nil, isRecording: true),
            "Stop Dictation"
        )
        XCTAssertEqual(
            TriggerHint.menuTitle(trigger: .customShortcut, mode: .toggle, customShortcut: nil, isRecording: true),
            "Stop Dictation"
        )
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

    func testReadyMessageForPushToTalk() {
        XCTAssertEqual(
            TriggerHint.readyMessage(trigger: .rightCommand, mode: .pushToTalk, customShortcut: nil),
            "Sorla is ready. Hold Right ⌘ to dictate."
        )
    }

    func testReadyMessageForToggle() {
        XCTAssertEqual(
            TriggerHint.readyMessage(trigger: .fn, mode: .toggle, customShortcut: nil),
            "Sorla is ready. Press Fn to dictate."
        )
    }

    func testReadyMessageWhenTheCustomShortcutIsNotSet() {
        XCTAssertEqual(
            TriggerHint.readyMessage(trigger: .customShortcut, mode: .pushToTalk, customShortcut: nil),
            "Sorla is ready. Set a shortcut in Settings to dictate."
        )
    }
}
