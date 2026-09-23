import XCTest
@testable import PrataCore

final class PrataIssueTests: XCTestCase {
    func testMicrophoneAccessNeededMenuTitle() {
        XCTAssertEqual(PrataIssue.microphoneAccessNeeded.menuTitle, "Microphone access needed")
    }

    func testMicrophoneAccessNeededNotificationBody() {
        XCTAssertEqual(
            PrataIssue.microphoneAccessNeeded.notificationBody,
            "Couldn't record — grant Prata access to the microphone in System Settings."
        )
    }

    func testMicrophoneAccessNeededSettingsURL() {
        XCTAssertEqual(
            PrataIssue.microphoneAccessNeeded.settingsURL,
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        )
    }

    func testAccessibilityAccessNeededMenuTitle() {
        XCTAssertEqual(PrataIssue.accessibilityAccessNeeded.menuTitle, "Accessibility access needed to paste")
    }

    func testAccessibilityAccessNeededNotificationBody() {
        XCTAssertEqual(
            PrataIssue.accessibilityAccessNeeded.notificationBody,
            "Your text is on the clipboard — press ⌘V. Grant Accessibility access so Prata can paste for you."
        )
    }

    func testAccessibilityAccessNeededSettingsURL() {
        XCTAssertEqual(
            PrataIssue.accessibilityAccessNeeded.settingsURL,
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        )
    }

    func testModelNotLoadedMenuTitle() {
        XCTAssertEqual(PrataIssue.modelNotLoaded.menuTitle, "Swedish model couldn't be loaded")
    }

    func testModelNotLoadedNotificationBody() {
        XCTAssertEqual(
            PrataIssue.modelNotLoaded.notificationBody,
            "The Swedish model couldn't be loaded. Dictation won't work until this is fixed."
        )
    }

    func testModelNotLoadedHasNoSettingsURL() {
        XCTAssertNil(PrataIssue.modelNotLoaded.settingsURL)
    }

    func testNoInputDeviceHasNoMenuTitle() {
        XCTAssertNil(PrataIssue.noInputDevice.menuTitle)
    }

    func testNoInputDeviceNotificationBody() {
        XCTAssertEqual(PrataIssue.noInputDevice.notificationBody, "Couldn't start recording: no microphone found.")
    }

    func testNoInputDeviceHasNoSettingsURL() {
        XCTAssertNil(PrataIssue.noInputDevice.settingsURL)
    }

    func testTranscriptionFailedHasNoMenuTitle() {
        XCTAssertNil(PrataIssue.transcriptionFailed.menuTitle)
    }

    func testTranscriptionFailedNotificationBody() {
        XCTAssertEqual(PrataIssue.transcriptionFailed.notificationBody, "Couldn't transcribe that recording.")
    }

    func testTranscriptionFailedHasNoSettingsURL() {
        XCTAssertNil(PrataIssue.transcriptionFailed.settingsURL)
    }
}
