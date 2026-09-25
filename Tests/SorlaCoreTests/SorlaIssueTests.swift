import XCTest
@testable import SorlaCore

final class SorlaIssueTests: XCTestCase {
    // Names of System Settings items follow the Mac's language unless pinned; these check an English Mac (#79).
    override func invokeTest() {
        SystemSettingsName.$systemLanguage.withValue(.english) { super.invokeTest() }
    }

    func testMicrophoneAccessNeededMenuTitle() {
        XCTAssertEqual(SorlaIssue.microphoneAccessNeeded.menuTitle, "Microphone access needed")
    }

    func testMicrophoneAccessNeededSettingsURL() {
        XCTAssertEqual(
            SorlaIssue.microphoneAccessNeeded.settingsURL,
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        )
    }

    func testAccessibilityAccessNeededMenuTitleNamesThePaneOfTheRunningMacOS() {
        SystemSettingsName.$systemMajorVersion.withValue(26) {
            XCTAssertEqual(SorlaIssue.accessibilityAccessNeeded.menuTitle, "Accessibility permission needed to paste")
        }
        SystemSettingsName.$systemMajorVersion.withValue(27) {
            XCTAssertEqual(SorlaIssue.accessibilityAccessNeeded.menuTitle, "Device Control and Data Access permission needed to paste")
        }
    }

    func testAccessibilityAccessNeededSettingsURL() {
        XCTAssertEqual(
            SorlaIssue.accessibilityAccessNeeded.settingsURL,
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        )
    }

    func testModelNotLoadedMenuTitle() {
        XCTAssertEqual(SorlaIssue.modelNotLoaded.menuTitle, "Model couldn't be loaded")
    }

    func testModelNotLoadedHasNoSettingsURL() {
        XCTAssertNil(SorlaIssue.modelNotLoaded.settingsURL)
    }

    func testNoInputDeviceMenuTitlePointsToSoundInput() {
        XCTAssertEqual(SorlaIssue.noInputDevice.menuTitle, "No microphone found — check the sound input in Sound settings")
        XCTAssertEqual(SorlaIssue.noInputDevice.settingsURL, URL(string: "x-apple.systempreferences:com.apple.preference.sound?input"))
    }

    func testTranscriptionFailedMenuTitle() {
        XCTAssertEqual(SorlaIssue.transcriptionFailed.menuTitle, "Couldn't transcribe the last recording")
    }

    func testTranscriptionFailedHasNoSettingsURL() {
        XCTAssertNil(SorlaIssue.transcriptionFailed.settingsURL)
    }

    func testModelDownloadFailedWording() {
        XCTAssertEqual(SorlaIssue.modelDownloadFailed.menuTitle, "Model download failed")
        XCTAssertNil(SorlaIssue.modelDownloadFailed.settingsURL)
    }

    func testModelUpdateFailedWording() {
        XCTAssertEqual(SorlaIssue.modelUpdateFailed.menuTitle, "Model update failed")
        XCTAssertNil(SorlaIssue.modelUpdateFailed.settingsURL)
    }
}
