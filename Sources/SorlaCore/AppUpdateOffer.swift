import Foundation

// How Sorla can take the version a check found, for the Settings row and the menu's status row alike.
public enum AppUpdateOffer: Equatable, Sendable {
    case install(version: String)
    case download(version: String, note: String? = nil)
    case homebrew(version: String)
    case downloading(version: String, fraction: Double)
    case installing(version: String)
    case failed(version: String, AppInstallFailure)

    public static var homebrewCommand: String { "brew upgrade --cask sorla" }

    // Installing needs the exact release pinned and a place Sorla may replace itself; otherwise it is the download page.
    public static func make(status: AppUpdateStatus, pin: PinnedRelease?, install: AppInstallState, location: AppInstallLocation) -> AppUpdateOffer? {
        switch install {
        case .downloading(let version, let fraction): return .downloading(version: version, fraction: fraction)
        case .installing(let version): return .installing(version: version)
        case .failed(let version, let failure): return .failed(version: version, failure)
        case .idle, .ready: break
        }
        guard let version = status.availableVersion else { return nil }
        switch location {
        case .homebrew:
            return .homebrew(version: version)
        case .translocated:
            return .download(version: version, note: String(localized: "To install updates from Sorla, quit it and open it from Applications.", bundle: Localization.bundle))
        case .notWritable:
            return .download(version: version, note: String(localized: "Sorla can't replace itself in this folder. Download the update and drag it to Applications.", bundle: Localization.bundle))
        case .replaceable:
            let isPinned = pin.flatMap { SemanticVersion($0.version) } == SemanticVersion(version)
            return isPinned ? .install(version: version) : .download(version: version)
        }
    }

    public var version: String {
        switch self {
        case .install(let version), .download(let version, _), .homebrew(let version), .downloading(let version, _),
             .installing(let version), .failed(let version, _):
            return version
        }
    }

    public var isInstalling: Bool {
        switch self {
        case .downloading, .installing: return true
        case .install, .download, .homebrew, .failed: return false
        }
    }

    // For the log: what is offered, never the wording or a path.
    public var kind: String {
        switch self {
        case .install: return "install"
        case .download(_, let note): return note == nil ? "download (no installable DMG pinned)" : "download (Sorla can't replace itself here)"
        case .homebrew: return "homebrew"
        case .downloading: return "downloading"
        case .installing: return "installing"
        case .failed(_, let failure): return "failed (\(failure))"
        }
    }

    public var menuRow: MenuStatusRow {
        switch self {
        case .install(let version):
            return MenuStatusRow(title: String(localized: "Sorla \(version) is available — Install and Relaunch", bundle: Localization.bundle), action: .installApp)
        case .download(let version, _):
            return MenuStatusRow(title: String(localized: "Sorla \(version) is available — Download", bundle: Localization.bundle), action: .downloadApp)
        case .homebrew(let version):
            return MenuStatusRow(title: String(localized: "Sorla \(version) is available — Update with Homebrew", bundle: Localization.bundle), action: .showUpdates)
        case .downloading(let version, let fraction):
            return MenuStatusRow(title: String(localized: "Downloading Sorla \(version)… \(AppUpdateDecision.percent(fraction))%", bundle: Localization.bundle), action: .showUpdates)
        case .installing(let version):
            return MenuStatusRow(title: String(localized: "Installing Sorla \(version)…", bundle: Localization.bundle), action: .showUpdates)
        case .failed(let version, _):
            return MenuStatusRow(title: String(localized: "Couldn't install Sorla \(version) — Download", bundle: Localization.bundle), action: .downloadApp)
        }
    }
}
