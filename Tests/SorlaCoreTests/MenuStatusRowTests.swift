import XCTest
@testable import SorlaCore

final class MenuStatusRowTests: XCTestCase {
    private func row(
        microphoneDenied: Bool = false,
        accessibilityMissing: Bool = false,
        model: ModelStatus = .installed(version: "1.0.0"),
        modelLoadFailed: Bool = false,
        modelLoading: Bool = false,
        transient: TransientMenuStatus? = nil,
        appUpdate: String? = nil,
        now: Date = MenuStatusRowTests.shownAt
    ) -> MenuStatusRow? {
        MenuStatusRow.current(
            microphoneDenied: microphoneDenied,
            accessibilityMissing: accessibilityMissing,
            model: model,
            modelLoadFailed: modelLoadFailed,
            modelLoading: modelLoading,
            transient: transient,
            appUpdate: appUpdate,
            now: now
        )
    }

    private static let shownAt = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private let muted = TransientMenuStatus(issue: .microphoneMuted, at: MenuStatusRowTests.shownAt)

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
        let row = row(accessibilityMissing: true, model: .downloading(version: "1.0.0", fraction: 0.5, isUpdate: false))

        XCTAssertEqual(row, MenuStatusRow(title: "Accessibility access needed to paste", action: .showWelcome))
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

    func testFailedDownloadOffersARetry() {
        XCTAssertEqual(
            row(model: .failed(.network, isUpdate: false)),
            MenuStatusRow(title: "Model download failed — Try Again", action: .downloadModel)
        )
        XCTAssertEqual(
            row(model: .failed(.selfTestFailed, isUpdate: true)),
            MenuStatusRow(title: "Model update failed — Try Again", action: .downloadModel)
        )
    }

    func testMissingModelOffersADownload() {
        XCTAssertEqual(
            row(model: .notInstalled),
            MenuStatusRow(title: "Model not installed — Download", action: .downloadModel)
        )
    }

    func testLoadFailureRetriesLoadingTheModel() {
        XCTAssertEqual(
            row(modelLoadFailed: true),
            MenuStatusRow(title: "Model couldn't be loaded — Try Again", action: .reloadModel)
        )
        XCTAssertEqual(row(model: .upToDate(version: "1.0.0"), modelLoadFailed: true)?.action, .reloadModel)
    }

    // The dictation refusal points to this row, so it must be the one the menu shows.
    func testALoadFailureComesBeforeUpdateProgressButAfterPermissions() {
        XCTAssertEqual(row(model: .downloading(version: "1.1.0", fraction: 0.5, isUpdate: true), modelLoadFailed: true), .modelLoadFailed)
        XCTAssertEqual(row(model: .preparing(version: "1.1.0", isUpdate: true), modelLoadFailed: true), .modelLoadFailed)
        XCTAssertEqual(row(model: .failed(.network, isUpdate: true), modelLoadFailed: true), .modelLoadFailed)
        XCTAssertEqual(row(accessibilityMissing: true, modelLoadFailed: true)?.action, .showWelcome)
    }

    func testFailuresComeBeforeAnAvailableUpdate() {
        XCTAssertEqual(row(model: .updateAvailable(version: "1.1.0"), modelLoadFailed: true)?.action, .reloadModel)
    }

    func testAvailableUpdateComesLast() {
        XCTAssertEqual(
            row(model: .updateAvailable(version: "1.1.0")),
            MenuStatusRow(title: "Model update available (1.1.0)", action: .downloadModel)
        )
    }

    func testTransientExplanationsHaveTheirOwnActions() {
        XCTAssertEqual(muted?.row, MenuStatusRow(title: "Microphone seems to be muted — check Sound › Input", action: .openSoundSettings))
        XCTAssertEqual(
            TransientMenuStatus(issue: .textOnClipboard(pasteShortcut: "⌃⌥V"), at: Self.shownAt)?.row,
            MenuStatusRow(title: "Text is on the clipboard — press ⌃⌥V", action: .pasteLastTranscription)
        )
        XCTAssertEqual(
            TransientMenuStatus(issue: .noInputDevice, at: Self.shownAt)?.row,
            MenuStatusRow(title: "No microphone found — check Sound › Input", action: .openSoundSettings)
        )
        XCTAssertEqual(
            TransientMenuStatus(issue: .transcriptionFailed, at: Self.shownAt)?.row,
            MenuStatusRow(title: "Couldn't transcribe the last recording", action: .dismiss)
        )
    }

    // These already have a row of their own that lasts as long as the problem.
    func testLastingProblemsAreNeverTransient() {
        let issues: [SorlaIssue] = [.microphoneAccessNeeded, .accessibilityAccessNeeded, .modelNotLoaded, .modelDownloadFailed, .modelUpdateFailed]
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
        XCTAssertEqual(row(appUpdate: "1.1.0"), MenuStatusRow(title: "Sorla 1.1.0 is available — Download", action: .downloadApp))
    }

    func testTheAppUpdateComesJustBeforeTheModelUpdate() {
        XCTAssertEqual(row(model: .updateAvailable(version: "1.1.0"), appUpdate: "1.2.0")?.action, .downloadApp)
        XCTAssertEqual(row(model: .failed(.network, isUpdate: true), appUpdate: "1.2.0")?.action, .downloadModel)
        XCTAssertEqual(row(transient: muted, appUpdate: "1.2.0"), muted?.row)
        XCTAssertEqual(row(model: .downloading(version: "1.1.0", fraction: 0.5, isUpdate: true), appUpdate: "1.2.0")?.action, .openSettings)
        XCTAssertEqual(row(modelLoading: true, appUpdate: "1.2.0")?.action, .openSettings)
        XCTAssertEqual(row(accessibilityMissing: true, appUpdate: "1.2.0")?.action, .showWelcome)
        XCTAssertEqual(row(modelLoadFailed: true, appUpdate: "1.2.0"), .modelLoadFailed)
    }

    func testAnExpiredExplanationMakesWayForTheAppUpdate() {
        XCTAssertEqual(row(transient: muted, appUpdate: "1.2.0", now: Self.shownAt.addingTimeInterval(TransientMenuStatus.lifetime))?.action, .downloadApp)
    }
}
