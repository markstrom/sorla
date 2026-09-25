import XCTest
@testable import SorlaCore

// #74: macOS 27 calls the pane "Device Control and Data Access"; macOS 14–26 still say "Accessibility".
final class AccessibilityPaneNameTests: XCTestCase {
    func testMacOS14And26SayAccessibility() {
        XCTAssertEqual(AccessibilityPaneName.for(majorVersion: 14), "Accessibility")
        XCTAssertEqual(AccessibilityPaneName.for(majorVersion: 26), "Accessibility")
    }

    func testMacOS27SaysDeviceControlAndDataAccess() {
        XCTAssertEqual(AccessibilityPaneName.for(majorVersion: 27), "Device Control and Data Access")
        XCTAssertEqual(AccessibilityPaneName.for(majorVersion: 28), "Device Control and Data Access")
    }

    func testCurrentFollowsTheRunningSystem() {
        let running = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        XCTAssertEqual(AccessibilityPaneName.current, AccessibilityPaneName.for(majorVersion: running))
        AccessibilityPaneName.$systemMajorVersion.withValue(26) {
            XCTAssertEqual(AccessibilityPaneName.current, "Accessibility")
        }
        AccessibilityPaneName.$systemMajorVersion.withValue(27) {
            XCTAssertEqual(AccessibilityPaneName.current, "Device Control and Data Access")
        }
    }

    // The deep link still opens the pane on macOS 27, so it stays the same for every version.
    func testTheSettingsLinkIsTheSameOnEveryVersion() {
        for version in [14, 26, 27] {
            AccessibilityPaneName.$systemMajorVersion.withValue(version) {
                XCTAssertEqual(
                    SorlaIssue.accessibilityAccessNeeded.settingsURL,
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
                )
            }
        }
    }
}
