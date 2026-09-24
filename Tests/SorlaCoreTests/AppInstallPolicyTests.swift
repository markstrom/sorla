import Security
import XCTest
@testable import SorlaCore

final class AppInstallPolicyTests: XCTestCase {
    private let versioned = AppReleaseAsset(
        name: "Sorla-1.1.0.dmg",
        size: 11_441_265,
        downloadURL: URL(string: "https://github.com/markstrom/sorla/releases/download/v1.1.0/Sorla-1.1.0.dmg")!
    )
    private let fixedName = AppReleaseAsset(
        name: "Sorla.dmg",
        size: 11_441_265,
        downloadURL: URL(string: "https://github.com/markstrom/sorla/releases/download/v1.1.0/Sorla.dmg")!
    )

    // MARK: - The exact release is pinned

    func testTheVersionedAssetOfTheCheckedReleaseIsPinned() {
        let pin = AppInstallPolicy.pin(AppRelease(tagName: "v1.1.0", assets: [fixedName, versioned]))
        XCTAssertEqual(pin, PinnedRelease(tag: "v1.1.0", version: "1.1.0", assetURL: versioned.downloadURL, assetSize: 11_441_265))
        XCTAssertFalse(pin?.assetURL.absoluteString.contains("latest") ?? true)
    }

    func testOnlyTheFixedNameIsNotEnoughToInstall() {
        XCTAssertNil(AppInstallPolicy.pin(AppRelease(tagName: "v1.1.0", assets: [fixedName])))
        XCTAssertNil(AppInstallPolicy.pin(AppRelease(tagName: "v1.1.0")))
    }

    // A tampered answer can't point the download anywhere but the release's own address.
    func testAnAssetElsewhereIsNotPinned() {
        for url in [
            "https://example.com/Sorla-1.1.0.dmg",
            "https://github.com/markstrom/sorla/releases/latest/download/Sorla-1.1.0.dmg",
            "https://github.com/markstrom/sorla/releases/download/v1.0.9/Sorla-1.1.0.dmg",
            "http://github.com/markstrom/sorla/releases/download/v1.1.0/Sorla-1.1.0.dmg",
        ] {
            let asset = AppReleaseAsset(name: "Sorla-1.1.0.dmg", size: 11_000_000, downloadURL: URL(string: url)!)
            XCTAssertNil(AppInstallPolicy.pin(AppRelease(tagName: "v1.1.0", assets: [asset])), url)
        }
    }

    func testTheSizeCapAndAnEmptyAssetAreRefused() {
        let url = versioned.downloadURL
        XCTAssertNil(AppInstallPolicy.pin(AppRelease(tagName: "v1.1.0", assets: [AppReleaseAsset(name: "Sorla-1.1.0.dmg", size: 0, downloadURL: url)])))
        XCTAssertNil(AppInstallPolicy.pin(AppRelease(tagName: "v1.1.0", assets: [AppReleaseAsset(name: "Sorla-1.1.0.dmg", size: AppInstallPolicy.maximumDownloadSize + 1, downloadURL: url)])))
        XCTAssertNotNil(AppInstallPolicy.pin(AppRelease(tagName: "v1.1.0", assets: [AppReleaseAsset(name: "Sorla-1.1.0.dmg", size: AppInstallPolicy.maximumDownloadSize, downloadURL: url)])))
    }

    func testATagWithoutVAndAnUnusableTag() {
        let asset = AppReleaseAsset(name: "Sorla-1.2.dmg", size: 1, downloadURL: URL(string: "https://github.com/markstrom/sorla/releases/download/1.2/Sorla-1.2.dmg")!)
        XCTAssertEqual(AppInstallPolicy.pin(AppRelease(tagName: "1.2", assets: [asset]))?.version, "1.2.0")
        XCTAssertNil(AppInstallPolicy.pin(AppRelease(tagName: "v1.1.0-beta", assets: [versioned])))
    }

    func testTheReleaseAnswerCarriesItsAssets() throws {
        let json = #"{"tag_name":"v1.1.0","assets":[{"name":"Sorla-1.1.0.dmg","size":11441265,"browser_download_url":"https://github.com/markstrom/sorla/releases/download/v1.1.0/Sorla-1.1.0.dmg"}]}"#
        XCTAssertEqual(try URLSessionAppReleaseSource.decode(Data(json.utf8)).assets, [versioned])
        let broken = #"{"tag_name":"v1.1.0","assets":[{"name":1}]}"#
        XCTAssertEqual(try URLSessionAppReleaseSource.decode(Data(broken.utf8)), AppRelease(tagName: "v1.1.0"))
    }

    // MARK: - Verification

    func testTheRequirementNamesSorlasTeamAndBundleAndCompiles() {
        XCTAssertEqual(
            AppInstallPolicy.codeRequirement,
            #"anchor apple generic and certificate leaf[subject.OU] = "V8K5F8X64N" and identifier "com.sorla.app""#
        )
        var requirement: SecRequirement?
        XCTAssertEqual(SecRequirementCreateWithString(AppInstallPolicy.codeRequirement as CFString, [], &requirement), errSecSuccess)
        XCTAssertNotNil(requirement)
    }

    func testTheVersionMustBeTheCheckedOneAndNewer() {
        XCTAssertTrue(AppInstallPolicy.acceptsVersion("1.1.0", pinned: "1.1.0", running: "1.0.3"))
        XCTAssertTrue(AppInstallPolicy.acceptsVersion("1.1", pinned: "1.1.0", running: "1.0.3"))
        XCTAssertFalse(AppInstallPolicy.acceptsVersion("1.2.0", pinned: "1.1.0", running: "1.0.3"), "not the version that was checked")
        XCTAssertFalse(AppInstallPolicy.acceptsVersion("1.0.2", pinned: "1.0.2", running: "1.0.3"), "a downgrade")
        XCTAssertFalse(AppInstallPolicy.acceptsVersion("1.0.3", pinned: "1.0.3", running: "1.0.3"), "the same version")
        XCTAssertFalse(AppInstallPolicy.acceptsVersion(nil, pinned: "1.1.0", running: "1.0.3"))
        XCTAssertFalse(AppInstallPolicy.acceptsVersion("1.1.0", pinned: "1.1.0", running: nil))
        XCTAssertFalse(AppInstallPolicy.acceptsVersion("1.1.0b", pinned: "1.1.0", running: "1.0.3"))
    }

    func testGatekeeperMustSayNotarized() {
        let notarized = "/tmp/m/Sorla.app: accepted\nsource=Notarized Developer ID\norigin=Developer ID Application: Anders Markström (V8K5F8X64N)\n"
        XCTAssertTrue(GatekeeperAssessment.isNotarized(status: 0, output: notarized))
        XCTAssertFalse(GatekeeperAssessment.isNotarized(status: 0, output: "/tmp/m/Sorla.app: accepted\nsource=Developer ID\n"))
        XCTAssertFalse(GatekeeperAssessment.isNotarized(status: 3, output: "/tmp/m/Sorla.app: rejected\nsource=Notarized Developer ID\n"))
        XCTAssertEqual(GatekeeperAssessment.arguments, ["--assess", "--type", "execute", "-v"])
    }

    func testTheImageIsMountedReadOnlyAndHidden() {
        let arguments = DiskImageCommand.attachArguments(image: URL(fileURLWithPath: "/private/tmp/d/Sorla-1.1.0.dmg"), mountPoint: URL(fileURLWithPath: "/private/tmp/d/mount"))
        XCTAssertEqual(arguments, ["attach", "-readonly", "-nobrowse", "-noautoopen", "-quiet", "-mountpoint", "/private/tmp/d/mount", "/private/tmp/d/Sorla-1.1.0.dmg"])
        XCTAssertEqual(DiskImageCommand.detachArguments(mountPoint: URL(fileURLWithPath: "/m"), force: true), ["detach", "/m", "-quiet", "-force"])
    }

    // MARK: - Replace in place, or fall back

    func testAWritableFolderCanBeReplacedInPlace() {
        XCTAssertEqual(AppInstallLocation.decide(bundlePath: "/Applications/Sorla.app", symlinkTarget: nil, isFolderWritable: true, isBundleWritable: true), .replaceable)
        XCTAssertTrue(AppInstallLocation.replaceable.canInstall)
    }

    func testAStandardUserOrReadOnlyBundleFallsBack() {
        XCTAssertEqual(AppInstallLocation.decide(bundlePath: "/Applications/Sorla.app", symlinkTarget: nil, isFolderWritable: false, isBundleWritable: true), .notWritable)
        XCTAssertEqual(AppInstallLocation.decide(bundlePath: "/Applications/Sorla.app", symlinkTarget: nil, isFolderWritable: true, isBundleWritable: false), .notWritable)
        XCTAssertFalse(AppInstallLocation.notWritable.canInstall)
    }

    func testATranslocatedCopyFallsBack() {
        let path = "/private/var/folders/xy/T/AppTranslocation/1A2B/d/Sorla.app"
        XCTAssertEqual(AppInstallLocation.decide(bundlePath: path, symlinkTarget: nil, isFolderWritable: true, isBundleWritable: true), .translocated)
    }

    func testHomebrewManagesItsOwnCopy() {
        XCTAssertEqual(AppInstallLocation.decide(bundlePath: "/opt/homebrew/Caskroom/sorla/1.0.3/Sorla.app", symlinkTarget: nil, isFolderWritable: true, isBundleWritable: true), .homebrew)
        XCTAssertEqual(
            AppInstallLocation.decide(bundlePath: "/Applications/Sorla.app", symlinkTarget: "/usr/local/Caskroom/sorla/1.0.3/Sorla.app", isFolderWritable: true, isBundleWritable: true),
            .homebrew
        )
        XCTAssertEqual(AppInstallLocation.decide(bundlePath: "/Applications/Sorla.app", symlinkTarget: "/Volumes/Apps/Sorla.app", isFolderWritable: true, isBundleWritable: true), .notWritable)
        XCTAssertEqual(AppInstallLocation.decide(bundlePath: "/Applications/Caskroomy/Sorla.app", symlinkTarget: nil, isFolderWritable: true, isBundleWritable: true), .replaceable)
    }

    // A cask moves the app to Applications and leaves a link to it in the Caskroom, pointing the other way.
    func testACaskroomLinkToThisAppMeansHomebrew() {
        func decide(_ links: [String]) -> AppInstallLocation {
            AppInstallLocation.decide(bundlePath: "/Applications/Sorla.app", symlinkTarget: nil, caskroomLinks: links, isFolderWritable: true, isBundleWritable: true)
        }
        XCTAssertEqual(decide(["/Applications/Sorla.app"]), .homebrew)
        XCTAssertEqual(decide(["/Users/test/Applications/Sorla.app", "/Applications/Sorla.app"]), .homebrew)
        XCTAssertEqual(decide(["/Users/test/Applications/Sorla.app"]), .replaceable, "a cask installed elsewhere doesn't own this copy")
        XCTAssertEqual(decide([]), .replaceable)
    }

    func testTheCurrentLocationIsReadFromTheDisk() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SorlaLocation-\(UUID().uuidString)")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.appendingPathComponent("locked").path)
            try? FileManager.default.removeItem(at: root)
        }
        let apps = root.appendingPathComponent("Apps")
        let cask = root.appendingPathComponent("Caskroom/sorla/1.0.3/Sorla.app")
        let locked = root.appendingPathComponent("locked/Sorla.app")
        for folder in [apps, cask, locked] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let linked = root.appendingPathComponent("Linked/Sorla.app")
        try FileManager.default.createDirectory(at: linked.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: cask)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.deletingLastPathComponent().path)

        let app = apps.appendingPathComponent("Sorla.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        XCTAssertEqual(AppInstallLocation.current(bundleURL: app, homebrewPrefixes: [root]), .replaceable)
        XCTAssertEqual(AppInstallLocation.current(bundleURL: linked, homebrewPrefixes: [root]), .homebrew)
        XCTAssertEqual(AppInstallLocation.current(bundleURL: locked, homebrewPrefixes: [root]), .notWritable)
    }

    func testACaskInstallIsFoundThroughTheCaskroomLink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SorlaCaskroom-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let prefixes = [root.appendingPathComponent("opt/homebrew"), root.appendingPathComponent("usr/local")]
        let app = root.appendingPathComponent("Applications/Sorla.app")
        let other = root.appendingPathComponent("Other/Sorla.app")
        for folder in [app, other, prefixes[0].appendingPathComponent("Caskroom/sorla/1.0.1/Sorla.app")] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        XCTAssertEqual(AppInstallLocation.current(bundleURL: app, homebrewPrefixes: prefixes), .replaceable, "a leftover folder is not a link")

        let version = prefixes[1].appendingPathComponent("Caskroom/sorla/1.0.2")
        try FileManager.default.createDirectory(at: version, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: version.appendingPathComponent("Sorla.app").path, withDestinationPath: app.path)

        XCTAssertEqual(AppInstallLocation.current(bundleURL: app, homebrewPrefixes: prefixes), .homebrew)
        XCTAssertEqual(AppInstallLocation.current(bundleURL: other, homebrewPrefixes: prefixes), .replaceable)
    }

    // MARK: - Cleanup and rollback

    func testAFailureUndoesEverythingNewestFirst() {
        let temp = URL(fileURLWithPath: "/t")
        let mount = URL(fileURLWithPath: "/t/mount")
        var cleanup = AppInstallCleanup()
        cleanup.did(.temporaryDirectory(temp))
        cleanup.did(.mounted(mount))
        XCTAssertEqual(cleanup.onFailure, [.detach(mount), .remove(temp)])
        cleanup.undid(.mounted(mount))
        XCTAssertEqual(cleanup.onFailure, [.remove(temp)])
    }

    func testAFailedSwapPutsTheOldAppBackBeforeTidyingUp() {
        let bundle = AppInstallFixtures.bundle
        let backup = AppInstallFixtures.backup
        var cleanup = AppInstallCleanup()
        cleanup.did(.temporaryDirectory(URL(fileURLWithPath: "/t")))
        cleanup.did(.swapped(bundle: bundle, backup: backup))
        cleanup.did(.staged(AppInstallFixtures.staged))
        XCTAssertEqual(cleanup.onFailure, [.remove(AppInstallFixtures.staged), .rollBack(bundle: bundle, backup: backup), .remove(URL(fileURLWithPath: "/t"))])
    }

    func testSuccessKeepsTheSwapAndItsBackup() {
        var cleanup = AppInstallCleanup()
        cleanup.did(.temporaryDirectory(URL(fileURLWithPath: "/t")))
        cleanup.did(.swapped(bundle: AppInstallFixtures.bundle, backup: AppInstallFixtures.backup))
        XCTAssertEqual(cleanup.onSuccess, [.remove(URL(fileURLWithPath: "/t"))])
        XCTAssertEqual(AppInstallCleanup.Action.rollBack(bundle: AppInstallFixtures.bundle, backup: AppInstallFixtures.backup).name, "roll back")
    }

    func testTheBackupIsNamedForTheVersionItHolds() {
        XCTAssertEqual(AppInstallPolicy.backupName(runningVersion: "1.0.3"), "Sorla 1.0.3.app")
        XCTAssertEqual(AppInstallPolicy.backupName(runningVersion: nil), "Sorla previous.app")
    }

    // MARK: - After the relaunch

    private let record = AppInstallRecord(version: "1.1.0", bundlePath: "/Applications/Sorla.app", backupPath: "/Applications/Sorla 1.0.3.app")

    func testTheNewAppAtTheSamePathRemovesTheBackupAfterTheGrace() {
        XCTAssertEqual(AppInstallRecovery.atLaunch(record: record, bundlePath: "/Applications/Sorla.app", runningVersion: "1.1.0"), .removeBackupAfterGrace(updatedTo: "1.1.0"))
        XCTAssertEqual(AppInstallRecovery.grace, 30)
    }

    // Whoever runs from the original path has proved it starts, even if it's the old app put back by hand.
    func testTheOldAppAtTheSamePathAlsoTidiesUpButSaysNothing() {
        XCTAssertEqual(AppInstallRecovery.atLaunch(record: record, bundlePath: "/Applications/Sorla.app", runningVersion: "1.0.3"), .removeBackupAfterGrace(updatedTo: nil))
    }

    func testTheBackupItselfRunningKeepsIt() {
        XCTAssertEqual(AppInstallRecovery.atLaunch(record: record, bundlePath: "/Applications/Sorla 1.0.3.app", runningVersion: "1.0.3"), .keepBackup)
        XCTAssertEqual(AppInstallRecovery.atLaunch(record: nil, bundlePath: "/Applications/Sorla.app", runningVersion: "1.1.0"), .none)
    }

    // MARK: - Automatic install

    private let start = Date(timeIntervalSinceReferenceDate: 1_000_000)

    func testAutomaticInstallNeedsBothToggles() {
        for (check, install) in [(false, false), (false, true), (true, false)] {
            XCTAssertEqual(AutomaticAppInstall.decide(autoCheck: check, autoInstall: install, atLaunch: true, lastActivity: start, now: start, isQuiet: true), .never)
        }
    }

    func testAutomaticInstallWaitsForTenQuietMinutes() {
        func decide(after seconds: TimeInterval, quiet: Bool = true) -> AutomaticAppInstall.Decision {
            AutomaticAppInstall.decide(autoCheck: true, autoInstall: true, atLaunch: false, lastActivity: start, now: start.addingTimeInterval(seconds), isQuiet: quiet)
        }
        XCTAssertEqual(decide(after: 0), .after(600))
        XCTAssertEqual(decide(after: 240), .after(360))
        XCTAssertEqual(decide(after: 600), .now)
        XCTAssertEqual(decide(after: 3_600, quiet: false), .after(600), "never during dictation")
        XCTAssertEqual(decide(after: -60), .after(600), "a clock set back counts as no quiet time")
    }

    func testAtLaunchItInstallsRightAwayUnlessADictationRuns() {
        XCTAssertEqual(AutomaticAppInstall.decide(autoCheck: true, autoInstall: true, atLaunch: true, lastActivity: start, now: start, isQuiet: true), .now)
        XCTAssertEqual(AutomaticAppInstall.decide(autoCheck: true, autoInstall: true, atLaunch: true, lastActivity: start, now: start, isQuiet: false), .after(600))
    }

    // MARK: - Failures keep the app, and say so

    func testEveryFailureSaysSorlaWasKept() {
        let failures: [AppInstallFailure] = [.offline, .download, .verification, .replace, .relaunch]
        for failure in failures {
            XCTAssertTrue(failure.message.contains("wasn't changed") || failure.message.contains("is kept"), failure.message)
            XCTAssertFalse(failure.message.localizedCaseInsensitiveContains("up to date"))
        }
        XCTAssertEqual(AppInstallError.notarization.failure, .verification)
        XCTAssertEqual(AppInstallError.tooLarge.failure, .verification)
        XCTAssertEqual(AppInstallError.incomplete.failure, .download)
        XCTAssertEqual(AppInstallError.notReplaceable.failure, .replace)
    }
}
