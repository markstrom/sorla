import XCTest
@testable import SorlaCore

final class DictationGateTests: XCTestCase {
    func testAnInstalledModelLetsDictationThrough() {
        XCTAssertNil(DictationGate.blockedMessage(isModelInstalled: true, model: .installed(version: "1.0.0")))
        XCTAssertNil(DictationGate.blockedMessage(isModelInstalled: true, model: .downloading(version: "1.1.0", fraction: 0.5, isUpdate: true)))
        XCTAssertNil(DictationGate.blockedMessage(isModelInstalled: true, model: .preparing(version: "1.0.0", isUpdate: false)))
    }

    func testDownloadingShowsTheProgress() {
        XCTAssertEqual(
            DictationGate.blockedMessage(isModelInstalled: false, model: .downloading(version: "1.0.0", fraction: 0.345, isUpdate: false)),
            "The model is still downloading (34%). Dictation will work once it's ready."
        )
    }

    func testPreparingSaysHowLongItTakes() {
        let message = "The model is being prepared (~1 min). Dictation will work once it's ready."
        XCTAssertEqual(DictationGate.blockedMessage(isModelInstalled: false, model: .preparing(version: "1.0.0", isUpdate: false)), message)
        XCTAssertEqual(DictationGate.blockedMessage(isModelInstalled: false, model: .waitingToInstall(version: "1.0.0")), message)
    }

    func testMissingModelPointsToTheMenu() {
        let message = "The model isn't installed yet. Open the Sorla menu to download it."
        XCTAssertEqual(DictationGate.blockedMessage(isModelInstalled: false, model: .notInstalled), message)
        XCTAssertEqual(DictationGate.blockedMessage(isModelInstalled: false, model: .failed(.network, isUpdate: false)), message)
    }

    func testAnInstalledModelThatIsStillLoadingIsRefused() {
        XCTAssertEqual(
            DictationGate.blockedMessage(isModelInstalled: true, isModelLoading: true, model: .installed(version: "1.0.0")),
            "The model is loading (~1 min). Dictation will work once it's ready."
        )
    }

    func testAnInstalledModelThatFailedToLoadIsRefusedWithTheRecoveryStep() {
        XCTAssertEqual(
            DictationGate.blockedMessage(isModelInstalled: true, didModelFailToLoad: true, model: .installed(version: "1.0.0")),
            "The model couldn't be loaded. Open the Sorla menu and choose “Model couldn't be loaded — Try Again”."
        )
    }

    func testAReadyModelKeepsDictatingWhileAnUpdateDownloads() {
        XCTAssertNil(DictationGate.blockedMessage(
            isModelInstalled: true,
            isModelLoading: false,
            didModelFailToLoad: false,
            model: .downloading(version: "1.1.0", fraction: 0.5, isUpdate: true)
        ))
    }

    func testASuccessfulRetryLetsDictationThroughAgain() {
        let model = ModelStatus.installed(version: "1.0.0")
        XCTAssertNotNil(DictationGate.blockedMessage(isModelInstalled: true, didModelFailToLoad: true, model: model))
        XCTAssertNotNil(DictationGate.blockedMessage(isModelInstalled: true, isModelLoading: true, model: model))
        XCTAssertNil(DictationGate.blockedMessage(isModelInstalled: true, model: model))
    }

    func testAModelOnItsWayRefusesWithAnHourglass() {
        let downloading = DictationGate.refusal(isModelInstalled: false, model: .downloading(version: "1.0.0", fraction: 0.345, isUpdate: false))
        XCTAssertEqual(downloading, .waitingForModel("The model is still downloading (34%). Dictation will work once it's ready."))
        XCTAssertEqual(downloading?.symbolName, "hourglass")
        XCTAssertEqual(DictationGate.refusal(isModelInstalled: false, model: .preparing(version: "1.0.0", isUpdate: false))?.symbolName, "hourglass")
        XCTAssertEqual(DictationGate.refusal(isModelInstalled: false, model: .waitingToInstall(version: "1.0.0"))?.symbolName, "hourglass")
        XCTAssertEqual(DictationGate.refusal(isModelInstalled: true, isModelLoading: true, model: .installed(version: "1.0.0"))?.symbolName, "hourglass")
    }

    func testAModelThatNeedsTheUserRefusesWithAWarning() {
        let failedLoad = DictationGate.refusal(isModelInstalled: true, didModelFailToLoad: true, model: .installed(version: "1.0.0"))
        XCTAssertEqual(failedLoad, .failed("The model couldn't be loaded. Open the Sorla menu and choose “Model couldn't be loaded — Try Again”."))
        XCTAssertEqual(DictationGate.refusal(isModelInstalled: false, model: .failed(.network, isUpdate: false))?.symbolName, "exclamationmark.triangle")
        XCTAssertEqual(DictationGate.refusal(isModelInstalled: false, model: .notInstalled)?.symbolName, "exclamationmark.triangle")
    }

    func testAReadyModelIsNotRefused() {
        XCTAssertNil(DictationGate.refusal(isModelInstalled: true, model: .downloading(version: "1.1.0", fraction: 0.5, isUpdate: true)))
    }

    func testPushToTalkWaitsForTheReleaseSoShortcutsStaySilent() {
        XCTAssertTrue(DictationGate.waitsForRelease(mode: .pushToTalk))
        XCTAssertFalse(DictationGate.waitsForRelease(mode: .toggle))
    }

    // A replaced Sorla can't paste, so a press isn't recorded and asks for a restart (#43, #72);
    // one that can't reopen itself falls back to the clipboard.
    func testAReplacedAppAsksForARestartInsteadOfRecording() {
        XCTAssertEqual(DictationGate.restartRefusal(isAppReplaced: true, canRestart: true), DictationRefusal(cue: .restartNeeded, problem: .restartRequired))
        XCTAssertNil(DictationGate.restartRefusal(isAppReplaced: true, canRestart: false))
        XCTAssertNil(DictationGate.restartRefusal(isAppReplaced: false, canRestart: true))
    }

    // #72: only a model that needs the user opens the Welcome window; one on its way just waits.
    func testOnlyAModelThatNeedsTheUserIsAProblem() {
        XCTAssertNil(DictationGate.modelProblem(isModelInstalled: false, model: .downloading(version: "1", fraction: 0.5, isUpdate: false)))
        XCTAssertNil(DictationGate.modelProblem(isModelInstalled: false, model: .preparing(version: "1", isUpdate: false)))
        XCTAssertNil(DictationGate.modelProblem(isModelInstalled: false, model: .waitingToInstall(version: "1")))
        XCTAssertNil(DictationGate.modelProblem(isModelInstalled: true, isModelLoading: true, model: .installed(version: "1")))
        XCTAssertNil(DictationGate.modelProblem(isModelInstalled: true, model: .installed(version: "1")))
        XCTAssertEqual(DictationGate.modelProblem(isModelInstalled: false, model: .notInstalled), .missing)
        XCTAssertEqual(DictationGate.modelProblem(isModelInstalled: false, model: .failed(.network, isUpdate: false)), .downloadFailed)
        XCTAssertEqual(DictationGate.modelProblem(isModelInstalled: false, model: .failed(.insufficientDiskSpace(required: 1_400_000_000), isUpdate: false)), .insufficientDiskSpace)
        XCTAssertEqual(DictationGate.modelProblem(isModelInstalled: true, didModelFailToLoad: true, model: .installed(version: "1")), .loadFailed)
    }

    func testAModelRefusalCarriesItsCueAndProblem() {
        XCTAssertEqual(
            DictationGate.modelRefusal(isModelInstalled: false, model: .notInstalled),
            DictationRefusal(cue: .failed("The model isn't installed yet. Open the Sorla menu to download it."), problem: .model(.missing))
        )
        let downloading = DictationGate.modelRefusal(isModelInstalled: false, model: .downloading(version: "1", fraction: 0.5, isUpdate: false))
        XCTAssertEqual(downloading?.cue.symbolName, "hourglass")
        XCTAssertNil(downloading?.problem)
        XCTAssertNil(DictationGate.modelRefusal(isModelInstalled: true, model: .installed(version: "1")))
    }
}
