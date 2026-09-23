import Foundation

public enum MicrophoneAccess: Equatable, Sendable {
    case granted
    case notDetermined
    case denied
}

public enum WelcomeAction: Equatable, Sendable {
    case requestMicrophone
    case openMicrophoneSettings
    case openAccessibilitySettings
    case downloadModel
    case reloadModel
}

public enum WelcomeRowStatus: Equatable, Sendable {
    case done
    case inProgress(String)
    case needsAction(WelcomeAction, buttonTitle: String, note: String?)

    public var isDone: Bool { self == .done }
}

// The welcome window's three rows: what each still needs, and when Sorla is ready to dictate.
public enum WelcomeChecklist {
    public static func shouldShow(hasCompletedOnboarding: Bool, microphone: MicrophoneAccess, isAccessibilityTrusted: Bool) -> Bool {
        !hasCompletedOnboarding || microphone != .granted || !isAccessibilityTrusted
    }

    public static func microphoneRow(_ access: MicrophoneAccess) -> WelcomeRowStatus {
        switch access {
        case .granted:
            return .done
        case .notDetermined:
            return .needsAction(.requestMicrophone, buttonTitle: String(localized: "Allow", bundle: Localization.bundle), note: nil)
        case .denied:
            return .needsAction(.openMicrophoneSettings, buttonTitle: openSystemSettings, note: nil)
        }
    }

    public static func accessibilityRow(isTrusted: Bool) -> WelcomeRowStatus {
        isTrusted ? .done : .needsAction(.openAccessibilitySettings, buttonTitle: openSystemSettings, note: nil)
    }

    // An installed model only counts once it's loaded, since dictation is refused while it loads.
    public static func modelRow(isInstalled: Bool, isLoaded: Bool, loadFailed: Bool, model: ModelStatus) -> WelcomeRowStatus {
        if isInstalled {
            if isLoaded { return .done }
            if loadFailed {
                return .needsAction(.reloadModel, buttonTitle: tryAgain, note: SorlaIssue.modelNotLoaded.menuTitle)
            }
            return .inProgress(preparing)
        }
        switch model {
        case .downloading(_, let fraction, _):
            return .inProgress(String(localized: "Downloading model… \(ModelStatus.percent(fraction))%", bundle: Localization.bundle))
        case .preparing, .waitingToInstall:
            return .inProgress(preparing)
        case .failed(_, let isUpdate):
            let issue: SorlaIssue = isUpdate ? .modelUpdateFailed : .modelDownloadFailed
            return .needsAction(.downloadModel, buttonTitle: tryAgain, note: issue.menuTitle)
        default:
            return .needsAction(.downloadModel, buttonTitle: String(localized: "Download", bundle: Localization.bundle), note: ModelStatus.notInstalled.settingsText)
        }
    }

    public static func isReady(microphone: WelcomeRowStatus, accessibility: WelcomeRowStatus, model: WelcomeRowStatus) -> Bool {
        microphone.isDone && accessibility.isDone && model.isDone
    }

    public static func readinessLine(isReady: Bool, trigger: TriggerKey, mode: RecordingMode, customShortcut: String?) -> String {
        guard isReady else {
            return String(localized: "Dictation works once all three are done.", bundle: Localization.bundle)
        }
        return TriggerHint.readyMessage(trigger: trigger, mode: mode, customShortcut: customShortcut)
    }

    private static var openSystemSettings: String { String(localized: "Open System Settings", bundle: Localization.bundle) }
    private static var tryAgain: String { String(localized: "Try Again", bundle: Localization.bundle) }
    private static var preparing: String { String(localized: "Preparing model… ~1 min", bundle: Localization.bundle) }
}
