import XCTest
import AppKit
@testable import PrataCore

final class TriggerKeyTests: XCTestCase {
    func testRawValuesAreStableForPersistence() {
        XCTAssertEqual(TriggerKey.rightCommand.rawValue, "rightCommand")
        XCTAssertEqual(TriggerKey.rightOption.rawValue, "rightOption")
        XCTAssertEqual(TriggerKey.rightControl.rawValue, "rightControl")
        XCTAssertEqual(TriggerKey.fn.rawValue, "fn")
        XCTAssertEqual(TriggerKey.customShortcut.rawValue, "customShortcut")
    }

    func testAllCases() {
        XCTAssertEqual(
            Set(TriggerKey.allCases),
            [.rightCommand, .rightOption, .rightControl, .fn, .customShortcut]
        )
    }

    func testDefaultIsRightCommand() {
        XCTAssertEqual(TriggerKey.default, .rightCommand)
    }

    func testRightCommandKeyCodeAndDeviceMask() {
        XCTAssertEqual(TriggerKey.rightCommand.keyCode, 0x36)
        XCTAssertEqual(TriggerKey.rightCommand.deviceMask, 0x10)
    }

    func testRightOptionKeyCodeAndDeviceMask() {
        XCTAssertEqual(TriggerKey.rightOption.keyCode, 0x3D)
        XCTAssertEqual(TriggerKey.rightOption.deviceMask, 0x40)
    }

    func testRightControlKeyCodeAndDeviceMask() {
        XCTAssertEqual(TriggerKey.rightControl.keyCode, 0x3E)
        XCTAssertEqual(TriggerKey.rightControl.deviceMask, 0x2000)
    }

    func testFnKeyCodeAndDeviceMask() {
        XCTAssertEqual(TriggerKey.fn.keyCode, 0x3F)
        XCTAssertEqual(TriggerKey.fn.deviceMask, NSEvent.ModifierFlags.function.rawValue)
    }

    func testCustomShortcutHasNoKeyCodeOrDeviceMask() {
        XCTAssertNil(TriggerKey.customShortcut.keyCode)
        XCTAssertNil(TriggerKey.customShortcut.deviceMask)
    }

    func testDisplayNames() {
        XCTAssertEqual(TriggerKey.rightCommand.displayName, "Right ⌘")
        XCTAssertEqual(TriggerKey.rightOption.displayName, "Right ⌥")
        XCTAssertEqual(TriggerKey.rightControl.displayName, "Right ⌃")
        XCTAssertEqual(TriggerKey.fn.displayName, "Fn")
        XCTAssertEqual(TriggerKey.customShortcut.displayName, "Custom shortcut")
    }
}

final class RecordingModeTests: XCTestCase {
    func testRawValuesAreStableForPersistence() {
        XCTAssertEqual(RecordingMode.pushToTalk.rawValue, "pushToTalk")
        XCTAssertEqual(RecordingMode.toggle.rawValue, "toggle")
    }

    func testAllCases() {
        XCTAssertEqual(Set(RecordingMode.allCases), [.pushToTalk, .toggle])
    }

    func testDefaultIsPushToTalk() {
        XCTAssertEqual(RecordingMode.default, .pushToTalk)
    }

    func testDisplayNames() {
        XCTAssertEqual(RecordingMode.pushToTalk.displayName, "Push to talk")
        XCTAssertEqual(RecordingMode.toggle.displayName, "Toggle")
    }
}
