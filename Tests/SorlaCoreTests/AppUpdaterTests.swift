import XCTest
@testable import SorlaCore

@MainActor
final class AppUpdaterTests: XCTestCase {
    private let clock = TestClock()
    private let disk = AppInstallFixtures.makeDisk()
    private lazy var downloader = FakeAppDownloader(disk: disk)
    private lazy var mounter = FakeMounter(disk: disk)
    private let relauncher = FakeRelauncher()
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var journal: AppInstallJournal!
    private var activity = DictationActivity.quiet
    // Answers the next looks at activity in turn, then falls back to `activity`.
    private var activityScript: [DictationActivity] = []
    private var appReplaced = false
    private var quits = 0
    private var quitGoesAhead = true
    private var updatedTo: [String] = []
    private let pin = AppInstallFixtures.pin
    private let bundle = AppInstallFixtures.bundle
    private let backup = AppInstallFixtures.backup
    private let startDate = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private lazy var startInstant = clock.now

    override func setUp() async throws {
        suiteName = "sorla-app-updater-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        journal = AppInstallJournal(defaults: defaults)
        _ = startInstant
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeUpdater(
        location: AppInstallLocation = .replaceable,
        automaticChecks: Bool = false,
        automaticInstalls: Bool = false,
        running: String = "1.0.0",
        bundleURL: URL = AppInstallFixtures.bundle
    ) -> AppUpdater {
        let installer = AppInstaller(
            bundleURL: bundleURL,
            runningVersion: running,
            downloader: downloader,
            mounter: mounter,
            signatures: FakeSignatures(disk: disk),
            files: disk
        )
        let updater = AppUpdater(
            installer: installer,
            location: location,
            relauncher: relauncher,
            journal: journal,
            automaticChecks: automaticChecks,
            automaticInstalls: automaticInstalls,
            activity: { [unowned self] in self.activityScript.isEmpty ? self.activity : self.activityScript.removeFirst() },
            terminate: { [unowned self] in
                self.quits += 1
                return self.quitGoesAhead
            },
            isAppReplaced: { [unowned self] in self.appReplaced },
            processID: 4242,
            sleep: { [clock] in await clock.sleep(for: $0) },
            now: { [unowned self] in
                let elapsed = self.clock.now - self.startInstant
                return self.startDate.addingTimeInterval(Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)
            }
        )
        updater.onUpdated = { [unowned self] in self.updatedTo.append($0) }
        return updater
    }

    private func settle(_ updater: AppUpdater) async {
        while let work = updater.work { await work.value }
    }

    private func assertRelaunchedInto(_ version: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(relauncher.starts.map(\.pid), [4242], file: file, line: line)
        XCTAssertEqual(relauncher.starts.map(\.bundle), [bundle], "the same path, never the backup", file: file, line: line)
        XCTAssertEqual(relauncher.starts.map(\.version), [version], file: file, line: line)
        XCTAssertEqual(quits, 1, file: file, line: line)
        XCTAssertEqual(disk.item(bundle.path), .app(FakeApp(version: version)), file: file, line: line)
        XCTAssertEqual(journal.record, AppInstallRecord(version: version, bundlePath: bundle.path, backupPath: backup.path), file: file, line: line)
    }

    // MARK: - Install and Relaunch

    func testInstallAndRelaunchSwapsAndRelaunchesTheSamePath() async {
        let updater = makeUpdater()
        updater.install(pin)
        XCTAssertEqual(updater.state, .installing(version: "1.1.0"))
        await settle(updater)

        assertRelaunchedInto("1.1.0")
        XCTAssertEqual(disk.item(backup.path), .app(FakeApp(version: "1.0.0")), "the backup stays until the new app has launched")
        XCTAssertEqual(updater.state, .installing(version: "1.1.0"))
    }

    // The tail, a transcription, a waiting delivery or the clipboard coming back all hold the swap.
    func testTheSwapWaitsForEverythingInFlight() async {
        activity = DictationActivity(isRestoringClipboard: true)
        let updater = makeUpdater()
        updater.install(pin)
        await clock.waitForSleeps(1)
        XCTAssertEqual(disk.item(bundle.path), .app(FakeApp(version: "1.0.0")))
        XCTAssertTrue(relauncher.starts.isEmpty)

        activity = DictationActivity(pendingDeliveries: 1)
        await clock.advance(by: .milliseconds(500))
        await clock.waitForSleeps(2)
        XCTAssertTrue(relauncher.starts.isEmpty)

        activity = .quiet
        await clock.advance(by: .milliseconds(500))
        await settle(updater)
        assertRelaunchedInto("1.1.0")
    }

    func testAVerificationFailureKeepsTheAppAndSaysSo() async {
        downloader.serve(.image(size: pin.assetSize, app: FakeApp(version: "1.1.0", isNotarized: false)))
        let updater = makeUpdater()
        updater.install(pin)
        await settle(updater)

        XCTAssertEqual(updater.state, .failed(version: "1.1.0", .verification))
        XCTAssertEqual(disk.paths, [bundle.path])
        XCTAssertTrue(relauncher.starts.isEmpty)
        XCTAssertEqual(quits, 0)
        XCTAssertNil(journal.record)
    }

    func testAHelperThatWontStartPutsTheOldAppBack() async {
        relauncher.error = CocoaError(.executableNotLoadable)
        let updater = makeUpdater()
        updater.install(pin)
        await settle(updater)

        XCTAssertEqual(updater.state, .failed(version: "1.1.0", .relaunch))
        XCTAssertEqual(disk.paths, [bundle.path])
        XCTAssertEqual(disk.item(bundle.path), .app(FakeApp(version: "1.0.0")))
        XCTAssertEqual(quits, 0)
        XCTAssertNil(journal.record)
    }

    // Quitting called off: the helper is stopped and the old app goes back, so this Sorla keeps pasting.
    func testACancelledQuitPutsTheOldAppBack() async {
        quitGoesAhead = false
        let updater = makeUpdater()
        updater.install(pin)
        await settle(updater)

        XCTAssertEqual(quits, 1)
        XCTAssertEqual(relauncher.cancels, 1)
        XCTAssertEqual(updater.state, .failed(version: "1.1.0", .relaunch))
        XCTAssertEqual(disk.paths, [bundle.path])
        XCTAssertEqual(disk.item(bundle.path), .app(FakeApp(version: "1.0.0")))
        XCTAssertNil(journal.record)
    }

    func testNothingIsInstalledWhereSorlaCantReplaceItself() async {
        for location in [AppInstallLocation.translocated, .notWritable, .homebrew] {
            let updater = makeUpdater(location: location)
            updater.install(pin)
            updater.updateFound(pin, automatic: true)
            await settle(updater)
            XCTAssertEqual(updater.state, .idle, "\(location)")
        }
        XCTAssertTrue(downloader.requests.isEmpty)
    }

    // A newer Sorla put in place during the wait is kept; the restart it needs takes over, without an error.
    func testASorlaReplacedWhileTheInstallWaitsIsKept() async {
        activity = DictationActivity(isRecording: true)
        let updater = makeUpdater()
        updater.install(pin)
        await clock.waitForSleeps(1)
        disk.set(bundle.path, .app(FakeApp(version: "1.2.0")))
        activity = .quiet
        await clock.advance(by: .milliseconds(500))
        await settle(updater)

        XCTAssertEqual(updater.state, .idle)
        XCTAssertEqual(disk.paths, [bundle.path])
        XCTAssertEqual(disk.item(bundle.path), .app(FakeApp(version: "1.2.0")))
        XCTAssertTrue(relauncher.starts.isEmpty)
        XCTAssertEqual(quits, 0)
        XCTAssertNil(journal.record)
    }

    // A rebuild with the same version is only told apart by the running app's replacement check.
    func testASorlaReplacedByTheSameVersionIsKept() async {
        appReplaced = true
        let updater = makeUpdater()
        updater.install(pin)
        await settle(updater)

        XCTAssertEqual(updater.state, .idle)
        XCTAssertEqual(disk.paths, [bundle.path])
        XCTAssertTrue(relauncher.starts.isEmpty)
    }

    func testANewCheckClearsAnEarlierFailure() async {
        downloader.fail(with: URLError(.notConnectedToInternet))
        let updater = makeUpdater()
        updater.install(pin)
        await settle(updater)
        XCTAssertEqual(updater.state, .failed(version: "1.1.0", .offline))

        updater.updateFound(pin, automatic: false)
        XCTAssertEqual(updater.state, .idle)
    }

    // MARK: - Automatic install

    func testWithoutBothTogglesNothingIsDownloadedInTheBackground() async {
        for (checks, installs) in [(false, false), (true, false), (false, true)] {
            let updater = makeUpdater(automaticChecks: checks, automaticInstalls: installs)
            updater.updateFound(pin, automatic: true)
            await settle(updater)
        }
        let updater = makeUpdater(automaticChecks: true, automaticInstalls: true)
        updater.updateFound(pin, automatic: false)
        await settle(updater)
        XCTAssertTrue(downloader.requests.isEmpty)
        XCTAssertNil(journal.pendingRelease)
    }

    func testAnAutomaticInstallWaitsForTenQuietMinutes() async {
        let updater = makeUpdater(automaticChecks: true, automaticInstalls: true)
        updater.updateFound(pin, automatic: true)
        await settle(updater)
        XCTAssertEqual(updater.state, .ready(version: "1.1.0"))
        XCTAssertEqual(journal.pendingRelease, pin)
        XCTAssertEqual(downloader.requests.count, 1)

        await clock.waitForSleeps(1)
        XCTAssertEqual(clock.sleeps.last, .seconds(600))
        await clock.advance(by: .seconds(300))
        updater.dictationActivityChanged()
        await clock.advance(by: .seconds(300))
        await clock.waitForSleeps(2)
        XCTAssertEqual(clock.sleeps.last, .seconds(300), "a dictation five minutes in starts the wait over")
        XCTAssertTrue(relauncher.starts.isEmpty)

        await clock.advance(by: .seconds(300))
        await settle(updater)
        assertRelaunchedInto("1.1.0")
        XCTAssertEqual(downloader.requests.count, 1, "the background download is reused")
    }

    func testAnAutomaticInstallNeverRunsDuringADictation() async {
        let updater = makeUpdater(automaticChecks: true, automaticInstalls: true)
        updater.updateFound(pin, automatic: true)
        await settle(updater)
        await clock.waitForSleeps(1)

        activity = DictationActivity(isRecording: true)
        await clock.advance(by: .seconds(600))
        await clock.waitForSleeps(2)
        XCTAssertEqual(clock.sleeps.last, .seconds(600))
        XCTAssertTrue(relauncher.starts.isEmpty)
        XCTAssertEqual(updater.state, .ready(version: "1.1.0"))
    }

    func testAnAutomaticInstallKeepsASorlaReplacedMeanwhile() async {
        let updater = makeUpdater(automaticChecks: true, automaticInstalls: true)
        updater.updateFound(pin, automatic: true)
        await settle(updater)
        await clock.waitForSleeps(1)
        disk.set(bundle.path, .app(FakeApp(version: "1.2.0")))
        await clock.advance(by: .seconds(600))
        await settle(updater)

        XCTAssertEqual(updater.state, .idle)
        XCTAssertEqual(disk.paths, [bundle.path])
        XCTAssertEqual(disk.item(bundle.path), .app(FakeApp(version: "1.2.0")))
        XCTAssertTrue(relauncher.starts.isEmpty)
    }

    func testTurningAutomaticInstallsOffStopsTheWait() async {
        let updater = makeUpdater(automaticChecks: true, automaticInstalls: true)
        updater.updateFound(pin, automatic: true)
        await settle(updater)
        await clock.waitForSleeps(1)

        updater.automaticInstalls = false
        await clock.advance(by: .seconds(600))
        await updater.automaticWait?.value
        XCTAssertTrue(relauncher.starts.isEmpty)
        XCTAssertEqual(updater.state, .ready(version: "1.1.0"), "Install and Relaunch still works by hand")

        updater.install(pin)
        await settle(updater)
        assertRelaunchedInto("1.1.0")
    }

    // Quiet when the wait ends, then recording from the moment the copy next to Sorla is done.
    func testADictationDuringTheStagingCopyKeepsTheDownloadForTheNextTry() async {
        let recording = DictationActivity(isRecording: true)
        activityScript = [.quiet, .quiet, recording, recording]
        let updater = makeUpdater(automaticChecks: true, automaticInstalls: true)
        updater.updateFound(pin, automatic: true)
        await settle(updater)
        await clock.waitForSleeps(1)
        await clock.advance(by: .seconds(600))
        await settle(updater)
        XCTAssertEqual(updater.state, .ready(version: "1.1.0"))
        XCTAssertFalse(disk.exists(AppInstallFixtures.staged))
        XCTAssertTrue(relauncher.starts.isEmpty)

        await clock.waitForSleeps(2)
        await clock.advance(by: .seconds(600))
        await settle(updater)
        assertRelaunchedInto("1.1.0")
        XCTAssertEqual(downloader.requests.count, 1, "the download is reused")
    }

    // macOS clears old temporary files, so an update that waited days in Ready may be gone.
    func testADownloadThatVanishedIsFetchedAgain() async {
        let updater = makeUpdater(automaticChecks: true, automaticInstalls: true)
        updater.updateFound(pin, automatic: true)
        await settle(updater)
        updater.automaticInstalls = false
        try? disk.remove(URL(fileURLWithPath: "/private/tmp/Sorla-update-1"))

        updater.install(pin)
        await settle(updater)
        assertRelaunchedInto("1.1.0")
        XCTAssertEqual(downloader.requests.count, 2)
    }

    func testClickingInstallDuringTheBackgroundDownloadReusesIt() async {
        let updater = makeUpdater(automaticChecks: true, automaticInstalls: true)
        updater.updateFound(pin, automatic: true)
        updater.install(pin)
        await settle(updater)

        XCTAssertEqual(downloader.requests.count, 1)
        assertRelaunchedInto("1.1.0")
    }

    func testAPendingAutomaticInstallIsTakenUpAtTheNextLaunch() async {
        journal.pendingRelease = pin
        let updater = makeUpdater(automaticChecks: true, automaticInstalls: true)
        updater.start()
        await settle(updater)
        await updater.automaticWait?.value
        await settle(updater)

        assertRelaunchedInto("1.1.0")
        XCTAssertTrue(clock.sleeps.isEmpty, "no quiet period at launch")
    }

    func testAPendingReleaseThisVersionAlreadyHasIsForgotten() async {
        journal.pendingRelease = pin
        let updater = makeUpdater(automaticChecks: true, automaticInstalls: true, running: "1.1.0")
        updater.start()
        await settle(updater)
        XCTAssertNil(journal.pendingRelease)
        XCTAssertTrue(downloader.requests.isEmpty)
    }

    func testAnAutomaticDownloadThatFailsSaysSoAndForgetsTheRelease() async {
        downloader.fail(with: ModelNetworkError.httpStatus(500))
        let updater = makeUpdater(automaticChecks: true, automaticInstalls: true)
        updater.updateFound(pin, automatic: true)
        await settle(updater)
        XCTAssertEqual(updater.state, .failed(version: "1.1.0", .download))
        XCTAssertNil(journal.pendingRelease)
        XCTAssertEqual(disk.paths, [bundle.path])
    }

    // MARK: - After the relaunch

    func testTheNewAppSaysItWasUpdatedAndRemovesTheBackupAfterTheGrace() async {
        disk.set(bundle.path, .app(FakeApp(version: "1.1.0")))
        disk.set(backup.path, .app(FakeApp(version: "1.0.0")))
        journal.record = AppInstallRecord(version: "1.1.0", bundlePath: bundle.path, backupPath: backup.path)
        let updater = makeUpdater(running: "1.1.0")

        updater.start()
        XCTAssertEqual(updatedTo, ["1.1.0"])
        await clock.waitForSleeps(1)
        XCTAssertEqual(clock.sleeps, [.seconds(30)])
        XCTAssertTrue(disk.exists(backup), "a crash in the first seconds still has the old app to go back to")

        await clock.advance(by: .seconds(30))
        await updater.backupRemoval?.value
        XCTAssertEqual(disk.paths, [bundle.path])
        XCTAssertNil(journal.record)
    }

    func testTheBackupRunningOnItsOwnIsLeftAlone() async {
        disk.set(backup.path, .app(FakeApp(version: "1.0.0")))
        let record = AppInstallRecord(version: "1.1.0", bundlePath: bundle.path, backupPath: backup.path)
        journal.record = record
        let updater = makeUpdater(running: "1.0.0", bundleURL: backup)

        updater.start()
        await settle(updater)
        XCTAssertNil(updater.backupRemoval)
        XCTAssertTrue(updatedTo.isEmpty)
        XCTAssertTrue(disk.exists(backup))
        XCTAssertEqual(journal.record, record)
    }
}
