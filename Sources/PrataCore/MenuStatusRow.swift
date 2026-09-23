public enum MenuStatusAction: Equatable, Sendable {
    case openMicrophoneSettings
    case openAccessibilitySettings
    case downloadModel
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
            return MenuStatusRow(title: PrataIssue.microphoneAccessNeeded.menuTitle ?? "", action: .openMicrophoneSettings)
        }
        if accessibilityMissing {
            return MenuStatusRow(title: PrataIssue.accessibilityAccessNeeded.menuTitle ?? "", action: .openAccessibilitySettings)
        }
        switch model {
        case .downloading(_, let fraction, _):
            return MenuStatusRow(title: "Downloading Swedish model… \(ModelStatus.percent(fraction))%", action: .openSettings)
        case .preparing, .waitingToInstall:
            return MenuStatusRow(title: "Preparing Swedish model…", action: .openSettings)
        case .failed(_, let isUpdate):
            let issue: PrataIssue = isUpdate ? .modelUpdateFailed : .modelDownloadFailed
            return MenuStatusRow(title: "\(issue.menuTitle ?? "") — Try Again", action: .downloadModel)
        case .notInstalled:
            return MenuStatusRow(title: "Swedish model not installed — Download", action: .downloadModel)
        default:
            break
        }
        if modelLoadFailed {
            return MenuStatusRow(title: PrataIssue.modelNotLoaded.menuTitle ?? "", action: .openSettings)
        }
        if case .updateAvailable(let version) = model {
            return MenuStatusRow(title: "Model update available (\(version))", action: .downloadModel)
        }
        return nil
    }
}
