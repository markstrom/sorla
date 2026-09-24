import XCTest
@testable import SorlaCore

final class UpdateRowTests: XCTestCase {
    func testAppRowFollowsTheCheck() {
        XCTAssertEqual(UpdateRow.app(.notChecked), UpdateRow(text: nil))
        XCTAssertEqual(UpdateRow.app(.checking), UpdateRow(text: "Checking…", kind: .busy))
        XCTAssertEqual(UpdateRow.app(.upToDate), UpdateRow(text: "Latest", kind: .latest))
        XCTAssertEqual(UpdateRow.app(.available(version: "1.1.0")), UpdateRow(text: "1.1.0 available", action: .download))
    }

    func testAppFailuresUseTheirOwnWording() {
        XCTAssertEqual(
            UpdateRow.app(.failed(.offline)),
            UpdateRow(text: "Couldn't check for updates. Check your internet connection.", kind: .failure)
        )
        XCTAssertEqual(UpdateRow.app(.failed(.rateLimited)).text, AppUpdateFailure.rateLimited.message)
        XCTAssertEqual(UpdateRow.app(.failed(.badResponse)).text, AppUpdateFailure.badResponse.message)
    }

    func testModelRowKeepsItsInstallStates() {
        XCTAssertEqual(UpdateRow.model(.installed(version: "1.0.0")), UpdateRow(text: nil))
        XCTAssertEqual(UpdateRow.model(.checking), UpdateRow(text: "Checking…", kind: .busy))
        XCTAssertEqual(UpdateRow.model(.upToDate(version: "1.0.0")), UpdateRow(text: "Latest", kind: .latest))
        XCTAssertEqual(UpdateRow.model(.updateAvailable(version: "1.1.0")), UpdateRow(text: "1.1.0 available", action: .download))
        XCTAssertEqual(
            UpdateRow.model(.downloading(version: "1.1.0", fraction: 0.42, isUpdate: true)),
            UpdateRow(text: "Downloading 42%", kind: .busy)
        )
        XCTAssertEqual(UpdateRow.model(.preparing(version: "1.1.0", isUpdate: true)), UpdateRow(text: "Preparing… ~1 min", kind: .busy))
        XCTAssertEqual(UpdateRow.model(.waitingToInstall(version: "1.1.0")), UpdateRow(text: "Installing when dictation ends…", kind: .busy))
        XCTAssertEqual(UpdateRow.model(.notInstalled), UpdateRow(text: "Not installed", action: .download))
    }

    func testModelFailuresOfferTryAgainOnlyForAFailedInstall() {
        XCTAssertEqual(
            UpdateRow.model(.failed(.network, isUpdate: true)),
            UpdateRow(text: "Failed: Couldn't reach Hugging Face. Check your internet connection.", kind: .failure, action: .tryAgain)
        )
        XCTAssertEqual(
            UpdateRow.model(.checkFailed(.network)),
            UpdateRow(text: "Failed: Couldn't reach Hugging Face. Check your internet connection.", kind: .failure)
        )
    }

    // Each half reports on its own, so one failing never hides the other's answer.
    func testEveryCombinationKeepsBothAnswers() {
        let apps: [AppUpdateStatus] = [.notChecked, .checking, .upToDate, .available(version: "1.1.0"), .failed(.offline), .failed(.rateLimited), .failed(.badResponse)]
        let models: [ModelStatus] = [
            .installed(version: "1.0.0"), .checking, .upToDate(version: "1.0.0"), .updateAvailable(version: "1.1.0"),
            .downloading(version: "1.1.0", fraction: 0.5, isUpdate: true), .preparing(version: "1.1.0", isUpdate: true),
            .waitingToInstall(version: "1.1.0"), .failed(.network, isUpdate: true), .checkFailed(.network),
        ]
        for app in apps {
            for model in models {
                let appRow = UpdateRow.app(app)
                let modelRow = UpdateRow.model(model)
                XCTAssertEqual(appRow.kind == .latest, app == .upToDate, "\(app) × \(model)")
                if case .upToDate = model {
                    XCTAssertEqual(modelRow.kind, .latest)
                } else {
                    XCTAssertNotEqual(modelRow.kind, .latest, "\(app) × \(model)")
                }
                XCTAssertEqual(
                    UpdateRow.canCheckNow(app: app, model: model),
                    app != .checking && !model.isBusy,
                    "\(app) × \(model)"
                )
            }
        }
    }

    func testCheckNowWaitsForBothHalves() {
        XCTAssertTrue(UpdateRow.canCheckNow(app: .upToDate, model: .upToDate(version: "1.0.0")))
        XCTAssertFalse(UpdateRow.canCheckNow(app: .checking, model: .upToDate(version: "1.0.0")))
        XCTAssertFalse(UpdateRow.canCheckNow(app: .upToDate, model: .checking))
        XCTAssertFalse(UpdateRow.canCheckNow(app: .failed(.offline), model: .downloading(version: "1.1.0", fraction: 0.1, isUpdate: true)))
        XCTAssertTrue(UpdateRow.canCheckNow(app: .failed(.offline), model: .checkFailed(.network)))
    }

    func testOnlyAnAvailableVersionReachesTheMenu() {
        XCTAssertEqual(AppUpdateStatus.available(version: "1.1.0").availableVersion, "1.1.0")
        XCTAssertNil(AppUpdateStatus.upToDate.availableVersion)
        XCTAssertNil(AppUpdateStatus.failed(.offline).availableVersion)
        XCTAssertEqual(AppUpdateStatus(.available(version: "2.0.0")), .available(version: "2.0.0"))
        XCTAssertEqual(AppUpdateStatus(.failed(.badResponse)), .failed(.badResponse))
    }

    // MARK: - Install and Relaunch (#29)

    private let pin = AppInstallFixtures.pin

    private func offer(_ status: AppUpdateStatus = .available(version: "1.1.0"), pin: PinnedRelease? = AppInstallFixtures.pin, install: AppInstallState = .idle, location: AppInstallLocation = .replaceable) -> AppUpdateOffer? {
        AppUpdateOffer.make(status: status, pin: pin, install: install, location: location)
    }

    func testAPinnedReleaseInAWritablePlaceOffersInstallAndRelaunch() {
        XCTAssertEqual(offer(), .install(version: "1.1.0"))
        XCTAssertEqual(offer(install: .ready(version: "1.1.0")), .install(version: "1.1.0"))
        XCTAssertEqual(UpdateRow.app(.available(version: "1.1.0"), offer: offer()), UpdateRow(text: "1.1.0 available", action: .install))
    }

    func testWithoutAPinTheDownloadPageIsTheFallback() {
        XCTAssertEqual(offer(pin: nil), .download(version: "1.1.0"))
        let other = PinnedRelease(tag: "v1.0.9", version: "1.0.9", assetURL: pin.assetURL, assetSize: 1)
        XCTAssertEqual(offer(pin: other), .download(version: "1.1.0"))
        XCTAssertEqual(UpdateRow.app(.available(version: "1.1.0"), offer: offer(pin: nil)), UpdateRow(text: "1.1.0 available", action: .download))
    }

    func testATranslocatedOrReadOnlyCopyExplainsTheDownload() {
        XCTAssertEqual(
            UpdateRow.app(.available(version: "1.1.0"), offer: offer(location: .translocated)),
            UpdateRow(text: "1.1.0 available", action: .download, note: "To install updates from Sorla, quit it and open it from Applications.")
        )
        XCTAssertEqual(
            UpdateRow.app(.available(version: "1.1.0"), offer: offer(location: .notWritable)).note,
            "Sorla can't replace itself in this folder. Download the update and drag it to Applications."
        )
    }

    func testHomebrewIsToldToUpgradeWithBrew() {
        XCTAssertEqual(
            UpdateRow.app(.available(version: "1.1.0"), offer: offer(location: .homebrew)),
            UpdateRow(text: "1.1.0 available", note: "Update with Homebrew: brew upgrade --cask sorla")
        )
    }

    func testInstallingIsBusyAndAFailureIsNeverLatest() {
        XCTAssertEqual(UpdateRow.app(.available(version: "1.1.0"), offer: offer(install: .installing(version: "1.1.0"))), UpdateRow(text: "Installing…", kind: .busy))
        for failure in [AppInstallFailure.offline, .download, .verification, .replace, .relaunch] {
            let row = UpdateRow.app(.available(version: "1.1.0"), offer: offer(install: .failed(version: "1.1.0", failure)))
            XCTAssertEqual(row, UpdateRow(text: failure.message, kind: .failure, action: .download))
        }
        XCTAssertNil(offer(.upToDate), "nothing to offer")
    }

    func testCheckNowWaitsForAnInstall() {
        XCTAssertFalse(UpdateRow.canCheckNow(app: .available(version: "1.1.0"), model: .upToDate(version: "1"), install: .installing(version: "1.1.0")))
        XCTAssertTrue(UpdateRow.canCheckNow(app: .available(version: "1.1.0"), model: .upToDate(version: "1"), install: .ready(version: "1.1.0")))
    }
}
