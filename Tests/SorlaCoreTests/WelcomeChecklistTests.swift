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
            "Fix the items above to try dictation."
        )
    }

    // #20: holding a key can be hard, so push-to-talk users hear about the mode that only needs taps.
    func testTheToggleModeTipShowsOnlyInPushToTalk() {
        XCTAssertEqual(
            WelcomeChecklist.toggleModeTip(mode: .pushToTalk),
            "Hard to hold a key down? Choose Toggle under Mode in Settings: press once to start and again to stop."
        )
        XCTAssertNil(WelcomeChecklist.toggleModeTip(mode: .toggle))
    }

    // #61: Tab and VoiceOver's control list read a button without its row, so each says what it acts on.
    func testEachButtonIsNamedForWhatItActsOn() {
        let names = { (status: WelcomeRowStatus) in WelcomeChecklist.buttonName(status) }
        XCTAssertEqual(names(WelcomeChecklist.microphoneRow(.notDetermined)), "Allow microphone access")
        XCTAssertEqual(names(WelcomeChecklist.microphoneRow(.denied)), "Open Microphone in System Settings")
        XCTAssertEqual(names(WelcomeChecklist.accessibilityRow(isTrusted: false)), "Open Accessibility in System Settings")
        XCTAssertEqual(
            names(WelcomeChecklist.modelRow(isInstalled: false, isLoaded: false, loadFailed: false, model: .notInstalled)),
            "Download the speech model"
        )
        XCTAssertEqual(
            names(WelcomeChecklist.modelRow(isInstalled: false, isLoaded: false, loadFailed: false, model: .failed(.network, isUpdate: false))),
            "Try downloading the model again"
        )
        XCTAssertEqual(
            names(WelcomeChecklist.modelRow(isInstalled: true, isLoaded: false, loadFailed: true, model: .installed(version: "1"))),
            "Try loading the model again"
        )
        XCTAssertNil(names(.done))
        XCTAssertNil(names(.inProgress("Preparing model… ~1 min")))
    }

    // #72: nothing was downloaded, so the row gives the space the model needs and offers another try.
    func testTooLittleDiskSpaceSaysHowMuchIsNeededAndRetries() {
        let row = modelRow(model: .failed(.insufficientDiskSpace(required: 1_376_514_942), isUpdate: false))
        XCTAssertEqual(row, .needsAction(.downloadModel, buttonTitle: "Try Again", note: "Not enough disk space (1.4 GB free needed)."))
        XCTAssertEqual(WelcomeChecklist.buttonName(row), "Try downloading the model again")
    }

    func testTheWindowOffersNotNowUntilItIsReady() {
        XCTAssertEqual(WelcomeChecklist.closeButtonTitle(isReady: false), "Not now")
        XCTAssertEqual(WelcomeChecklist.closeButtonTitle(isReady: true), "Done")
    }

    // #72: the window opened for a blocked paste only claims the clipboard while the text is there,
    // and never suggests Paste Last, which needs the same access.
    func testABlockedPasteIsExplainedOnlyWhileTheTextIsOnTheClipboard() {
        XCTAssertEqual(
            WelcomeChecklist.pasteBlockedMessage(isTextOnClipboard: true, isAccessibilityTrusted: false),
            "The text is ready, but Sorla needs Accessibility access to paste it. The text is on the clipboard — close this window and press ⌘V where you were typing."
        )
        XCTAssertEqual(
            WelcomeChecklist.pasteBlockedMessage(isTextOnClipboard: true, isAccessibilityTrusted: true),
            "Your text is on the clipboard — close this window and press ⌘V where you were typing."
        )
        XCTAssertNil(WelcomeChecklist.pasteBlockedMessage(isTextOnClipboard: false, isAccessibilityTrusted: false))
        XCTAssertNil(WelcomeChecklist.pasteBlockedMessage(isTextOnClipboard: false, isAccessibilityTrusted: true))
    }

    // #73: the note follows the two toggles and never says "off" about something that is on.
    func testTheUpdatesNoteReflectsTheActualSettings() {
        XCTAssertEqual(
            WelcomeChecklist.updatesNote(autoCheck: false, autoInstall: false),
            "Automatic update checks and installation are off. You can turn them on in Settings."
        )
        XCTAssertEqual(
            WelcomeChecklist.updatesNote(autoCheck: true, autoInstall: false),
            "Sorla checks for updates automatically but doesn't install them. You can change this in Settings."
        )
        XCTAssertEqual(
            WelcomeChecklist.updatesNote(autoCheck: true, autoInstall: true),
            "Sorla checks for updates and installs them automatically. You can change this in Settings."
        )
        XCTAssertEqual(
            WelcomeChecklist.updatesNote(autoCheck: false, autoInstall: true),
            "Automatic update checks are off, so nothing is installed automatically until you turn them on in Settings."
        )
        XCTAssertEqual(WelcomeChecklist.updateSettingsButtonTitle, "Update Settings")
        XCTAssertEqual(WelcomeChecklist.updateSettingsButtonName, "Open Updates in Settings")
    }
}
