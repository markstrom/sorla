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

    // The line under the row's purpose: what went wrong, or what to try.
    public var note: String? {
        switch self {
        // What is in progress is the row's status text instead, beside the spinner.
        case .done, .inProgress: return nil
        case .needsAction(_, _, let note): return note
        }
    }

    public var buttonTitle: String? {
        guard case .needsAction(_, let buttonTitle, _) = self else { return nil }
        return buttonTitle
    }

}

public enum WelcomeRow: CaseIterable, Sendable {
    case microphone
    case accessibility
    case model

    public var title: String {
        switch self {
        case .microphone: return String(localized: "Microphone", bundle: Localization.bundle)
        // Says what the permission is for; the name macOS gives it (#74) is in the explanation and the button's name.
        case .accessibility: return String(localized: "Automatic Pasting", bundle: Localization.bundle)
        case .model: return String(localized: "Speech Model", bundle: Localization.bundle)
        }
    }

    // Beside the marker, so the row's state reads without its colour, and VoiceOver reads it as the row's value (#75).
    public func statusText(_ status: WelcomeRowStatus) -> String {
        switch (self, status) {
        case (_, .inProgress(let text)):
            return text
        case (.model, .done):
            return String(localized: "Ready", bundle: Localization.bundle)
        case (.model, .needsAction(.reloadModel, _, _)):
            return String(localized: "Couldn't load", bundle: Localization.bundle)
        case (.model, .needsAction):
            return String(localized: "Missing", bundle: Localization.bundle)
        case (_, .done):
            return String(localized: "Allowed", bundle: Localization.bundle)
        case (_, .needsAction):
            return String(localized: "Permission missing", bundle: Localization.bundle)
        }
    }

    public var purpose: String {
        switch self {
        case .microphone: return String(localized: "So Sorla can hear you.", bundle: Localization.bundle)
        case .accessibility:
            return String(localized: "So Sorla can paste where you type. In System Settings the permission is called \(SystemSettingsName.name(.accessibility)).", bundle: Localization.bundle)
        case .model: return Localization.bundle.localizedString(forKey: PianissimoModel.displayName, value: nil, table: nil)
        }
    }

    // Every kind of state the row can show, so the window can keep room for the largest and not jump when one changes (#75).
    public var possibleStatuses: [WelcomeRowStatus] {
        switch self {
        case .microphone:
            return [MicrophoneAccess.granted, .notDetermined, .denied].map(WelcomeChecklist.microphoneRow)
        case .accessibility:
            return [true, false].map { WelcomeChecklist.accessibilityRow(isTrusted: $0) }
        case .model:
            let installed: [WelcomeRowStatus] = [
                WelcomeChecklist.modelRow(isInstalled: true, isLoaded: true, loadFailed: false, model: .installed(version: "1")),
                WelcomeChecklist.modelRow(isInstalled: true, isLoaded: false, loadFailed: true, model: .installed(version: "1")),
            ]
            // 100 % and nearly 10 GB are the widest a percentage and a size get.
            let missing: [ModelStatus] = [
                .notInstalled,
                .downloading(version: "1", fraction: 1, isUpdate: false),
                .preparing(version: "1", isUpdate: false),
                .failed(.network, isUpdate: false),
                .failed(.network, isUpdate: true),
                .failed(.insufficientDiskSpace(required: 9_900_000_000), isUpdate: false),
            ]
            return installed + missing.map { WelcomeChecklist.modelRow(isInstalled: false, isLoaded: false, loadFailed: false, model: $0) }
        }
    }
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

    // macOS can keep an old grant that no longer matches the app, and then only a relaunch helps.
    public static func accessibilityRow(isTrusted: Bool) -> WelcomeRowStatus {
        isTrusted ? .done : .needsAction(
            .openAccessibilitySettings,
            buttonTitle: openSystemSettings,
            note: String(localized: "Switch already on? Quit and reopen Sorla.", bundle: Localization.bundle)
        )
    }

    // An installed model only counts once it's loaded, since dictation is refused while it loads.
    public static func modelRow(isInstalled: Bool, isLoaded: Bool, loadFailed: Bool, model: ModelStatus) -> WelcomeRowStatus {
        if isInstalled {
            if isLoaded { return .done }
            // "Couldn't load" beside the marker says it all.
            if loadFailed {
                return .needsAction(.reloadModel, buttonTitle: tryAgain, note: nil)
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
        // "Missing" beside the marker says it all.
        default:
            return .needsAction(.downloadModel, buttonTitle: String(localized: "Download", bundle: Localization.bundle), note: nil)
        }
    }

    public static func isReady(microphone: WelcomeRowStatus, accessibility: WelcomeRowStatus, model: WelcomeRowStatus) -> Bool {
        microphone.isDone && accessibility.isDone && model.isDone
    }

    // Above Try it here, so it says where to click and how to dictate with the chosen key and mode.
    public static func readinessLine(isReady: Bool, trigger: TriggerKey, mode: RecordingMode, customShortcut: String?) -> String {
        guard isReady else { return notReadyLine }
        if trigger == .customShortcut, customShortcut?.isEmpty ?? true {
            return String(localized: "Sorla is ready. Set a shortcut in Settings to dictate.", bundle: Localization.bundle)
        }
        let key = TriggerHint.keyLabel(for: trigger, customShortcut: customShortcut)
        switch mode {
        case .pushToTalk:
            return String(localized: "Sorla is ready. Click in the field below, hold down \(key), speak and release.", bundle: Localization.bundle)
        case .toggle:
            return String(localized: "Sorla is ready. Click in the field below, press \(key) once to start and once more to stop.", bundle: Localization.bundle)
        }
    }

    public static var notReadyLine: String {
        String(localized: "Fix the items above to try dictation.", bundle: Localization.bundle)
    }

    // Holding a key down can be hard, so the easier mode is named where people start.
    public static func toggleModeTip(mode: RecordingMode) -> String? {
        guard mode == .pushToTalk else { return nil }
        return String(localized: "Hard to hold a key down? Choose Toggle under Mode in Settings.", bundle: Localization.bundle)
    }

    // Two rows can show "Open System Settings", so Tab and VoiceOver's control list get what each button acts on (#61).
    public static func buttonName(_ status: WelcomeRowStatus) -> String? {
        guard case .needsAction(let action, let buttonTitle, _) = status else { return nil }
        switch action {
        case .requestMicrophone:
            return String(localized: "Allow microphone access", bundle: Localization.bundle)
        case .openMicrophoneSettings:
            return String(localized: "Open \(SystemSettingsName.name(.microphone)) in System Settings", bundle: Localization.bundle)
        case .openAccessibilitySettings:
            return String(localized: "Open \(SystemSettingsName.name(.accessibility)) in System Settings", bundle: Localization.bundle)
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

    public static var updatesHeading: String { String(localized: "Updates", bundle: Localization.bundle) }

    // Why someone would turn each switch on; both stay off until they do (#73).
    public static var autoCheckReason: String {
        String(localized: "Get fixes and new versions of the speech model without having to remember to check.", bundle: Localization.bundle)
    }

    public static var autoInstallReason: String {
        String(localized: "Installs them when you haven't dictated for a while. Needs automatic checks.", bundle: Localization.bundle)
    }

    private static var openSystemSettings: String { String(localized: "Open System Settings", bundle: Localization.bundle) }
    private static var tryAgain: String { String(localized: "Try Again", bundle: Localization.bundle) }
    private static var preparing: String { String(localized: "Preparing model… ~1 min", bundle: Localization.bundle) }
}
