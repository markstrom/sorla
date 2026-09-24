import XCTest
@testable import SorlaCore

final class AppInstallerTests: XCTestCase {
    private let disk = AppInstallFixtures.makeDisk()
    private lazy var downloader = FakeAppDownloader(disk: disk)
    private lazy var mounter = FakeMounter(disk: disk)
    private lazy var installer = AppInstallFixtures.makeInstaller(disk: disk, downloader: downloader, mounter: mounter)
    private let pin = AppInstallFixtures.pin
    private let bundle = AppInstallFixtures.bundle
    private let backup = AppInstallFixtures.backup

    private var privateDirectory: String { "/private/tmp/Sorla-update-1" }

    private func assertNothingLeftBehind(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(disk.paths, [bundle.path], file: file, line: line)
        XCTAssertEqual(disk.item(bundle.path), .app(FakeApp(version: "1.0.0")), "the current app is kept", file: file, line: line)
        XCTAssertEqual(mounter.detached, mounter.attached, "every mount is detached", file: file, line: line)
    }

    private func prepareFails(with expected: AppInstallError, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await installer.prepare(pin)
            XCTFail("prepared", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? AppInstallError, expected, file: file, line: line)
        }
        assertNothingLeftBehind(file: file, line: line)
    }

    // MARK: - Download and verify

    func testPreparingDownloadsThePinnedAssetAndLeavesOnlyAVerifiedCopy() async throws {
        let prepared = try await installer.prepare(pin)

        XCTAssertEqual(downloader.requests.map(\.url), [pin.assetURL])
        XCTAssertEqual(downloader.requests.map(\.maximumBytes), [pin.assetSize])
        XCTAssertEqual(mounter.attached, [privateDirectory + "/mount"])
        XCTAssertEqual(mounter.detached, mounter.attached)
        XCTAssertEqual(prepared, PreparedAppUpdate(version: "1.1.0", directory: URL(fileURLWithPath: privateDirectory), app: URL(fileURLWithPath: privateDirectory + "/Sorla.app")))
        XCTAssertEqual(disk.paths, [bundle.path, privateDirectory, privateDirectory + "/Sorla.app"])
        XCTAssertEqual(disk.item(bundle.path), .app(FakeApp(version: "1.0.0")), "nothing is touched before the swap")
    }

    func testAnOfflineDownloadKeepsTheApp() async {
        downloader.fail(with: URLError(.notConnectedToInternet))
        await prepareFails(with: .offline)
    }

    func testAServerErrorKeepsTheApp() async {
        downloader.fail(with: ModelNetworkError.httpStatus(404))
        await prepareFails(with: .download)
    }

    func testADownloadOverTheCapIsCutOff() async {
        downloader.fail(with: ModelNetworkError.tooLarge)
        await prepareFails(with: .tooLarge)
        let huge = PinnedRelease(tag: pin.tag, version: pin.version, assetURL: pin.assetURL, assetSize: AppInstallPolicy.maximumDownloadSize + 1)
        do {
            _ = try await installer.prepare(huge)
            XCTFail("prepared")
        } catch {
            XCTAssertEqual(error as? AppInstallError, .tooLarge)
        }
        XCTAssertEqual(downloader.requests.count, 1, "an oversized asset isn't even asked for")
    }

    func testADownloadThatStopsShortIsRefused() async {
        downloader.serve(.image(size: 5_000_000, app: FakeApp(version: "1.1.0")))
        await prepareFails(with: .incomplete)
    }

    func testAnImageThatWontMountIsRefused() async {
        mounter.failAttach()
        await prepareFails(with: .mount)
    }

    func testAnImageWithoutSorlaIsRefused() async {
        downloader.serve(.image(size: pin.assetSize, app: nil))
        await prepareFails(with: .missingApp)
    }

    func testAnAppFromAnotherDeveloperIsRefused() async {
        downloader.serve(.image(size: pin.assetSize, app: FakeApp(version: "1.1.0", isSignedBySorla: false)))
        await prepareFails(with: .signature)
    }

    func testAnAppGatekeeperDoesntCallNotarizedIsRefused() async {
        downloader.serve(.image(size: pin.assetSize, app: FakeApp(version: "1.1.0", isNotarized: false)))
        await prepareFails(with: .notarization)
    }

    func testAnotherVersionThanTheCheckedOneIsRefused() async {
        downloader.serve(.image(size: pin.assetSize, app: FakeApp(version: "1.2.0")))
        await prepareFails(with: .version)
    }

    func testAnOlderAppIsNeverInstalled() async {
        let older = PinnedRelease(tag: "v0.9.0", version: "0.9.0", assetURL: pin.assetURL, assetSize: pin.assetSize)
        downloader.serve(.image(size: pin.assetSize, app: FakeApp(version: "0.9.0")))
        do {
            _ = try await installer.prepare(older)
            XCTFail("prepared")
        } catch {
            XCTAssertEqual(error as? AppInstallError, .version)
        }
        assertNothingLeftBehind()
    }

    func testACopyThatFailsIsCleanedUp() async {
        disk.fail("copy")
        await prepareFails(with: .disk)
    }

    // MARK: - Stage and swap

    private func stagedUpdate() async throws -> StagedAppUpdate {
        try installer.stage(try await installer.prepare(pin))
    }

    func testTheSwapKeepsTheSamePathAndTheOldAppAsBackup() async throws {
        let staged = try await stagedUpdate()
        XCTAssertEqual(staged.staged, AppInstallFixtures.staged)

        let record = try installer.swap(staged)

        XCTAssertEqual(record, AppInstallRecord(version: "1.1.0", bundlePath: bundle.path, backupPath: backup.path))
        XCTAssertEqual(disk.item(bundle.path), .app(FakeApp(version: "1.1.0")))
        XCTAssertEqual(disk.item(backup.path), .app(FakeApp(version: "1.0.0")))
        XCTAssertEqual(disk.paths, [backup.path, bundle.path], "the staged copy and the private folder are gone")
    }

    func testACopyChangedOnItsWayNextToSorlaIsRefused() async throws {
        let prepared = try await installer.prepare(pin)
        disk.state.withLock { $0.copiesBecome = FakeApp(version: "1.1.0", isSignedBySorla: false) }
        XCTAssertThrowsError(try installer.stage(prepared)) { XCTAssertEqual($0 as? AppInstallError, .signature) }
        assertNothingLeftBehind()
    }

    func testASwapThatFailsKeepsTheApp() async throws {
        let staged = try await stagedUpdate()
        disk.fail("replace")
        XCTAssertThrowsError(try installer.swap(staged)) { XCTAssertEqual($0 as? AppInstallError, .replace) }
        assertNothingLeftBehind()
    }

    func testASwapCutShortPutsTheOldAppBack() async throws {
        let staged = try await stagedUpdate()
        disk.state.withLock { $0.replaceFailsHalfway = true }
        XCTAssertThrowsError(try installer.swap(staged))
        disk.state.withLock { $0.replaceFailsHalfway = false }
        XCTAssertEqual(disk.item(bundle.path), .app(FakeApp(version: "1.0.0")))
        XCTAssertFalse(disk.exists(backup))
        XCTAssertFalse(disk.exists(AppInstallFixtures.staged))
    }

    func testTheWrongAppAtThePathAfterTheSwapIsRolledBack() async throws {
        let staged = try await stagedUpdate()
        disk.set(staged.staged.path, .app(FakeApp(version: "1.2.0")))
        XCTAssertThrowsError(try installer.swap(staged)) { XCTAssertEqual($0 as? AppInstallError, .replace) }
        assertNothingLeftBehind()
    }

    func testAnOldBackupFromAnEarlierInstallMakesWay() async throws {
        disk.set(backup.path, .app(FakeApp(version: "1.0.0")))
        let record = try installer.swap(try await stagedUpdate())
        XCTAssertEqual(disk.item(record.backupPath), .app(FakeApp(version: "1.0.0")))
    }

    func testABackupNameThatIsTheRunningAppItselfIsRefused() async throws {
        let odd = AppInstaller(
            bundleURL: backup,
            runningVersion: "1.0.0",
            downloader: downloader,
            mounter: mounter,
            signatures: FakeSignatures(disk: disk),
            files: disk
        )
        disk.set(backup.path, .app(FakeApp(version: "1.0.0")))
        let staged = try odd.stage(try await odd.prepare(pin))
        XCTAssertThrowsError(try odd.swap(staged)) { XCTAssertEqual($0 as? AppInstallError, .notReplaceable) }
        XCTAssertEqual(disk.item(backup.path), .app(FakeApp(version: "1.0.0")))
    }

    func testRollingBackAfterTheSwapRestoresTheOldApp() async throws {
        let record = try installer.swap(try await stagedUpdate())
        installer.rollBack(record)
        assertNothingLeftBehind()
    }

    func testRemovingTheBackupNeverTouchesTheApp() async throws {
        let record = try installer.swap(try await stagedUpdate())
        installer.removeBackup(of: record)
        XCTAssertEqual(disk.paths, [bundle.path])
        XCTAssertEqual(disk.item(bundle.path), .app(FakeApp(version: "1.1.0")))

        installer.removeBackup(of: AppInstallRecord(version: "1.1.0", bundlePath: bundle.path, backupPath: bundle.path))
        XCTAssertEqual(disk.paths, [bundle.path])
    }

    func testDiscardingRemovesWhatWasDownloaded() async throws {
        let prepared = try await installer.prepare(pin)
        installer.discard(prepared)
        assertNothingLeftBehind()

        let staged = try await stagedUpdate()
        installer.discard(staged)
        assertNothingLeftBehind()
    }

    func testLeftoversFromAnInterruptedInstallAreDetachedAndRemoved() async {
        disk.set(privateDirectory, .folder)
        disk.set(privateDirectory + "/mount/Sorla.app", .app(FakeApp(version: "1.1.0")))
        disk.set(AppInstallFixtures.staged.path, .app(FakeApp(version: "1.1.0")))

        await installer.removeLeftovers()

        XCTAssertEqual(mounter.detached, [privateDirectory + "/mount"])
        XCTAssertEqual(disk.paths, [bundle.path])
    }
}
