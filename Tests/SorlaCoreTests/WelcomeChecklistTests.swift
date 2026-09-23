import XCTest
@testable import SorlaCore

final class WelcomeChecklistTests: XCTestCase {
    func testShownOnFirstLaunchEvenWithEverythingGranted() {
        XCTAssertTrue(WelcomeChecklist.shouldShow(hasCompletedOnboarding: false, microphone: .granted, isAccessibilityTrusted: true))
    }

    func testShownAgainWhileMicrophoneAccessIsMissing() {
        XCTAssertTrue(WelcomeChecklist.shouldShow(hasCompletedOnboarding: true, microphone: .denied, isAccessibilityTrusted: true))
        XCTAssertTrue(WelcomeChecklist.shouldShow(hasCompletedOnboarding: true, microphone: .notDetermined, isAccessibilityTrusted: true))
    }

    func testShownAgainWhileAccessibilityIsMissing() {
        XCTAssertTrue(WelcomeChecklist.shouldShow(hasCompletedOnboarding: true, microphone: .granted, isAccessibilityTrusted: false))
    }

    func testNotShownOnceCompletedAndGranted() {
        XCTAssertFalse(WelcomeChecklist.shouldShow(hasCompletedOnboarding: true, microphone: .granted, isAccessibilityTrusted: true))
    }

    func testMicrophoneRow() {
        XCTAssertEqual(WelcomeChecklist.microphoneRow(.granted), .done)
        XCTAssertEqual(WelcomeChecklist.microphoneRow(.notDetermined), .needsAction(.requestMicrophone, buttonTitle: "Allow", note: nil))
        XCTAssertEqual(WelcomeChecklist.microphoneRow(.denied), .needsAction(.openMicrophoneSettings, buttonTitle: "Open System Settings", note: nil))
    }

    func testAccessibilityRow() {
        XCTAssertEqual(WelcomeChecklist.accessibilityRow(isTrusted: true), .done)
        XCTAssertEqual(
            WelcomeChecklist.accessibilityRow(isTrusted: false),
            .needsAction(.openAccessibilitySettings, buttonTitle: "Open System Settings", note: nil)
        )
    }

    private func modelRow(isInstalled: Bool = false, isLoaded: Bool = false, loadFailed: Bool = false, model: ModelStatus) -> WelcomeRowStatus {
        WelcomeChecklist.modelRow(isInstalled: isInstalled, isLoaded: isLoaded, loadFailed: loadFailed, model: model)
    }

    func testModelRowShowsDownloadProgress() {
        XCTAssertEqual(modelRow(model: .downloading(version: "1.0.0", fraction: 0.34, isUpdate: false)), .inProgress("Downloading model… 34%"))
    }

    func testModelRowShowsPreparing() {
        XCTAssertEqual(modelRow(model: .preparing(version: "1.0.0", isUpdate: false)), .inProgress("Preparing model… ~1 min"))
        XCTAssertEqual(modelRow(model: .waitingToInstall(version: "1.0.0")), .inProgress("Preparing model… ~1 min"))
    }

    func testInstalledModelStillLoadingIsNotDone() {
        XCTAssertEqual(modelRow(isInstalled: true, model: .installed(version: "1.0.0")), .inProgress("Preparing model… ~1 min"))
    }

    func testLoadedModelIsDone() {
        XCTAssertEqual(modelRow(isInstalled: true, isLoaded: true, model: .upToDate(version: "1.0.0")), .done)
        XCTAssertEqual(modelRow(isInstalled: true, isLoaded: true, model: .downloading(version: "1.1.0", fraction: 0.5, isUpdate: true)), .done)
    }

    func testMissingModelOffersADownload() {
        XCTAssertEqual(modelRow(model: .notInstalled), .needsAction(.downloadModel, buttonTitle: "Download", note: "Not installed"))
    }

    func testFailedDownloadOffersARetry() {
        XCTAssertEqual(
            modelRow(model: .failed(.network, isUpdate: false)),
            .needsAction(.downloadModel, buttonTitle: "Try Again", note: "Model download failed")
        )
    }

    func testFailedLoadRetriesLoading() {
        XCTAssertEqual(
            modelRow(isInstalled: true, loadFailed: true, model: .installed(version: "1.0.0")),
            .needsAction(.reloadModel, buttonTitle: "Try Again", note: "Model couldn't be loaded")
        )
    }

    func testReadyOnlyWhenBothPermissionsAndTheLoadedModelAreDone() {
        let loaded = modelRow(isInstalled: true, isLoaded: true, model: .upToDate(version: "1.0.0"))
        let loading = modelRow(isInstalled: true, model: .installed(version: "1.0.0"))
        let granted = WelcomeChecklist.microphoneRow(.granted)
        let trusted = WelcomeChecklist.accessibilityRow(isTrusted: true)

        XCTAssertTrue(WelcomeChecklist.isReady(microphone: granted, accessibility: trusted, model: loaded))
        XCTAssertFalse(WelcomeChecklist.isReady(microphone: granted, accessibility: trusted, model: loading))
        XCTAssertFalse(WelcomeChecklist.isReady(microphone: WelcomeChecklist.microphoneRow(.denied), accessibility: trusted, model: loaded))
        XCTAssertFalse(WelcomeChecklist.isReady(microphone: granted, accessibility: WelcomeChecklist.accessibilityRow(isTrusted: false), model: loaded))
    }

    func testReadinessLineUsesTheTriggerHint() {
        XCTAssertEqual(
            WelcomeChecklist.readinessLine(isReady: true, trigger: .rightCommand, mode: .pushToTalk, customShortcut: nil),
            "Sorla is ready. Hold Right ⌘ to dictate."
        )
        XCTAssertEqual(
            WelcomeChecklist.readinessLine(isReady: false, trigger: .rightCommand, mode: .pushToTalk, customShortcut: nil),
            "Dictation works once all three are done."
        )
    }
}
