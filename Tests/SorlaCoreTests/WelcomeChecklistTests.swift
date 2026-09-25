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
            .needsAction(.openAccessibilitySettings, buttonTitle: "Open System Settings", note: "Switch already on? Quit and reopen Sorla.")
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
            "Hard to hold a key down? Choose Toggle under Mode in Settings."
        )
        XCTAssertNil(WelcomeChecklist.toggleModeTip(mode: .toggle))
    }

    // #61: Tab and VoiceOver's control list read a button without its row, so each says what it acts on.
    func testEachButtonIsNamedForWhatItActsOn() {
        let names = { (status: WelcomeRowStatus) in WelcomeChecklist.buttonName(status) }
        XCTAssertEqual(names(WelcomeChecklist.microphoneRow(.notDetermined)), "Allow microphone access")
        XCTAssertEqual(names(WelcomeChecklist.microphoneRow(.denied)), "Open Microphone in System Settings")
        AccessibilityPaneName.$systemMajorVersion.withValue(26) {
            XCTAssertEqual(names(WelcomeChecklist.accessibilityRow(isTrusted: false)), "Open Accessibility in System Settings")
        }
        AccessibilityPaneName.$systemMajorVersion.withValue(27) {
            XCTAssertEqual(names(WelcomeChecklist.accessibilityRow(isTrusted: false)), "Open Device Control and Data Access in System Settings")
        }
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

    // #75: the marker is a picture, so VoiceOver hears each row's state as its value.
    func testEachRowSaysItsStateToVoiceOver() {
        XCTAssertEqual(WelcomeRowStatus.done.accessibilityValue, "Done")
        XCTAssertEqual(WelcomeChecklist.microphoneRow(.notDetermined).accessibilityValue, "Needs action")
        XCTAssertEqual(modelRow(model: .preparing(version: "1", isUpdate: false)).accessibilityValue, "In progress")
    }

    func testNotesAndButtonTitlesComeFromTheStatus() {
        XCTAssertNil(WelcomeRowStatus.done.note)
        XCTAssertNil(WelcomeRowStatus.done.buttonTitle)
        XCTAssertEqual(WelcomeRowStatus.inProgress("Preparing model… ~1 min").note, "Preparing model… ~1 min")
        XCTAssertNil(WelcomeRowStatus.inProgress("x").buttonTitle)
        XCTAssertEqual(modelRow(model: .notInstalled).note, "Not installed")
        XCTAssertEqual(modelRow(model: .notInstalled).buttonTitle, "Download")
        XCTAssertNil(WelcomeChecklist.microphoneRow(.denied).note)
    }

    // #75: the window reserves room for every state a row can reach, so these must cover what the rows really show.
    func testEachRowListsTheStatesItCanShow() {
        XCTAssertEqual(WelcomeRow.microphone.possibleStatuses, [.granted, .notDetermined, .denied].map(WelcomeChecklist.microphoneRow))
        XCTAssertEqual(WelcomeRow.accessibility.possibleStatuses, [.done, WelcomeChecklist.accessibilityRow(isTrusted: false)])
        let model = WelcomeRow.model.possibleStatuses
        XCTAssertTrue(model.contains(.done))
        XCTAssertTrue(model.contains(.inProgress("Downloading model… 100%")))
        XCTAssertTrue(model.contains(.inProgress("Preparing model… ~1 min")))
        XCTAssertTrue(model.contains(modelRow(isInstalled: true, loadFailed: true, model: .installed(version: "1"))))
        XCTAssertTrue(model.contains(modelRow(model: .failed(.network, isUpdate: true))))
        XCTAssertTrue(model.contains(modelRow(model: .notInstalled)))
        XCTAssertTrue(model.contains { $0.note?.hasPrefix("Not enough disk space") == true })
        let titles = Set(WelcomeRow.allCases.flatMap(\.possibleStatuses).compactMap(\.buttonTitle))
        XCTAssertEqual(titles, ["Allow", "Open System Settings", "Download", "Try Again"])
    }

    func testRowTitlesAndPurposes() {
        XCTAssertEqual(WelcomeRow.microphone.title, "Microphone")
        XCTAssertEqual(WelcomeRow.model.title, "Model")
        XCTAssertEqual(WelcomeRow.accessibility.purpose, "So Sorla can paste where you type.")
        XCTAssertEqual(WelcomeRow.model.purpose, "Pianissimo (Swedish)")
        AccessibilityPaneName.$systemMajorVersion.withValue(27) {
            XCTAssertEqual(WelcomeRow.accessibility.title, "Device Control and Data Access")
        }
    }

    // #73: each update switch says why someone would turn it on.
    func testTheUpdateSwitchesExplainWhyToTurnThemOn() {
        XCTAssertEqual(WelcomeChecklist.updatesHeading, "Updates")
        XCTAssertEqual(WelcomeChecklist.autoCheckReason, "Get fixes and new versions of the speech model without having to remember to check.")
        XCTAssertEqual(WelcomeChecklist.autoInstallReason, "Installs them when you haven't dictated for a while. Needs automatic checks.")
    }
}
