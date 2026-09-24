import Foundation
import os

public protocol AppUpdateDownloading: Sendable {
    func download(_ url: URL, to destination: URL, maximumBytes: Int64) async throws
}

public protocol DiskImageMounting: Sendable {
    func attach(_ image: URL, at mountPoint: URL) async throws
    func detach(_ mountPoint: URL) async
}

public protocol AppSignatureChecking: Sendable {
    func checkSignature(of app: URL, requirement: String) throws
    func checkNotarized(_ app: URL) async throws
}

public protocol AppFileOperations: Sendable {
    func makePrivateDirectory() throws -> URL
    func leftoverDirectories() -> [URL]
    func size(of url: URL) -> Int64?
    func exists(_ url: URL) -> Bool
    func copy(_ source: URL, to destination: URL) throws
    func move(_ source: URL, to destination: URL) throws
    func remove(_ url: URL) throws
    func replace(_ item: URL, with replacement: URL, backupName: String?) throws
    func shortVersion(of app: URL) -> String?
}

@MainActor
public protocol AppRelaunching: AnyObject {
    func start(waitingFor pid: Int32, thenOpen bundle: URL, expectedVersion: String?) throws
    func cancel()
}

public enum AppInstallError: Error, Equatable, Sendable {
    case notReplaceable
    case offline
    case download
    case tooLarge
    case incomplete
    case mount
    case missingApp
    case signature
    case notarization
    case version
    case disk
    case replace
    case relaunch
    // Another Sorla was put in place while this one runs; that copy is kept and the restart it needs takes over.
    case replacedOnDisk

    public var failure: AppInstallFailure {
        switch self {
        case .offline: return .offline
        case .download, .incomplete: return .download
        case .tooLarge, .mount, .missingApp, .signature, .notarization, .version: return .verification
        case .notReplaceable, .disk, .replace, .replacedOnDisk: return .replace
        case .relaunch: return .relaunch
        }
    }
}

// Downloaded, checked and copied out of its disk image, which is already detached.
public struct PreparedAppUpdate: Equatable, Sendable {
    public let version: String
    public let directory: URL
    public let app: URL
}

// Copied next to the running app and checked again, ready for a swap that only renames.
public struct StagedAppUpdate: Equatable, Sendable {
    public let version: String
    public let directory: URL
    public let staged: URL
}

public struct AppInstaller: Sendable {
    public let bundleURL: URL
    public let runningVersion: String?
    private let downloader: AppUpdateDownloading
    private let mounter: DiskImageMounting
    private let signatures: AppSignatureChecking
    private let files: AppFileOperations
    private static let logger = Logger(subsystem: "com.sorla.app", category: "AppInstaller")

    public init(
        bundleURL: URL,
        runningVersion: String?,
        downloader: AppUpdateDownloading,
        mounter: DiskImageMounting,
        signatures: AppSignatureChecking,
        files: AppFileOperations
    ) {
        self.bundleURL = bundleURL
        self.runningVersion = runningVersion
        self.downloader = downloader
        self.mounter = mounter
        self.signatures = signatures
        self.files = files
    }

    public func prepare(_ pin: PinnedRelease) async throws -> PreparedAppUpdate {
        guard (1...AppInstallPolicy.maximumDownloadSize).contains(pin.assetSize) else { throw log(AppInstallError.tooLarge, "size check") }
        var cleanup = AppInstallCleanup()
        do {
            let directory = try disk { try files.makePrivateDirectory() }
            cleanup.did(.temporaryDirectory(directory))
            let image = directory.appendingPathComponent(AppInstallPolicy.assetName(version: pin.version))
            Self.logger.info("downloading \(pin.tag, privacy: .public) (\(pin.assetSize, privacy: .public) bytes)")
            do {
                try await downloader.download(pin.assetURL, to: image, maximumBytes: pin.assetSize)
            } catch {
                throw Self.downloadError(error)
            }
            guard files.size(of: image) == pin.assetSize else { throw AppInstallError.incomplete }

            let mountPoint = directory.appendingPathComponent("mount")
            // Counted before attaching, so even an attach that fails halfway is detached.
            cleanup.did(.mounted(mountPoint))
            do {
                try await mounter.attach(image, at: mountPoint)
            } catch {
                throw AppInstallError.mount
            }
            let mountedApp = mountPoint.appendingPathComponent(AppInstallPolicy.appName)
            try verify(mountedApp, version: pin.version)
            do {
                try await signatures.checkNotarized(mountedApp)
            } catch {
                throw AppInstallError.notarization
            }

            let app = directory.appendingPathComponent(AppInstallPolicy.appName)
            try disk { try files.copy(mountedApp, to: app) }
            await mounter.detach(mountPoint)
            cleanup.undid(.mounted(mountPoint))
            try? files.remove(image)
            Self.logger.info("\(pin.tag, privacy: .public) downloaded and verified")
            return PreparedAppUpdate(version: pin.version, directory: directory, app: app)
        } catch {
            await perform(cleanup.onFailure)
            throw log(error, "prepare")
        }
    }

    // The slow copy happens here, away from the moment of the swap.
    public func stage(_ prepared: PreparedAppUpdate) throws -> StagedAppUpdate {
        let staged = bundleURL.deletingLastPathComponent().appendingPathComponent(AppInstallPolicy.stagingName)
        var cleanup = AppInstallCleanup()
        cleanup.did(.temporaryDirectory(prepared.directory))
        do {
            try checkBundleIsRunningApp()
            if files.exists(staged) { try disk { try files.remove(staged) } }
            cleanup.did(.staged(staged))
            try disk { try files.copy(prepared.app, to: staged) }
            // Checked again where it will run, so nothing changed it on the way.
            try verify(staged, version: prepared.version)
            return StagedAppUpdate(version: prepared.version, directory: prepared.directory, staged: staged)
        } catch {
            performNow(cleanup.onFailure)
            throw log(error, "stage")
        }
    }

    // Only renames, so it is quick enough to follow the last check that no dictation is running.
    public func swap(_ staged: StagedAppUpdate) throws -> AppInstallRecord {
        let folder = bundleURL.deletingLastPathComponent()
        let backup = folder.appendingPathComponent(AppInstallPolicy.backupName(runningVersion: runningVersion))
        var cleanup = AppInstallCleanup()
        cleanup.did(.temporaryDirectory(staged.directory))
        cleanup.did(.staged(staged.staged))
        do {
            guard backup != bundleURL else { throw AppInstallError.notReplaceable }
            try checkBundleIsRunningApp()
            if files.exists(backup) { try disk { try files.remove(backup) } }
            cleanup.undid(.staged(staged.staged))
            cleanup.did(.swapped(bundle: bundleURL, backup: backup))
            do {
                try files.replace(bundleURL, with: staged.staged, backupName: backup.lastPathComponent)
            } catch {
                cleanup.did(.staged(staged.staged))
                throw AppInstallError.replace
            }
            guard AppInstallPolicy.acceptsVersion(files.shortVersion(of: bundleURL), pinned: staged.version, running: runningVersion) else {
                throw AppInstallError.replace
            }
        } catch {
            performNow(cleanup.onFailure)
            throw log(error, "swap")
        }
        performNow(cleanup.onSuccess)
        Self.logger.info("swapped in \(staged.version, privacy: .public); previous app kept at \(backup.lastPathComponent, privacy: .public)")
        return AppInstallRecord(version: staged.version, bundlePath: bundleURL.path, backupPath: backup.path)
    }

    // Puts the previous app back when Sorla can't restart into the new one.
    public func rollBack(_ record: AppInstallRecord) {
        performNow([.rollBack(bundle: URL(fileURLWithPath: record.bundlePath), backup: URL(fileURLWithPath: record.backupPath))])
    }

    public func discard(_ prepared: PreparedAppUpdate) {
        performNow([.remove(prepared.directory)])
    }

    // Only the copy next to Sorla; the download stays for the next try.
    public func discard(_ staged: StagedAppUpdate) {
        performNow([.remove(staged.staged)])
    }

    // macOS clears old temporary files, so a download that waited long enough may be gone.
    public func isAvailable(_ prepared: PreparedAppUpdate) -> Bool {
        files.exists(prepared.app)
    }

    public func removeBackup(of record: AppInstallRecord) {
        let backup = URL(fileURLWithPath: record.backupPath)
        guard record.backupPath != bundleURL.path, files.exists(backup) else { return }
        performNow([.remove(backup)])
    }

    // Whatever a Sorla that quit or crashed mid-install left behind.
    public func removeLeftovers() async {
        let staged = bundleURL.deletingLastPathComponent().appendingPathComponent(AppInstallPolicy.stagingName)
        var actions: [AppInstallCleanup.Action] = files.exists(staged) ? [.remove(staged)] : []
        for directory in files.leftoverDirectories() {
            actions += [.detach(directory.appendingPathComponent("mount")), .remove(directory)]
        }
        await perform(actions)
    }

    // Checked again right before the swap, since the wait for quiet has no limit.
    private func checkBundleIsRunningApp() throws {
        let found = files.shortVersion(of: bundleURL).flatMap(SemanticVersion.init)
        guard let found, found == runningVersion.flatMap(SemanticVersion.init) else {
            Self.logger.info("Sorla.app on disk is \(found?.description ?? "unreadable", privacy: .public), not the running version; it is kept")
            throw AppInstallError.replacedOnDisk
        }
    }

    private func verify(_ app: URL, version: String) throws {
        guard files.exists(app) else { throw AppInstallError.missingApp }
        do {
            try signatures.checkSignature(of: app, requirement: AppInstallPolicy.codeRequirement)
        } catch {
            throw AppInstallError.signature
        }
        let found = files.shortVersion(of: app)
        guard AppInstallPolicy.acceptsVersion(found, pinned: version, running: runningVersion) else {
            Self.logger.error("version mismatch: found \(found ?? "none", privacy: .public), expected \(version, privacy: .public), running \(runningVersion ?? "none", privacy: .public)")
            throw AppInstallError.version
        }
    }

    private func perform(_ actions: [AppInstallCleanup.Action]) async {
        for action in actions {
            if case .detach(let mountPoint) = action {
                await mounter.detach(mountPoint)
            } else {
                performNow([action])
            }
        }
    }

    private func performNow(_ actions: [AppInstallCleanup.Action]) {
        for action in actions {
            do {
                switch action {
                case .detach:
                    break
                case .remove(let url):
                    if files.exists(url) { try files.remove(url) }
                case .rollBack(let bundle, let backup):
                    guard files.exists(backup) else { continue }
                    if files.exists(bundle) {
                        try files.replace(bundle, with: backup, backupName: nil)
                    } else {
                        try files.move(backup, to: bundle)
                    }
                    Self.logger.info("previous app put back")
                }
            } catch {
                Self.logger.error("cleanup step \(action.name, privacy: .public) failed: \(ErrorSummary.of(error), privacy: .public)")
            }
        }
    }

    private func disk<T>(_ work: () throws -> T) throws -> T {
        do {
            return try work()
        } catch {
            throw AppInstallError.disk
        }
    }

    private func log(_ error: Error, _ step: String) -> Error {
        Self.logger.error("app install \(step, privacy: .public) failed: \(String(describing: error), privacy: .public)")
        return error
    }

    static func downloadError(_ error: Error) -> AppInstallError {
        if case ModelNetworkError.tooLarge = error { return .tooLarge }
        if AppUpdateCheck.failure(for: error) == .offline { return .offline }
        return .download
    }
}
