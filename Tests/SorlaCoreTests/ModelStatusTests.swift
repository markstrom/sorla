import XCTest
@testable import SorlaCore

final class ModelStatusTests: XCTestCase {
    func testSettingsText() {
        XCTAssertEqual(ModelStatus.notInstalled.settingsText, "Not installed")
        XCTAssertEqual(ModelStatus.installed(version: "1.0.0").settingsText, "Version 1.0.0")
        XCTAssertEqual(ModelStatus.installed(version: nil).settingsText, "Installed")
        XCTAssertEqual(ModelStatus.checking.settingsText, "Checking for updates…")
        XCTAssertEqual(ModelStatus.upToDate(version: "1.0.0").settingsText, "Up to date · Version 1.0.0")
        XCTAssertEqual(ModelStatus.updateAvailable(version: "1.1.0").settingsText, "Update available · Version 1.1.0")
        XCTAssertEqual(ModelStatus.downloading(version: "1.1.0", fraction: 0.345, isUpdate: true).settingsText, "Downloading 34%")
        XCTAssertEqual(ModelStatus.preparing(version: "1.1.0", isUpdate: true).settingsText, "Preparing… ~1 min")
        XCTAssertEqual(ModelStatus.waitingToInstall(version: "1.1.0").settingsText, "Installing when dictation ends…")
        XCTAssertEqual(
            ModelStatus.failed(.network, isUpdate: false).settingsText,
            "Failed: Couldn't reach Hugging Face. Check your internet connection."
        )
        XCTAssertEqual(ModelStatus.checkFailed(.invalidManifest).settingsText, "Failed: The model list couldn't be read.")
    }

    func testDiskSpaceReasonIsReadable() {
        XCTAssertEqual(
            ModelInstallError.insufficientDiskSpace(required: 1_376_514_942).reason,
            "Not enough disk space (1.4 GB free needed)."
        )
    }

    func testPercentIsClampedAndRoundedDown() {
        XCTAssertEqual(ModelStatus.downloading(version: "1", fraction: 0.999, isUpdate: false).settingsText, "Downloading 99%")
        XCTAssertEqual(ModelStatus.downloading(version: "1", fraction: 1.2, isUpdate: false).settingsText, "Downloading 100%")
        XCTAssertEqual(ModelStatus.downloading(version: "1", fraction: -1, isUpdate: false).settingsText, "Downloading 0%")
    }

    func testBusyStates() {
        XCTAssertTrue(ModelStatus.checking.isBusy)
        XCTAssertTrue(ModelStatus.downloading(version: "1", fraction: 0, isUpdate: false).isBusy)
        XCTAssertTrue(ModelStatus.preparing(version: "1", isUpdate: false).isBusy)
        XCTAssertTrue(ModelStatus.waitingToInstall(version: "1").isBusy)
        XCTAssertFalse(ModelStatus.upToDate(version: "1").isBusy)
        XCTAssertFalse(ModelStatus.failed(.network, isUpdate: false).isBusy)
    }
}
