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

    func testPushToTalkWaitsForTheReleaseSoShortcutsStaySilent() {
        XCTAssertTrue(DictationGate.waitsForRelease(mode: .pushToTalk))
        XCTAssertFalse(DictationGate.waitsForRelease(mode: .toggle))
    }
}
