import XCTest
@testable import SorlaCore

final class SorlaIssueTests: XCTestCase {
    func testMicrophoneAccessNeededMenuTitle() {
        XCTAssertEqual(SorlaIssue.microphoneAccessNeeded.menuTitle, "Microphone access needed")
    }

    func testMicrophoneAccessNeededNotificationBody() {
        XCTAssertEqual(
            SorlaIssue.microphoneAccessNeeded.notificationBody,
            "Couldn't record — grant Sorla access to the microphone in System Settings."
        )
    }

    func testMicrophoneAccessNeededSettingsURL() {
        XCTAssertEqual(
            SorlaIssue.microphoneAccessNeeded.settingsURL,
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        )
    }

    func testAccessibilityAccessNeededMenuTitle() {
        XCTAssertEqual(SorlaIssue.accessibilityAccessNeeded.menuTitle, "Accessibility access needed to paste")
    }

    func testAccessibilityAccessNeededNotificationBody() {
        XCTAssertEqual(
            SorlaIssue.accessibilityAccessNeeded.notificationBody,
            "Your text is on the clipboard — press ⌘V. Grant Accessibility access so Sorla can paste for you."
        )
    }

    func testAccessibilityAccessNeededSettingsURL() {
        XCTAssertEqual(
            SorlaIssue.accessibilityAccessNeeded.settingsURL,
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        )
    }

    func testModelNotLoadedMenuTitle() {
        XCTAssertEqual(SorlaIssue.modelNotLoaded.menuTitle, "Swedish model couldn't be loaded")
    }

    func testModelNotLoadedNotificationBody() {
        XCTAssertEqual(
            SorlaIssue.modelNotLoaded.notificationBody,
            "The Swedish model couldn't be loaded. Dictation won't work until this is fixed."
        )
    }

    func testModelNotLoadedHasNoSettingsURL() {
        XCTAssertNil(SorlaIssue.modelNotLoaded.settingsURL)
    }

    func testNoInputDeviceHasNoMenuTitle() {
        XCTAssertNil(SorlaIssue.noInputDevice.menuTitle)
    }

    func testNoInputDeviceNotificationBody() {
        XCTAssertEqual(SorlaIssue.noInputDevice.notificationBody, "Couldn't start recording: no microphone found.")
    }

    func testNoInputDeviceHasNoSettingsURL() {
        XCTAssertNil(SorlaIssue.noInputDevice.settingsURL)
    }

    func testTranscriptionFailedHasNoMenuTitle() {
        XCTAssertNil(SorlaIssue.transcriptionFailed.menuTitle)
    }

    func testTranscriptionFailedNotificationBody() {
        XCTAssertEqual(SorlaIssue.transcriptionFailed.notificationBody, "Couldn't transcribe that recording.")
    }

    func testTranscriptionFailedHasNoSettingsURL() {
        XCTAssertNil(SorlaIssue.transcriptionFailed.settingsURL)
    }

    func testModelDownloadFailedWording() {
        XCTAssertEqual(SorlaIssue.modelDownloadFailed.menuTitle, "Swedish model download failed")
        XCTAssertEqual(
            SorlaIssue.modelDownloadFailed.notificationBody,
            "Couldn't download the Swedish model. Open the Sorla menu to try again."
        )
        XCTAssertNil(SorlaIssue.modelDownloadFailed.settingsURL)
    }

    func testModelUpdateFailedWording() {
        XCTAssertEqual(SorlaIssue.modelUpdateFailed.menuTitle, "Model update failed")
        XCTAssertEqual(
            SorlaIssue.modelUpdateFailed.notificationBody,
            "Couldn't install the model update. Sorla keeps using the current model."
        )
        XCTAssertNil(SorlaIssue.modelUpdateFailed.settingsURL)
    }
}
