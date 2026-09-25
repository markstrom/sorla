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

    // Holding a key down can be hard, so the easier mode is named where people start.
    public static func toggleModeTip(mode: RecordingMode) -> String? {
        guard mode == .pushToTalk else { return nil }
        return String(localized: "Hard to hold a key down? Choose Toggle under Mode in Settings: press once to start and again to stop.", bundle: Localization.bundle)
    }

    // Two rows can show "Open System Settings", so Tab and VoiceOver's control list get what each button acts on (#61).
    public static func buttonName(_ status: WelcomeRowStatus) -> String? {
        guard case .needsAction(let action, let buttonTitle, _) = status else { return nil }
        switch action {
        case .requestMicrophone:
            return String(localized: "Allow microphone access", bundle: Localization.bundle)
        case .openMicrophoneSettings:
            return String(localized: "Open Microphone in System Settings", bundle: Localization.bundle)
        case .openAccessibilitySettings:
            return String(localized: "Open Accessibility in System Settings", bundle: Localization.bundle)
        case .downloadModel where buttonTitle == tryAgain:
            return String(localized: "Try downloading the model again", bundle: Localization.bundle)
        case .downloadModel:
            return String(localized: "Download the speech model", bundle: Localization.bundle)
        case .reloadModel:
            return String(localized: "Try loading the model again", bundle: Localization.bundle)
        }
    }

    private static var openSystemSettings: String { String(localized: "Open System Settings", bundle: Localization.bundle) }
    private static var tryAgain: String { String(localized: "Try Again", bundle: Localization.bundle) }
    private static var preparing: String { String(localized: "Preparing model… ~1 min", bundle: Localization.bundle) }
}
