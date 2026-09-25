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
        // Nothing was downloaded, so the row says how much room is needed rather than that the download failed.
        case .failed(.insufficientDiskSpace(let required), _):
            return .needsAction(.downloadModel, buttonTitle: tryAgain, note: ModelInstallError.insufficientDiskSpace(required: required).reason)
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
            return String(localized: "Fix the items above to try dictation.", bundle: Localization.bundle)
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

    // A window that still needs something offers "Not now"; one that is ready is "Done" (#72).
    public static func closeButtonTitle(isReady: Bool) -> String {
        isReady ? String(localized: "Done", bundle: Localization.bundle) : RecoveryDialog.notNow
    }

    // Opened because a paste was blocked. Only said while the text really is on the clipboard,
    // and Paste Last isn't offered, since it needs the same access (#72).
    // The window has the focus, so ⌘V only works back where the user was typing; closing it takes them there.
    public static func pasteBlockedMessage(isTextOnClipboard: Bool, isAccessibilityTrusted: Bool) -> String? {
        guard isTextOnClipboard else { return nil }
        guard !isAccessibilityTrusted else { return textOnClipboardInWindow }
        return String(localized: "The text is ready, but Sorla needs Accessibility access to paste it. The text is on the clipboard — close this window and press ⌘V where you were typing.", bundle: Localization.bundle)
    }

    public static var textOnClipboardInWindow: String {
        String(localized: "Your text is on the clipboard — close this window and press ⌘V where you were typing.", bundle: Localization.bundle)
    }

    // What the two update toggles really do right now; both are off until the user turns them on (#73).
    public static func updatesNote(autoCheck: Bool, autoInstall: Bool) -> String {
        switch (autoCheck, autoInstall) {
        case (false, false):
            return String(localized: "Automatic update checks and installation are off. You can turn them on in Settings.", bundle: Localization.bundle)
        // Installing needs the checks, in Settings and for both the app and the model, so the stored choice waits.
        case (false, true):
            return String(localized: "Automatic update checks are off, so nothing is installed automatically until you turn them on in Settings.", bundle: Localization.bundle)
        case (true, false):
            return String(localized: "Sorla checks for updates automatically but doesn't install them. You can change this in Settings.", bundle: Localization.bundle)
        case (true, true):
            return String(localized: "Sorla checks for updates and installs them automatically. You can change this in Settings.", bundle: Localization.bundle)
        }
    }

    public static var updateSettingsButtonTitle: String { String(localized: "Update Settings", bundle: Localization.bundle) }
    public static var updateSettingsButtonName: String { String(localized: "Open Updates in Settings", bundle: Localization.bundle) }

    private static var openSystemSettings: String { String(localized: "Open System Settings", bundle: Localization.bundle) }
    private static var tryAgain: String { String(localized: "Try Again", bundle: Localization.bundle) }
    private static var preparing: String { String(localized: "Preparing model… ~1 min", bundle: Localization.bundle) }
}
