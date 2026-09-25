import XCTest
@testable import SorlaCore

final class MenuStatusRowTests: XCTestCase {
    // Names of System Settings items follow the Mac's language unless pinned; these check an English Mac (#79).
    override func invokeTest() {
        SystemSettingsName.$systemLanguage.withValue(.english) { super.invokeTest() }
    }

    private func row(
        microphoneDenied: Bool = false,
        accessibilityMissing: Bool = false,
        model: ModelStatus = .installed(version: "1.0.0"),
        modelLoadFailed: Bool = false,
        modelLoading: Bool = false,
        appReplaced: Bool = false,
        canRestart: Bool = true,
        transient: TransientMenuStatus? = nil,
        appUpdate: AppUpdateOffer? = nil,
        now: Date = MenuStatusRowTests.shownAt
    ) -> MenuStatusRow? {
        MenuStatusRow.current(
            microphoneDenied: microphoneDenied,
            accessibilityMissing: accessibilityMissing,
            model: model,
            modelLoadFailed: modelLoadFailed,
            modelLoading: modelLoading,
            appReplaced: appReplaced,
            canRestart: canRestart,
            transient: transient,
            appUpdate: appUpdate,
            now: now
        )
    }

    private static let shownAt = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private var muted: TransientMenuStatus? { TransientMenuStatus(issue: .microphoneMuted, at: MenuStatusRowTests.shownAt) }

    func testLoadingAnInstalledModelSaysHowLongItTakes() {
        XCTAssertEqual(row(modelLoading: true), MenuStatusRow(title: "Preparing model… ~1 min", action: .openSettings))
    }

    func testNothingToShowHidesTheRow() {
        XCTAssertNil(row())
        XCTAssertNil(row(model: .upToDate(version: "1.0.0")))
        XCTAssertNil(row(model: .checking))
        XCTAssertNil(row(model: .checkFailed(.network)))
    }

    func testMicrophoneComesFirst() {
        let row = row(microphoneDenied: true, accessibilityMissing: true, model: .failed(.network, isUpdate: false), modelLoadFailed: true)

        XCTAssertEqual(row, MenuStatusRow(title: "Microphone access needed", action: .showWelcome))
    }

    func testAccessibilityComesBeforeTheModel() {
        let row = SystemSettingsName.$systemMajorVersion.withValue(26) {
            self.row(accessibilityMissing: true, model: .downloading(version: "1.0.0", fraction: 0.5, isUpdate: false))
        }

        XCTAssertEqual(row, MenuStatusRow(title: "Accessibility permission needed to paste", action: .showWelcome))
    }

    func testDownloadProgressIsShown() {
        XCTAssertEqual(
            row(model: .downloading(version: "1.0.0", fraction: 0.34, isUpdate: false)),
            MenuStatusRow(title: "Downloading model… 34%", action: .openSettings)
        )
        XCTAssertEqual(
            row(model: .preparing(version: "1.0.0", isUpdate: false)),
            MenuStatusRow(title: "Preparing model… ~1 min", action: .openSettings)
        )
        XCTAssertEqual(
            row(model: .waitingToInstall(version: "1.1.0")),
            MenuStatusRow(title: "Preparing model… ~1 min", action: .openSettings)
        )
    }

    // #76: a blocker that badges the icon names itself and opens the setup window, whose row has the fix.
    func testAFailedFirstDownloadOpensTheSetupWindow() {
        XCTAssertEqual(
            row(model: .failed(.network, isUpdate: false)),
            MenuStatusRow(title: "Model download failed", action: .showWelcome)
        )
        XCTAssertEqual(row(model: .failed(.insufficientDiskSpace(required: 1_000_000_000), isUpdate: false))?.action, .showWelcome)
    }

    // The installed model still works, so a failed update is no blocker and retries from the menu.
    func testAFailedUpdateOffersARetry() {
        XCTAssertEqual(
            row(model: .failed(.selfTestFailed, isUpdate: true)),
            MenuStatusRow(title: "Model update failed — Try Again", action: .downloadModel)
        )
    }

    func testAMissingModelOpensTheSetupWindow() {
        XCTAssertEqual(
            row(model: .notInstalled),
            MenuStatusRow(title: "Model not installed", action: .showWelcome)
        )
    }

    func testALoadFailureOpensTheSetupWindow() {
        XCTAssertEqual(
            row(modelLoadFailed: true),
            MenuStatusRow(title: "Model couldn't be loaded", action: .showWelcome)
        )
        XCTAssertEqual(row(model: .upToDate(version: "1.0.0"), modelLoadFailed: true), .modelLoadFailed)
    }

    // The dictation refusal points to this row, so it must be the one the menu shows.
    func testALoadFailureComesBeforeUpdateProgressButAfterPermissions() {
        XCTAssertEqual(row(model: .downloading(version: "1.1.0", fraction: 0.5, isUpdate: true), modelLoadFailed: true), .modelLoadFailed)
        XCTAssertEqual(row(model: .preparing(version: "1.1.0", isUpdate: true), modelLoadFailed: true), .modelLoadFailed)
        XCTAssertEqual(row(model: .failed(.network, isUpdate: true), modelLoadFailed: true), .modelLoadFailed)
        XCTAssertEqual(row(accessibilityMissing: true, modelLoadFailed: true)?.action, .showWelcome)
    }

    func testFailuresComeBeforeAnAvailableUpdate() {
        XCTAssertEqual(row(model: .updateAvailable(version: "1.1.0"), modelLoadFailed: true), .modelLoadFailed)
    }

    func testAvailableUpdateComesLast() {
        XCTAssertEqual(
            row(model: .updateAvailable(version: "1.1.0")),
            MenuStatusRow(title: "Model update available (1.1.0)", action: .downloadModel)
        )
    }

    func testTransientExplanationsHaveTheirOwnActions() {
        XCTAssertEqual(muted?.row, MenuStatusRow(title: "Microphone seems to be muted — check the sound input in Sound settings", action: .openSoundSettings))
        XCTAssertEqual(
            TransientMenuStatus(issue: .textOnClipboard(pasteLast: .shortcut("⌃⌥V")), at: Self.shownAt)?.row,
            MenuStatusRow(title: "Text is on the clipboard — press ⌃⌥V", action: .pasteLastTranscription)
        )
        XCTAssertEqual(
            TransientMenuStatus(issue: .textOnClipboard(pasteLast: nil), at: Self.shownAt)?.row,
            MenuStatusRow(title: "Text is on the clipboard — press ⌘V", action: .pasteLastTranscription)
        )
        XCTAssertEqual(
            TransientMenuStatus(issue: .noInputDevice, at: Self.shownAt)?.row,
            MenuStatusRow(title: "No microphone found — check the sound input in Sound settings", action: .openSoundSettings)
        )
        XCTAssertEqual(
            TransientMenuStatus(issue: .transcriptionFailed, at: Self.shownAt)?.row,
            MenuStatusRow(title: "Couldn't transcribe the last recording", action: .dismiss)
        )
    }

    // These already have a row of their own that lasts as long as the problem.
    func testLastingProblemsAreNeverTransient() {
        let issues: [SorlaIssue] = [.microphoneAccessNeeded, .accessibilityAccessNeeded, .modelNotLoaded, .modelDownloadFailed, .modelUpdateFailed, .appReplaced]
        for issue in issues {
            XCTAssertNil(TransientMenuStatus(issue: issue, at: Self.shownAt), "\(issue)")
        }
    }

    func testATransientExplanationShowsWhenNothingElseDoes() {
        XCTAssertEqual(row(transient: muted), muted?.row)
    }

    func testATransientExplanationLastsFiveMinutes() {
        XCTAssertEqual(row(transient: muted, now: Self.shownAt.addingTimeInterval(4 * 60 + 59)), muted?.row)
        XCTAssertNil(row(transient: muted, now: Self.shownAt.addingTimeInterval(5 * 60)))
        XCTAssertEqual(muted?.isExpired(at: Self.shownAt.addingTimeInterval(5 * 60)), true)
        XCTAssertEqual(muted?.isExpired(at: Self.shownAt), false)
    }

    func testLastingProblemsAndProgressOutrankATransientExplanation() {
        XCTAssertEqual(row(microphoneDenied: true, transient: muted)?.action, .showWelcome)
        XCTAssertEqual(row(accessibilityMissing: true, transient: muted)?.action, .showWelcome)
        XCTAssertEqual(row(modelLoadFailed: true, transient: muted), .modelLoadFailed)
        XCTAssertEqual(row(model: .downloading(version: "1.1.0", fraction: 0.5, isUpdate: true), transient: muted)?.action, .openSettings)
        XCTAssertEqual(row(model: .preparing(version: "1.1.0", isUpdate: true), transient: muted)?.action, .openSettings)
        XCTAssertEqual(row(modelLoading: true, transient: muted)?.action, .openSettings)
    }

    func testATransientExplanationOutranksUpdateOffersAndUpdateFailures() {
        XCTAssertEqual(row(model: .updateAvailable(version: "1.1.0"), transient: muted), muted?.row)
        XCTAssertEqual(row(model: .failed(.network, isUpdate: true), transient: muted), muted?.row)
        XCTAssertEqual(row(model: .failed(.network, isUpdate: true), transient: muted, now: Self.shownAt.addingTimeInterval(600))?.action, .downloadModel)
    }

    func testANewerAppVersionOffersTheDownload() {
        XCTAssertEqual(row(appUpdate: .download(version: "1.1.0")), MenuStatusRow(title: "Sorla 1.1.0 is available — Download", action: .downloadApp))
    }

    func testTheAppUpdateComesJustBeforeTheModelUpdate() {
        XCTAssertEqual(row(model: .updateAvailable(version: "1.1.0"), appUpdate: .download(version: "1.2.0"))?.action, .downloadApp)
        XCTAssertEqual(row(model: .failed(.network, isUpdate: true), appUpdate: .download(version: "1.2.0"))?.action, .downloadModel)
        XCTAssertEqual(row(transient: muted, appUpdate: .download(version: "1.2.0")), muted?.row)
        XCTAssertEqual(row(model: .downloading(version: "1.1.0", fraction: 0.5, isUpdate: true), appUpdate: .download(version: "1.2.0"))?.action, .openSettings)
        XCTAssertEqual(row(modelLoading: true, appUpdate: .download(version: "1.2.0"))?.action, .openSettings)
        XCTAssertEqual(row(accessibilityMissing: true, appUpdate: .download(version: "1.2.0"))?.action, .showWelcome)
        XCTAssertEqual(row(modelLoadFailed: true, appUpdate: .download(version: "1.2.0")), .modelLoadFailed)
    }

    func testAnExpiredExplanationMakesWayForTheAppUpdate() {
        XCTAssertEqual(row(transient: muted, appUpdate: .download(version: "1.2.0"), now: Self.shownAt.addingTimeInterval(TransientMenuStatus.lifetime))?.action, .downloadApp)
    }

    // MARK: - Install and Relaunch (#29)

    func testTheMenuOffersInstallAndRelaunch() {
        XCTAssertEqual(row(appUpdate: .install(version: "1.1.0")), MenuStatusRow(title: "Sorla 1.1.0 is available — Install and Relaunch", action: .installApp))
        XCTAssertEqual(row(appUpdate: .homebrew(version: "1.1.0")), MenuStatusRow(title: "Sorla 1.1.0 is available — Update with Homebrew", action: .showUpdates))
        XCTAssertEqual(row(appUpdate: .installing(version: "1.1.0")), MenuStatusRow(title: "Installing Sorla 1.1.0…", action: .showUpdates))
        XCTAssertEqual(row(appUpdate: .failed(version: "1.1.0", .verification)), MenuStatusRow(title: "Couldn't install Sorla 1.1.0 — Download", action: .downloadApp))
    }

    func testAfterAnUpdateTheMenuSaysSoForAWhile() {
        let updated = TransientMenuStatus(updatedTo: "1.1.0", at: Self.shownAt)
        XCTAssertEqual(row(transient: updated), MenuStatusRow(title: "Sorla was updated to 1.1.0", action: .dismiss))
        XCTAssertNil(row(transient: updated, now: Self.shownAt.addingTimeInterval(TransientMenuStatus.lifetime)))
    }

    // MARK: - Replaced on disk (#7)

    func testAReplacedAppOffersARestart() {
        XCTAssertEqual(row(appReplaced: true), MenuStatusRow(title: "Sorla has been updated — Restart", action: .restart))
    }

    // A translocated copy's path is gone once it quits, so the user is sent to Applications instead.
    func testATranslocatedReplacedAppAsksToBeOpenedFromApplications() {
        XCTAssertEqual(
            row(appReplaced: true, canRestart: false),
            MenuStatusRow(title: "Sorla has been updated — Quit and open it from Applications", action: .quit)
        )
        XCTAssertNil(row(canRestart: false), "nothing to say until it is replaced")
    }

    // Its pastes are dropped until it restarts, and a restart retries the model too; permissions still need the user.
    func testARestartOutranksEverythingButPermissions() {
        let clipboard = TransientMenuStatus(issue: .textOnClipboard(pasteLast: nil), at: Self.shownAt)
        XCTAssertEqual(row(appReplaced: true, transient: clipboard)?.action, .restart)
        XCTAssertEqual(row(modelLoadFailed: true, appReplaced: true)?.action, .restart)
        XCTAssertEqual(row(model: .downloading(version: "1.1.0", fraction: 0.5, isUpdate: true), appReplaced: true)?.action, .restart)
        XCTAssertEqual(row(appReplaced: true, appUpdate: .download(version: "1.2.0"))?.action, .restart)
        XCTAssertEqual(row(microphoneDenied: true, appReplaced: true)?.action, .showWelcome)
        XCTAssertEqual(row(accessibilityMissing: true, appReplaced: true)?.action, .showWelcome)
    }

    // A paste that would have been dropped leaves the clipboard alone and asks for the restart (#72).
    func testAReplacedAppsPasteShowsTheRestartCue() {
        XCTAssertEqual(DictationCue(issue: .appReplaced), .restartNeeded)
        XCTAssertNil(SorlaIssue.appReplaced.settingsURL)
    }

    // MARK: - VoiceOver (#64)

    // VoiceOver may take ⌃⌥V (VO-V), and the row is already in the menu with the item it names.
    func testWithVoiceOverTheClipboardRowNamesTheMenuItem() {
        XCTAssertEqual(
            TransientMenuStatus(issue: .textOnClipboard(pasteLast: .menu), at: Self.shownAt)?.row,
            MenuStatusRow(title: "Text is on the clipboard — choose Paste Last Transcription", action: .pasteLastTranscription)
        )
    }

    func testTurningVoiceOverOnOrOffRewordsTheClipboardRowForTheSameTime() throws {
        let shortcut = try XCTUnwrap(TransientMenuStatus(issue: .textOnClipboard(pasteLast: .shortcut("⌃⌥V")), at: Self.shownAt))
        let menu = shortcut.rerouted(pasteLast: .menu)
        XCTAssertEqual(menu.row.title, "Text is on the clipboard — choose Paste Last Transcription")
        XCTAssertEqual(menu.shownAt, Self.shownAt)
        XCTAssertEqual(menu.rerouted(pasteLast: .shortcut("⌃⌥V")).row, shortcut.row)
    }

    // ⌘V was named because Paste Last couldn't help (no permission, a replaced app), so VoiceOver changes nothing.
    func testRerouteLeavesOtherRowsAlone() throws {
        let commandV = try XCTUnwrap(TransientMenuStatus(issue: .textOnClipboard(pasteLast: nil), at: Self.shownAt))
        XCTAssertEqual(commandV.rerouted(pasteLast: .menu), commandV)
        XCTAssertEqual(muted?.rerouted(pasteLast: .menu), muted)
        let updated = TransientMenuStatus(updatedTo: "1.2.0", at: Self.shownAt)
        XCTAssertEqual(updated.rerouted(pasteLast: .menu), updated)
    }
}
