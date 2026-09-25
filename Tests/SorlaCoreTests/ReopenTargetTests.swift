import XCTest
@testable import SorlaCore

// #80: opening Sorla again during setup shows the setup window, not Settings on top of it.
final class ReopenTargetTests: XCTestCase {
    private func target(
        isSetupOpen: Bool = false,
        hasCompletedOnboarding: Bool = true,
        microphone: MicrophoneAccess = .granted,
        problems: Set<RecoveryProblem> = []
    ) -> ReopenTarget {
        ReopenTarget.onReopen(
            isSetupOpen: isSetupOpen,
            hasCompletedOnboarding: hasCompletedOnboarding,
            microphone: microphone,
            problems: problems
        )
    }

    func testASetUpSorlaOpensSettingsAsBefore() {
        XCTAssertEqual(target(), .settings)
    }

    func testAnOpenSetupWindowIsBroughtForward() {
        XCTAssertEqual(target(isSetupOpen: true), .setup, "even with nothing left to fix")
        XCTAssertEqual(target(isSetupOpen: true, problems: [.accessibility]), .setup)
        XCTAssertEqual(target(isSetupOpen: true, problems: [.restartRequired]), .setup, "the window the user is in")
    }

    func testUnfinishedOnboardingShowsTheSetupWindow() {
        XCTAssertEqual(target(hasCompletedOnboarding: false), .setup)
    }

    func testAChecklistBlockerShowsTheSetupWindow() {
        XCTAssertEqual(target(microphone: .notDetermined), .setup)
        XCTAssertEqual(target(microphone: .denied, problems: [.microphoneAccess]), .setup)
        XCTAssertEqual(target(problems: [.accessibility]), .setup)
        XCTAssertEqual(target(problems: [.model(.missing)]), .setup)
        XCTAssertEqual(target(problems: [.model(.downloadFailed)]), .setup)
        XCTAssertEqual(target(problems: [.model(.insufficientDiskSpace)]), .setup)
        XCTAssertEqual(target(problems: [.model(.loadFailed)]), .setup)
    }

    // They have dialogs of their own, not a row in the checklist.
    func testProblemsOutsideTheChecklistKeepSettings() {
        XCTAssertEqual(target(problems: [.microphoneStart]), .settings)
        XCTAssertEqual(target(problems: [.restartRequired]), .settings)
        XCTAssertEqual(target(problems: [.microphoneStart, .restartRequired]), .settings)
    }
}
