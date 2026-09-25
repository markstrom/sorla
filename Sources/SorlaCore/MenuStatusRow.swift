import Foundation

public enum MenuStatusAction: Equatable, Sendable {
    case showWelcome
    case downloadModel
    case downloadApp
    case installApp
    case showUpdates
    case openSettings
    case openSoundSettings
    case pasteLastTranscription
    case restart
    case quit
    case dismiss
}

// An explanation left by the last dictation; it goes when the next one starts or after five minutes.
public struct TransientMenuStatus: Equatable, Sendable {
    public static let lifetime: TimeInterval = 5 * 60

    public let row: MenuStatusRow
    public let shownAt: Date
    // What it explains, so its wording can follow VoiceOver being turned on or off (#64).
    private let issue: SorlaIssue?

    public init?(issue: SorlaIssue, at shownAt: Date) {
        let action: MenuStatusAction
        switch issue {
        case .noInputDevice, .microphoneMuted: action = .openSoundSettings
        case .textOnClipboard: action = .pasteLastTranscription
        case .transcriptionFailed: action = .dismiss
        // A replaced app stays replaced until it restarts, so it has its own row rather than one that expires.
        case .microphoneAccessNeeded, .accessibilityAccessNeeded, .modelNotLoaded, .modelDownloadFailed, .modelUpdateFailed, .appReplaced:
            return nil
        }
        self.row = MenuStatusRow(title: issue.menuTitle, action: action)
        self.shownAt = shownAt
        self.issue = issue
    }

    // Said once after Sorla relaunched into a version it installed itself.
    public init(updatedTo version: String, at shownAt: Date) {
        self.row = MenuStatusRow(title: String(localized: "Sorla was updated to \(version)", bundle: Localization.bundle), action: .dismiss)
        self.shownAt = shownAt
        self.issue = nil
    }

    // The same explanation for the same time, naming Paste Last as `pasteLast` now says. A row that named only ⌘V
    // did so because Paste Last couldn't help, and stays as it is.
    public func rerouted(pasteLast: PasteLastRoute?) -> TransientMenuStatus {
        guard case .textOnClipboard(let named?) = issue, let pasteLast, pasteLast != named,
              let rerouted = TransientMenuStatus(issue: .textOnClipboard(pasteLast: pasteLast), at: shownAt)
        else { return self }
        return rerouted
    }

    public func isExpired(at now: Date) -> Bool {
        now.timeIntervalSince(shownAt) >= Self.lifetime
    }
}

// The menu has room for one status row, so only the most pressing thing is shown.
public struct MenuStatusRow: Equatable, Sendable {
    public let title: String
    public let action: MenuStatusAction

    public init(title: String, action: MenuStatusAction) {
        self.title = title
        self.action = action
    }

    // Each blocker that badges the menu bar icon names itself here and opens the setup window, whose row has the fix (#76).
    public static var modelLoadFailed: MenuStatusRow {
        MenuStatusRow(title: SorlaIssue.modelNotLoaded.menuTitle, action: .showWelcome)
    }

    // Whatever blocks dictation or shows progress outranks the last dictation's explanation; update offers come after it.
    public static func current(
        microphoneDenied: Bool,
        accessibilityMissing: Bool,
        model: ModelStatus,
        modelLoadFailed: Bool,
        modelLoading: Bool = false,
        appReplaced: Bool = false,
        canRestart: Bool = true,
        transient: TransientMenuStatus? = nil,
        appUpdate: AppUpdateOffer? = nil,
        now: Date = Date()
    ) -> MenuStatusRow? {
        if microphoneDenied {
            return MenuStatusRow(title: SorlaIssue.microphoneAccessNeeded.menuTitle, action: .showWelcome)
        }
        if accessibilityMissing {
            return MenuStatusRow(title: SorlaIssue.accessibilityAccessNeeded.menuTitle, action: .showWelcome)
        }
        // Until Sorla restarts its pastes are dropped, and a restart also retries anything below.
        if appReplaced {
            guard canRestart else {
                return MenuStatusRow(title: String(localized: "Sorla has been updated — Quit and open it from Applications", bundle: Localization.bundle), action: .quit)
            }
            return MenuStatusRow(title: SorlaIssue.appReplaced.menuTitle, action: .restart)
        }
        if modelLoadFailed {
            return .modelLoadFailed
        }
        switch model {
        case .downloading(_, let fraction, _):
            return MenuStatusRow(title: String(localized: "Downloading model… \(ModelStatus.percent(fraction))%", bundle: Localization.bundle), action: .openSettings)
        case .preparing, .waitingToInstall:
            return MenuStatusRow(title: String(localized: "Preparing model… ~1 min", bundle: Localization.bundle), action: .openSettings)
        // The setup window's row also says how much space is needed when that is why.
        case .failed(_, isUpdate: false):
            return MenuStatusRow(title: SorlaIssue.modelDownloadFailed.menuTitle, action: .showWelcome)
        case .notInstalled:
            return MenuStatusRow(title: String(localized: "Model not installed", bundle: Localization.bundle), action: .showWelcome)
        default:
            break
        }
        if modelLoading {
            return MenuStatusRow(title: String(localized: "Preparing model… ~1 min", bundle: Localization.bundle), action: .openSettings)
        }
        if let transient, !transient.isExpired(at: now) {
            return transient.row
        }
        // The installed model still works, so this is no blocker and retries straight from the menu.
        if case .failed(_, isUpdate: true) = model {
            return MenuStatusRow(title: String(localized: "\(SorlaIssue.modelUpdateFailed.menuTitle) — Try Again", bundle: Localization.bundle), action: .downloadModel)
        }
        if let appUpdate {
            return appUpdate.menuRow
        }
        if case .updateAvailable(let version) = model {
            return MenuStatusRow(title: String(localized: "Model update available (\(version))", bundle: Localization.bundle), action: .downloadModel)
        }
        return nil
    }
}
