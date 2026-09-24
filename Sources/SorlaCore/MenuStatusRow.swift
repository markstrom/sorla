import Foundation

public enum MenuStatusAction: Equatable, Sendable {
    case showWelcome
    case downloadModel
    case downloadApp
    case reloadModel
    case openSettings
    case openSoundSettings
    case pasteLastTranscription
    case restart
    case dismiss
}

// An explanation left by the last dictation; it goes when the next one starts or after five minutes.
public struct TransientMenuStatus: Equatable, Sendable {
    public static let lifetime: TimeInterval = 5 * 60

    public let row: MenuStatusRow
    public let shownAt: Date

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

    public static var modelLoadFailed: MenuStatusRow {
        MenuStatusRow(title: String(localized: "\(SorlaIssue.modelNotLoaded.menuTitle) — Try Again", bundle: Localization.bundle), action: .reloadModel)
    }

    // Whatever blocks dictation or shows progress outranks the last dictation's explanation; update offers come after it.
    public static func current(
        microphoneDenied: Bool,
        accessibilityMissing: Bool,
        model: ModelStatus,
        modelLoadFailed: Bool,
        modelLoading: Bool = false,
        appReplaced: Bool = false,
        transient: TransientMenuStatus? = nil,
        appUpdate: String? = nil,
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
        case .failed(_, isUpdate: false):
            return retry(.modelDownloadFailed)
        case .notInstalled:
            return MenuStatusRow(title: String(localized: "Model not installed — Download", bundle: Localization.bundle), action: .downloadModel)
        default:
            break
        }
        if modelLoading {
            return MenuStatusRow(title: String(localized: "Preparing model… ~1 min", bundle: Localization.bundle), action: .openSettings)
        }
        if let transient, !transient.isExpired(at: now) {
            return transient.row
        }
        if case .failed(_, isUpdate: true) = model {
            return retry(.modelUpdateFailed)
        }
        if let appUpdate {
            return MenuStatusRow(title: String(localized: "Sorla \(appUpdate) is available — Download", bundle: Localization.bundle), action: .downloadApp)
        }
        if case .updateAvailable(let version) = model {
            return MenuStatusRow(title: String(localized: "Model update available (\(version))", bundle: Localization.bundle), action: .downloadModel)
        }
        return nil
    }

    private static func retry(_ issue: SorlaIssue) -> MenuStatusRow {
        MenuStatusRow(title: String(localized: "\(issue.menuTitle) — Try Again", bundle: Localization.bundle), action: .downloadModel)
    }
}
