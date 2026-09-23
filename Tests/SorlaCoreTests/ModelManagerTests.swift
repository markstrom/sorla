import XCTest
@testable import SorlaCore

@MainActor
final class ModelManagerTests: XCTestCase {
    private var modelsDirectory: URL!
    private var network: FakeModelNetwork!
    private var preparer: FakeModelPreparer!
    private var isIdle = true
    private var reloadResults: [Bool] = []
    private var reloads = 0
    private var installs: [Bool] = []
    private var failures: [SorlaIssue] = []

    override func setUp() async throws {
        modelsDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("sorla-manager-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        network = FakeModelNetwork()
        preparer = FakeModelPreparer()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: modelsDirectory)
    }

    private var swap: ModelSwap { ModelSwap(modelsDirectory: modelsDirectory) }

    private func makeManager(
        autoCheck: Bool = false,
        autoDownload: Bool = false,
        checkInterval: TimeInterval = 86_400,
        onReload: @escaping @MainActor () -> Void = {}
    ) -> ModelManager {
        let installer = ModelInstaller(
            modelsDirectory: modelsDirectory,
            manifestURL: PublishedModelFixture.manifestURL,
            filesBaseURL: PublishedModelFixture.filesBaseURL,
            network: network,
            preparer: preparer,
            availableDiskSpace: { _ in 10_000_000_000 }
        )
        let manager = ModelManager(
            installer: installer,
            isDictationIdle: { [unowned self] in self.isIdle },
            reloadModel: { [unowned self] in
                self.reloads += 1
                onReload()
                return self.reloadResults.isEmpty ? true : self.reloadResults.removeFirst()
            },
            automaticChecks: autoCheck,
            automaticDownloads: autoDownload,
            checkInterval: checkInterval,
            idlePollInterval: 0.01
        )
        manager.onInstalled = { [unowned self] firstInstall in self.installs.append(firstInstall) }
        manager.onFailure = { [unowned self] issue in self.failures.append(issue) }
        return manager
    }

    private func installModel(version: String, at location: URL? = nil) throws {
        let directory = location ?? swap.installed
        for name in ["Preprocessor.mlmodelc", "Encoder.mlmodelc", "Decoder.mlmodelc", "JointDecisionv3.mlmodelc"] {
            try FileManager.default.createDirectory(at: directory.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        try Data("{}".utf8).write(to: directory.appendingPathComponent("parakeet_vocab.json"))
        try PublishedModelFixture(version: version).manifestData.write(to: directory.appendingPathComponent("manifest.json"))
    }

    private func waitUntil(_ condition: @autoclosure () -> Bool, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return XCTFail("timed out", file: file, line: line) }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    func testDefaultSettingsWithAnInstalledModelMakeNoNetworkRequests() async throws {
        try installModel(version: "1.0.0")
        await PublishedModelFixture(version: "1.1.0").publish(on: network)
        let manager = makeManager()

        manager.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        let requests = await network.requests
        XCTAssertEqual(requests, [])
        XCTAssertEqual(manager.status, .installed(version: "1.0.0"))
        XCTAssertEqual(reloads, 0)
    }

    func testFirstRunInstallsWithoutBeingAsked() async throws {
        await PublishedModelFixture(version: "1.0.0").publish(on: network)
        let manager = makeManager()

        manager.start()
        await waitUntil(manager.status == .upToDate(version: "1.0.0"))

        XCTAssertEqual(PianissimoModel.installedVersion(at: swap.installed), "1.0.0")
        XCTAssertTrue(PianissimoModel.hasRequiredFiles(at: swap.installed))
        XCTAssertEqual(installs, [true])
        XCTAssertEqual(reloads, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: modelsDirectory.appendingPathComponent(".staging").path))
    }

    func testFirstRunShowsTheDownloadStartingImmediately() async throws {
        await PublishedModelFixture(version: "1.0.0").publish(on: network)
        let manager = makeManager()

        manager.start()

        XCTAssertEqual(manager.status, .downloading(version: "", fraction: 0, isUpdate: false))
        await waitUntil(manager.status == .upToDate(version: "1.0.0"))
    }

    func testFirstRunOfflineFailsWithARetry() async throws {
        await network.fail(PublishedModelFixture.manifestURL)
        let manager = makeManager()

        manager.start()
        await waitUntil(manager.status == .failed(.network, isUpdate: false))

        XCTAssertEqual(failures, [.modelDownloadFailed])
        XCTAssertFalse(FileManager.default.fileExists(atPath: swap.installed.path))

        await PublishedModelFixture(version: "1.0.0").publish(on: network)
        await network.unfail(PublishedModelFixture.manifestURL)
        manager.downloadModel()
        await waitUntil(manager.status == .upToDate(version: "1.0.0"))
    }

    func testAutomaticCheckAtLaunchFindsTheInstalledVersionUpToDate() async throws {
        try installModel(version: "1.0.0")
        await PublishedModelFixture(version: "1.0.0").publish(on: network)
        let manager = makeManager(autoCheck: true)

        manager.start()
        await waitUntil(manager.status == .upToDate(version: "1.0.0"))

        let requests = await network.requests
        XCTAssertEqual(requests, [PublishedModelFixture.manifestURL])
        XCTAssertEqual(reloads, 0)
    }

    func testAutomaticChecksRepeatOnTheInterval() async throws {
        try installModel(version: "1.0.0")
        await PublishedModelFixture(version: "1.0.0").publish(on: network)
        let manager = makeManager(autoCheck: true, checkInterval: 0.05)

        manager.start()
        let deadline = Date().addingTimeInterval(5)
        while await network.requests.count < 3, Date() < deadline {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        let checks = await network.requests.count
        XCTAssertGreaterThanOrEqual(checks, 3)

        manager.automaticChecks = false
        try await Task.sleep(nanoseconds: 50_000_000)
        let settled = await network.requests.count
        try await Task.sleep(nanoseconds: 200_000_000)
        let later = await network.requests.count
        XCTAssertEqual(settled, later)
    }

    func testAnUpdateIsOfferedWhenAutomaticDownloadIsOff() async throws {
        try installModel(version: "1.0.0")
        await PublishedModelFixture(version: "1.1.0").publish(on: network)
        let manager = makeManager()

        manager.checkNow()
        await waitUntil(manager.status == .updateAvailable(version: "1.1.0"))

        let requests = await network.requests
        XCTAssertEqual(requests, [PublishedModelFixture.manifestURL])
        XCTAssertEqual(PianissimoModel.installedVersion(at: swap.installed), "1.0.0")
    }

    func testDownloadingAnOfferedUpdateReusesTheFetchedManifest() async throws {
        try installModel(version: "1.0.0")
        await PublishedModelFixture(version: "1.1.0").publish(on: network)
        let manager = makeManager()
        manager.checkNow()
        await waitUntil(manager.status == .updateAvailable(version: "1.1.0"))

        manager.downloadModel()
        await waitUntil(manager.status == .upToDate(version: "1.1.0"))

        let manifestFetches = await network.requests.filter { $0 == PublishedModelFixture.manifestURL }
        XCTAssertEqual(manifestFetches.count, 1)
        XCTAssertEqual(PianissimoModel.installedVersion(at: swap.installed), "1.1.0")
        XCTAssertFalse(FileManager.default.fileExists(atPath: swap.previous.path))
        XCTAssertEqual(installs, [false])
    }

    func testCheckNowWithAutomaticDownloadInstallsTheUpdate() async throws {
        try installModel(version: "1.0.0")
        await PublishedModelFixture(version: "1.1.0").publish(on: network)
        let manager = makeManager(autoDownload: true)

        manager.checkNow()
        await waitUntil(manager.status == .upToDate(version: "1.1.0"))

        XCTAssertEqual(PianissimoModel.installedVersion(at: swap.installed), "1.1.0")
        XCTAssertEqual(reloads, 1)
    }

    func testAFailedUpdateKeepsTheOldModel() async throws {
        try installModel(version: "1.0.0")
        await PublishedModelFixture(version: "1.1.0").publish(on: network)
        await preparer.failSelfTest()
        let manager = makeManager(autoDownload: true)

        manager.checkNow()
        await waitUntil(manager.status == .failed(.selfTestFailed, isUpdate: true))

        XCTAssertEqual(PianissimoModel.installedVersion(at: swap.installed), "1.0.0")
        XCTAssertEqual(reloads, 0)
        XCTAssertEqual(failures, [.modelUpdateFailed])
    }

    func testTheSwapWaitsUntilDictationIsIdle() async throws {
        try installModel(version: "1.0.0")
        await PublishedModelFixture(version: "1.1.0").publish(on: network)
        isIdle = false
        let manager = makeManager(autoDownload: true)

        manager.checkNow()
        await waitUntil(manager.status == .waitingToInstall(version: "1.1.0"))
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(PianissimoModel.installedVersion(at: swap.installed), "1.0.0")

        isIdle = true
        await waitUntil(manager.status == .upToDate(version: "1.1.0"))
        XCTAssertEqual(PianissimoModel.installedVersion(at: swap.installed), "1.1.0")
    }

    func testAReloadFailureRollsBackToTheOldModel() async throws {
        try installModel(version: "1.0.0")
        await PublishedModelFixture(version: "1.1.0").publish(on: network)
        reloadResults = [false, true]
        let manager = makeManager(autoDownload: true)

        manager.checkNow()
        await waitUntil(manager.status == .failed(.installFailed, isUpdate: true))

        XCTAssertEqual(PianissimoModel.installedVersion(at: swap.installed), "1.0.0")
        XCTAssertFalse(FileManager.default.fileExists(atPath: swap.previous.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: swap.failed.path))
        XCTAssertEqual(reloads, 2)
        XCTAssertEqual(failures, [.modelUpdateFailed])
    }

    func testRetryingAnUpdateThatFailedToLoadDoesNotDownloadItAgain() async throws {
        try installModel(version: "1.0.0")
        let published = PublishedModelFixture(version: "1.1.0")
        await published.publish(on: network)
        reloadResults = [false, true]
        let manager = makeManager(autoDownload: true)
        manager.checkNow()
        await waitUntil(manager.status == .failed(.installFailed, isUpdate: true))
        let downloadsBefore = await network.requests.filter { $0 != PublishedModelFixture.manifestURL }.count

        manager.downloadModel()
        await waitUntil(manager.status == .upToDate(version: "1.1.0"))

        let downloadsAfter = await network.requests.filter { $0 != PublishedModelFixture.manifestURL }.count
        XCTAssertEqual(downloadsBefore, published.files.count)
        XCTAssertEqual(downloadsAfter, downloadsBefore)
        XCTAssertEqual(PianissimoModel.installedVersion(at: swap.installed), "1.1.0")
        XCTAssertFalse(FileManager.default.fileExists(atPath: modelsDirectory.appendingPathComponent(".staging").path))
    }

    func testAnUpdateWhosePreviousModelAlsoFailsToLoadDoesNotClaimTheCurrentModelStillWorks() async throws {
        try installModel(version: "1.0.0")
        await PublishedModelFixture(version: "1.1.0").publish(on: network)
        reloadResults = [false, false]
        let manager = makeManager(autoDownload: true)

        manager.checkNow()
        await waitUntil(manager.status == .failed(.installFailed, isUpdate: true))

        XCTAssertEqual(failures, [.modelNotLoaded])
    }

    func testRetryingAfterARollbackThatLeftOnlyThePreviousModelKeepsIt() async throws {
        try installModel(version: "1.0.0", at: swap.previous)
        await PublishedModelFixture(version: "1.1.0").publish(on: network)
        reloadResults = [false, true]
        let manager = makeManager()
        XCTAssertFalse(manager.isInstalled)

        manager.downloadModel()
        await waitUntil(manager.status == .failed(.installFailed, isUpdate: true))

        XCTAssertEqual(PianissimoModel.installedVersion(at: swap.installed), "1.0.0")
        XCTAssertFalse(FileManager.default.fileExists(atPath: swap.previous.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: swap.failed.path))
        XCTAssertEqual(failures, [.modelUpdateFailed])
    }

    func testAnUpdateThatFailedToLoadIsNotRetriedAutomaticallyButIsWhenTheUserAsks() async throws {
        try installModel(version: "1.0.0")
        await PublishedModelFixture(version: "1.1.0").publish(on: network)
        reloadResults = [false, true]
        let failedRun = makeManager(autoDownload: true)
        failedRun.checkNow()
        await waitUntil(failedRun.status == .failed(.installFailed, isUpdate: true))
        XCTAssertEqual(FailedModelUpdate(modelsDirectory: modelsDirectory).version, "1.1.0")
        let staging = ModelStaging(modelsDirectory: modelsDirectory, version: "1.1.0")
        XCTAssertTrue(FileManager.default.fileExists(atPath: staging.directory.path))

        let manager = makeManager(autoCheck: true, autoDownload: true)
        manager.start()
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.directory.path))
        await waitUntil(manager.status == .updateAvailable(version: "1.1.0"))
        XCTAssertEqual(reloads, 2)

        manager.checkNow()
        await waitUntil(manager.status == .upToDate(version: "1.1.0"))
        XCTAssertEqual(reloads, 3)
        XCTAssertNil(FailedModelUpdate(modelsDirectory: modelsDirectory).version)
    }

    func testANetworkFailureIsRetriedAutomatically() async throws {
        try installModel(version: "1.0.0")
        let published = PublishedModelFixture(version: "1.1.0")
        await published.publish(on: network)
        await network.fail(published.url(for: "README.md"))
        let manager = makeManager(autoDownload: true)

        manager.checkNow()
        await waitUntil(manager.status == .failed(.network, isUpdate: true))

        XCTAssertNil(FailedModelUpdate(modelsDirectory: modelsDirectory).version)
    }

    func testStartRollsBackAnUpdateThatWasNeverConfirmedAndRemembersIt() async throws {
        try installModel(version: "1.0.0", at: swap.previous)
        try installModel(version: "1.1.0")
        let manager = makeManager()

        manager.start()

        XCTAssertEqual(manager.status, .installed(version: "1.0.0"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: swap.previous.path))
        XCTAssertEqual(FailedModelUpdate(modelsDirectory: modelsDirectory).version, "1.1.0")
    }

    func testRetryingTheLoadReloadsTheInstalledModel() async throws {
        try installModel(version: "1.0.0")
        reloadResults = [false, true]
        let manager = makeManager()

        manager.retryLoadingModel()
        await waitUntil(failures == [.modelNotLoaded])
        manager.retryLoadingModel()
        await waitUntil(reloads == 2)

        XCTAssertEqual(failures, [.modelNotLoaded])
    }

    func testRetryingTheLoadFirstFinishesAnInterruptedSwap() async throws {
        try installModel(version: "1.0.0", at: swap.previous)
        let manager = makeManager()

        manager.retryLoadingModel()
        await waitUntil(reloads == 1)

        XCTAssertEqual(PianissimoModel.installedVersion(at: swap.installed), "1.0.0")
        XCTAssertFalse(FileManager.default.fileExists(atPath: swap.previous.path))
    }

    func testRetryingTheLoadWithoutAModelOffersTheDownload() async throws {
        let manager = makeManager()

        manager.retryLoadingModel()
        await waitUntil(manager.status == .notInstalled)
        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(reloads, 0)
    }

    func testAFirstInstallThatFailsToLoadIsKept() async throws {
        await PublishedModelFixture(version: "1.0.0").publish(on: network)
        reloadResults = [false]
        let manager = makeManager()

        manager.start()
        await waitUntil(manager.status == .installed(version: "1.0.0"))

        XCTAssertTrue(PianissimoModel.hasRequiredFiles(at: swap.installed))
        XCTAssertFalse(FileManager.default.fileExists(atPath: swap.failed.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: modelsDirectory.appendingPathComponent(".staging").path))
        XCTAssertEqual(reloads, 1)
        XCTAssertEqual(failures, [.modelNotLoaded])
        XCTAssertEqual(installs, [])
    }

    func testCheckNowIsIgnoredWhileADownloadIsRunning() async throws {
        try installModel(version: "1.0.0")
        await PublishedModelFixture(version: "1.1.0").publish(on: network)
        await network.holdDownloads()
        let manager = makeManager(autoDownload: true)
        manager.checkNow()
        await waitUntil(manager.status == .downloading(version: "1.1.0", fraction: 0, isUpdate: true))
        let requestsBefore = await network.requests.count

        manager.checkNow()
        try await Task.sleep(nanoseconds: 50_000_000)

        let requestsAfter = await network.requests.count
        XCTAssertEqual(requestsAfter, requestsBefore)
        XCTAssertEqual(manager.status, .downloading(version: "1.1.0", fraction: 0, isUpdate: true))
        await network.releaseDownloads()
        await waitUntil(manager.status == .upToDate(version: "1.1.0"))
    }

    func testProgressNeverMovesBackwards() {
        let shown = ModelStatus.downloading(version: "1.1.0", fraction: 0.5, isUpdate: true)

        XCTAssertNil(ModelManager.status(after: shown, applying: .downloading(fraction: 0.4), version: "1.1.0", isUpdate: true))
        XCTAssertNil(ModelManager.status(after: shown, applying: .downloading(fraction: 0.501), version: "1.1.0", isUpdate: true))
        XCTAssertEqual(
            ModelManager.status(after: shown, applying: .downloading(fraction: 0.6), version: "1.1.0", isUpdate: true),
            .downloading(version: "1.1.0", fraction: 0.6, isUpdate: true)
        )
        let preparing = ModelStatus.preparing(version: "1.1.0", isUpdate: true)
        XCTAssertNil(ModelManager.status(after: preparing, applying: .downloading(fraction: 1), version: "1.1.0", isUpdate: true))
        XCTAssertEqual(ModelManager.status(after: shown, applying: .preparing, version: "1.1.0", isUpdate: true), preparing)
    }

    func testAFailedCheckWithAWorkingModelIsQuiet() async throws {
        try installModel(version: "1.0.0")
        await network.fail(PublishedModelFixture.manifestURL)
        let manager = makeManager()

        manager.checkNow()
        await waitUntil(manager.status == .checkFailed(.network))

        XCTAssertEqual(failures, [])
    }

    func testStartCleansStagingLeftFromTheInstalledVersion() async throws {
        try installModel(version: "1.0.0")
        let leftover = ModelStaging(modelsDirectory: modelsDirectory, version: "1.0.0")
        try FileManager.default.createDirectory(at: leftover.downloadsDirectory, withIntermediateDirectories: true)
        let manager = makeManager()

        manager.start()

        XCTAssertFalse(FileManager.default.fileExists(atPath: leftover.root.path))
        let requests = await network.requests
        XCTAssertEqual(requests, [])
    }

    func testStagingIsRemovedOnceTheSwappedInModelHasLoaded() async throws {
        try installModel(version: "1.0.0")
        await PublishedModelFixture(version: "1.1.0").publish(on: network)
        let staging = ModelStaging(modelsDirectory: modelsDirectory, version: "1.1.0")
        var stagingExistedDuringReload: Bool?
        var versionDuringReload: String?
        let installed = swap.installed
        let manager = makeManager(autoDownload: true, onReload: {
            stagingExistedDuringReload = FileManager.default.fileExists(atPath: staging.directory.path)
            versionDuringReload = PianissimoModel.installedVersion(at: installed)
        })

        manager.checkNow()
        await waitUntil(manager.status == .upToDate(version: "1.1.0"))

        XCTAssertEqual(stagingExistedDuringReload, true)
        XCTAssertEqual(versionDuringReload, "1.1.0")
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.root.path))
    }

    func testStartRemovesAllStagingWhenAutomaticDownloadsAreOff() async throws {
        try installModel(version: "1.0.0")
        let newer = ModelStaging(modelsDirectory: modelsDirectory, version: "2.0.0")
        try FileManager.default.createDirectory(at: newer.downloadsDirectory, withIntermediateDirectories: true)
        let manager = makeManager(autoDownload: false)

        manager.start()

        XCTAssertFalse(FileManager.default.fileExists(atPath: newer.root.path))
    }

    func testStartKeepsNewerStagingToResumeWhenAutomaticChecksAndDownloadsAreOn() async throws {
        try installModel(version: "1.0.0")
        let newer = ModelStaging(modelsDirectory: modelsDirectory, version: "2.0.0")
        try FileManager.default.createDirectory(at: newer.downloadsDirectory, withIntermediateDirectories: true)
        await network.fail(PublishedModelFixture.manifestURL)
        let manager = makeManager(autoCheck: true, autoDownload: true)

        manager.start()

        XCTAssertTrue(FileManager.default.fileExists(atPath: newer.directory.path))
        await waitUntil(manager.status == .checkFailed(.network))
    }

    func testStartRemovesAllStagingWhenAutomaticChecksAreOffEvenWithAutomaticDownloadsOn() async throws {
        try installModel(version: "1.0.0")
        let newer = ModelStaging(modelsDirectory: modelsDirectory, version: "2.0.0")
        try FileManager.default.createDirectory(at: newer.downloadsDirectory, withIntermediateDirectories: true)
        let manager = makeManager(autoCheck: false, autoDownload: true)

        manager.start()

        XCTAssertFalse(FileManager.default.fileExists(atPath: newer.root.path))
    }

    func testStartRestoresTheOldModelAfterAnInterruptedRollback() async throws {
        try installModel(version: "1.0.0")
        try FileManager.default.moveItem(at: swap.installed, to: swap.previous)
        try FileManager.default.createDirectory(at: swap.failed, withIntermediateDirectories: true)
        let manager = makeManager()

        manager.start()

        XCTAssertEqual(manager.status, .installed(version: "1.0.0"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: swap.previous.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: swap.failed.path))
    }

    func testStartRecoversAnInterruptedSwap() async throws {
        try installModel(version: "1.0.0")
        try FileManager.default.moveItem(at: swap.installed, to: swap.previous)
        let manager = makeManager()

        manager.start()

        XCTAssertEqual(manager.status, .installed(version: "1.0.0"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: swap.previous.path))
    }
}
