import Foundation

public enum AppInstallPolicy {
    // The same Team ID and bundle ID as the running app, signed through Apple's Developer ID chain.
    public static let codeRequirement = #"anchor apple generic and certificate leaf[subject.OU] = "V8K5F8X64N" and identifier "com.sorla.app""#
    // Sorla's DMG is about 11 MB, so anything near this is not a Sorla release.
    public static let maximumDownloadSize: Int64 = 100_000_000
    public static let appName = "Sorla.app"
    static let releaseDownloads = "https://github.com/markstrom/sorla/releases/download/"

    public static func assetName(version: String) -> String {
        "Sorla-\(version).dmg"
    }

    // Only the versioned DMG at its fixed GitHub address is taken, so a tampered answer can't choose another file.
    public static func pin(_ release: AppRelease) -> PinnedRelease? {
        guard let version = AppUpdateCheck.version(fromTag: release.tagName) else { return nil }
        let versionText = release.tagName.hasPrefix("v") || release.tagName.hasPrefix("V") ? String(release.tagName.dropFirst()) : release.tagName
        let name = assetName(version: versionText)
        guard let url = URL(string: releaseDownloads + release.tagName + "/" + name),
              let asset = release.assets.first(where: { $0.name == name }),
              asset.downloadURL == url,
              (1...maximumDownloadSize).contains(asset.size)
        else { return nil }
        return PinnedRelease(tag: release.tagName, version: version.description, assetURL: url, assetSize: asset.size)
    }

    // Exactly the version that was checked, and newer than this one: never a downgrade or a surprise.
    public static func acceptsVersion(_ bundleVersion: String?, pinned: String, running: String?) -> Bool {
        guard let found = bundleVersion.flatMap(SemanticVersion.init),
              let expected = SemanticVersion(pinned),
              let current = running.flatMap(SemanticVersion.init)
        else { return false }
        return found == expected && found > current
    }

    // Kept next to Sorla, visibly, so it can be opened by hand if the new version won't start.
    public static func backupName(runningVersion: String?) -> String {
        "Sorla \(runningVersion ?? "previous").app"
    }

    public static let stagingName = ".Sorla-update.app"
}

// Where the running Sorla lives decides whether it may replace itself.
public enum AppInstallLocation: Equatable, Sendable {
    case replaceable
    case translocated
    case notWritable
    case homebrew

    // Homebrew keeps track of what it installed, so it must do the upgrade; a symlink elsewhere isn't ours to replace.
    public static func decide(bundlePath: String, symlinkTarget: String?, isFolderWritable: Bool, isBundleWritable: Bool) -> AppInstallLocation {
        if isInCaskroom(bundlePath) || symlinkTarget.map(isInCaskroom) == true {
            return .homebrew
        }
        if !AppRelaunch.canReopen(URL(fileURLWithPath: bundlePath)) {
            return .translocated
        }
        guard symlinkTarget == nil, isFolderWritable, isBundleWritable else { return .notWritable }
        return .replaceable
    }

    static func isInCaskroom(_ path: String) -> Bool {
        path.split(separator: "/").contains("Caskroom")
    }

    public static func current(bundleURL: URL, fileManager: FileManager = .default) -> AppInstallLocation {
        let path = bundleURL.path
        let target = (try? fileManager.destinationOfSymbolicLink(atPath: path)).map {
            URL(fileURLWithPath: $0, relativeTo: bundleURL.deletingLastPathComponent()).standardizedFileURL.path
        }
        return decide(
            bundlePath: path,
            symlinkTarget: target,
            isFolderWritable: fileManager.isWritableFile(atPath: bundleURL.deletingLastPathComponent().path),
            isBundleWritable: fileManager.isWritableFile(atPath: path)
        )
    }

    public var canInstall: Bool { self == .replaceable }
}

// Every way an install can end early; each one keeps the current app.
public enum AppInstallFailure: Equatable, Sendable {
    case offline
    case download
    case verification
    case replace
    case relaunch

    public var message: String {
        switch self {
        case .offline:
            return String(localized: "Couldn't download the update. Check your internet connection. Sorla wasn't changed.", bundle: Localization.bundle)
        case .download:
            return String(localized: "Couldn't download the update. Sorla wasn't changed. Try again later.", bundle: Localization.bundle)
        case .verification:
            return String(localized: "The update couldn't be verified, so Sorla wasn't changed. Download it from GitHub instead.", bundle: Localization.bundle)
        case .replace:
            return String(localized: "Sorla couldn't replace itself, so this version is kept. Download the update instead.", bundle: Localization.bundle)
        case .relaunch:
            return String(localized: "Sorla couldn't restart, so this version is kept. Try again later.", bundle: Localization.bundle)
        }
    }
}

// What an install has put on disk so far, so every way out undoes exactly that, newest first.
public struct AppInstallCleanup: Equatable, Sendable {
    public enum Step: Equatable, Sendable {
        case temporaryDirectory(URL)
        case mounted(URL)
        case staged(URL)
        case swapped(bundle: URL, backup: URL)
    }

    public enum Action: Equatable, Sendable {
        case detach(URL)
        case remove(URL)
        case rollBack(bundle: URL, backup: URL)

        // Paths can hold the user's name, so logs get only the kind of step.
        public var name: String {
            switch self {
            case .detach: return "detach"
            case .remove: return "remove"
            case .rollBack: return "roll back"
            }
        }
    }

    public private(set) var steps: [Step] = []

    public init() {}

    public mutating func did(_ step: Step) {
        steps.append(step)
    }

    public mutating func undid(_ step: Step) {
        steps.removeAll { $0 == step }
    }

    // The old app goes back in place and the disk image is detached before its folder is removed.
    public var onFailure: [Action] {
        steps.reversed().map(Self.undo)
    }

    // A finished swap stays, and its backup waits until the new app has shown it launches.
    public var onSuccess: [Action] {
        steps.reversed().compactMap { step in
            if case .swapped = step { return nil }
            return Self.undo(step)
        }
    }

    private static func undo(_ step: Step) -> Action {
        switch step {
        case .temporaryDirectory(let url), .staged(let url): return .remove(url)
        case .mounted(let url): return .detach(url)
        case .swapped(let bundle, let backup): return .rollBack(bundle: bundle, backup: backup)
        }
    }
}

// Written just before the relaunch, so the new Sorla can finish up and the old one can be found again.
public struct AppInstallRecord: Codable, Equatable, Sendable {
    public let version: String
    public let bundlePath: String
    public let backupPath: String

    public init(version: String, bundlePath: String, backupPath: String) {
        self.version = version
        self.bundlePath = bundlePath
        self.backupPath = backupPath
    }
}

public enum AppInstallRecovery {
    // Only a Sorla that has run from the original path this long removes the backup, so a crash at launch keeps the old app.
    public static let grace: TimeInterval = 30

    public enum Action: Equatable, Sendable {
        case none
        case keepBackup
        case removeBackupAfterGrace(updatedTo: String?)
    }

    public static func atLaunch(record: AppInstallRecord?, bundlePath: String, runningVersion: String?) -> Action {
        guard let record else { return .none }
        guard record.bundlePath == bundlePath, record.backupPath != bundlePath else { return .keepBackup }
        let isNewVersion = runningVersion.flatMap(SemanticVersion.init).map { $0 == SemanticVersion(record.version) } ?? false
        return .removeBackupAfterGrace(updatedTo: isNewVersion ? record.version : nil)
    }
}

// Automatic installs need both update toggles, and never interrupt: ten quiet minutes, or the next launch.
public enum AutomaticAppInstall {
    public static let idleDelay: TimeInterval = 10 * 60

    public enum Decision: Equatable, Sendable {
        case never
        case now
        case after(TimeInterval)
    }

    public static func isEnabled(autoCheck: Bool, autoInstall: Bool) -> Bool {
        autoCheck && autoInstall
    }

    public static func decide(autoCheck: Bool, autoInstall: Bool, atLaunch: Bool, lastActivity: Date, now: Date, isQuiet: Bool) -> Decision {
        guard isEnabled(autoCheck: autoCheck, autoInstall: autoInstall) else { return .never }
        guard isQuiet else { return .after(idleDelay) }
        if atLaunch { return .now }
        let idle = now.timeIntervalSince(lastActivity)
        return idle >= idleDelay ? .now : .after(idleDelay - max(0, idle))
    }
}

// Gatekeeper's verdict as spctl prints it: accepted, and from a notarized Developer ID.
public enum GatekeeperAssessment {
    public static let arguments = ["--assess", "--type", "execute", "-v"]

    public static func isNotarized(status: Int32, output: String) -> Bool {
        status == 0 && output.split(whereSeparator: \.isNewline).contains { $0 == "source=Notarized Developer ID" }
    }
}

public enum DiskImageCommand {
    public static let hdiutil = URL(fileURLWithPath: "/usr/bin/hdiutil")

    // Read-only and hidden from Finder, at a mount point inside Sorla's private folder.
    public static func attachArguments(image: URL, mountPoint: URL) -> [String] {
        ["attach", "-readonly", "-nobrowse", "-noautoopen", "-quiet", "-mountpoint", mountPoint.path, image.path]
    }

    public static func detachArguments(mountPoint: URL, force: Bool) -> [String] {
        ["detach", mountPoint.path, "-quiet"] + (force ? ["-force"] : [])
    }
}
