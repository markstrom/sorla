import XCTest
@testable import SorlaCore

final class ModelUpdatePolicyTests: XCTestCase {
    private let latest = ModelManifestTests.release(version: "1.1.0")

    func testLaunchWithDefaultSettingsAndAnInstalledModelDoesNothing() {
        XCTAssertEqual(ModelUpdatePolicy.launchAction(isInstalled: true, autoCheck: false), .none)
    }

    func testLaunchWithAutomaticChecksChecks() {
        XCTAssertEqual(ModelUpdatePolicy.launchAction(isInstalled: true, autoCheck: true), .check)
    }

    func testLaunchWithoutAModelInstallsRegardlessOfSettings() {
        XCTAssertEqual(ModelUpdatePolicy.launchAction(isInstalled: false, autoCheck: false), .install)
        XCTAssertEqual(ModelUpdatePolicy.launchAction(isInstalled: false, autoCheck: true), .install)
    }

    func testSameVersionIsUpToDate() {
        let release = ModelManifestTests.release(version: "1.0.0")
        for autoDownload in [false, true] {
            XCTAssertEqual(ModelUpdatePolicy.decide(installedVersion: "1.0.0", isInstalled: true, latest: release, autoDownload: autoDownload), .none)
        }
    }

    func testOlderPublishedVersionIsIgnored() {
        let release = ModelManifestTests.release(version: "0.9.0")

        XCTAssertEqual(ModelUpdatePolicy.decide(installedVersion: "1.0.0", isInstalled: true, latest: release, autoDownload: true), .none)
    }

    func testNewerVersionNotifiesWhenAutomaticDownloadIsOff() {
        XCTAssertEqual(
            ModelUpdatePolicy.decide(installedVersion: "1.0.0", isInstalled: true, latest: latest, autoDownload: false),
            .notify(version: "1.1.0")
        )
    }

    func testNewerVersionDownloadsWhenAutomaticDownloadIsOn() {
        XCTAssertEqual(
            ModelUpdatePolicy.decide(installedVersion: "1.0.0", isInstalled: true, latest: latest, autoDownload: true),
            .download(version: "1.1.0")
        )
    }

    func testVersionsCompareNumerically() {
        let release = ModelManifestTests.release(version: "1.10.0")

        XCTAssertEqual(
            ModelUpdatePolicy.decide(installedVersion: "1.9.0", isInstalled: true, latest: release, autoDownload: false),
            .notify(version: "1.10.0")
        )
    }

    func testMissingModelIsAlwaysDownloaded() {
        XCTAssertEqual(
            ModelUpdatePolicy.decide(installedVersion: nil, isInstalled: false, latest: latest, autoDownload: false),
            .download(version: "1.1.0")
        )
    }

    func testInstalledModelWithoutAKnownVersionIsOfferedTheUpdate() {
        XCTAssertEqual(
            ModelUpdatePolicy.decide(installedVersion: nil, isInstalled: true, latest: latest, autoDownload: false),
            .notify(version: "1.1.0")
        )
    }

    func testIncompatibleReleasesAreNeverInstalled() {
        let release = ModelManifestTests.release(version: "2.0.0", loader: ModelLoader(library: "FluidAudio", version: "v4"))

        XCTAssertEqual(ModelUpdatePolicy.decide(installedVersion: "1.0.0", isInstalled: true, latest: release, autoDownload: true), .none)
        XCTAssertEqual(ModelUpdatePolicy.decide(installedVersion: nil, isInstalled: false, latest: release, autoDownload: true), .none)
    }

    func testAVersionThatFailedBeforeIsOnlyOfferedInsteadOfDownloadedAutomatically() {
        XCTAssertEqual(
            ModelUpdatePolicy.decide(installedVersion: "1.0.0", isInstalled: true, latest: latest, autoDownload: true, failedVersion: "1.1.0"),
            .notify(version: "1.1.0")
        )
    }

    func testAnOlderFailedVersionDoesNotHoldBackANewerOne() {
        XCTAssertEqual(
            ModelUpdatePolicy.decide(installedVersion: "1.0.0", isInstalled: true, latest: latest, autoDownload: true, failedVersion: "1.0.5"),
            .download(version: "1.1.0")
        )
    }

    func testAMissingModelIsDownloadedEvenIfThatVersionFailedBefore() {
        XCTAssertEqual(
            ModelUpdatePolicy.decide(installedVersion: nil, isInstalled: false, latest: latest, autoDownload: false, failedVersion: "1.1.0"),
            .download(version: "1.1.0")
        )
    }
}
