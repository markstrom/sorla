import Foundation

public enum MenuStatusAction: Equatable, Sendable {
    case openMicrophoneSettings
    case openAccessibilitySettings
    case downloadModel
    case reloadModel
    case openSettings
}

// The menu has room for one status row, so only the most pressing thing is shown.
public struct MenuStatusRow: Equatable, Sendable {
    public let title: String
    public let action: MenuStatusAction

    public init(title: String, action: MenuStatusAction) {
        self.title = title
        self.action = action
    }

    public static func current(
        microphoneDenied: Bool,
        accessibilityMissing: Bool,
        model: ModelStatus,
        modelLoadFailed: Bool
    ) -> MenuStatusRow? {
        if microphoneDenied {
            return MenuStatusRow(title: SorlaIssue.microphoneAccessNeeded.menuTitle ?? "", action: .openMicrophoneSettings)
        }
        if accessibilityMissing {
            return MenuStatusRow(title: SorlaIssue.accessibilityAccessNeeded.menuTitle ?? "", action: .openAccessibilitySettings)
        }
        switch model {
        case .downloading(_, let fraction, _):
            return MenuStatusRow(title: String(localized: "Downloading model… \(ModelStatus.percent(fraction))%", bundle: Localization.bundle), action: .openSettings)
        case .preparing, .waitingToInstall:
            return MenuStatusRow(title: String(localized: "Preparing model… ~1 min", bundle: Localization.bundle), action: .openSettings)
        case .failed(_, let isUpdate):
            let issue: SorlaIssue = isUpdate ? .modelUpdateFailed : .modelDownloadFailed
            return MenuStatusRow(title: String(localized: "\(issue.menuTitle ?? "") — Try Again", bundle: Localization.bundle), action: .downloadModel)
        case .notInstalled:
            return MenuStatusRow(title: String(localized: "Model not installed — Download", bundle: Localization.bundle), action: .downloadModel)
        default:
            break
        }
        if modelLoadFailed {
            return MenuStatusRow(title: String(localized: "\(SorlaIssue.modelNotLoaded.menuTitle ?? "") — Try Again", bundle: Localization.bundle), action: .reloadModel)
        }
        if case .updateAvailable(let version) = model {
            return MenuStatusRow(title: String(localized: "Model update available (\(version))", bundle: Localization.bundle), action: .downloadModel)
        }
        return nil
    }
}
