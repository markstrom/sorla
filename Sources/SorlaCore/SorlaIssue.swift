import Foundation

// Wording for every user-visible problem lives here, so the menu row and the notification always agree.
public enum SorlaIssue: Hashable, Sendable {
    case microphoneAccessNeeded
    case accessibilityAccessNeeded
    case modelNotLoaded
    case noInputDevice
    case transcriptionFailed
    case modelDownloadFailed
    case modelUpdateFailed

    public var menuTitle: String? {
        switch self {
        case .microphoneAccessNeeded: return String(localized: "Microphone access needed", bundle: Localization.bundle)
        case .accessibilityAccessNeeded: return String(localized: "Accessibility access needed to paste", bundle: Localization.bundle)
        case .modelNotLoaded: return String(localized: "Model couldn't be loaded", bundle: Localization.bundle)
        case .modelDownloadFailed: return String(localized: "Model download failed", bundle: Localization.bundle)
        case .modelUpdateFailed: return String(localized: "Model update failed", bundle: Localization.bundle)
        case .noInputDevice, .transcriptionFailed: return nil
        }
    }

    public var notificationBody: String? {
        switch self {
        case .microphoneAccessNeeded:
            return String(localized: "Couldn't record — grant Sorla access to the microphone in System Settings.", bundle: Localization.bundle)
        case .accessibilityAccessNeeded:
            return String(localized: "Your text is on the clipboard — press ⌘V. Grant Accessibility access so Sorla can paste for you.", bundle: Localization.bundle)
        case .modelNotLoaded:
            return String(localized: "The model couldn't be loaded. Dictation won't work until this is fixed.", bundle: Localization.bundle)
        case .noInputDevice:
            return String(localized: "Couldn't start recording: no microphone found.", bundle: Localization.bundle)
        case .transcriptionFailed:
            return String(localized: "Couldn't transcribe that recording.", bundle: Localization.bundle)
        case .modelDownloadFailed:
            return String(localized: "Couldn't download the model. Open the Sorla menu to try again.", bundle: Localization.bundle)
        case .modelUpdateFailed:
            return String(localized: "Couldn't install the model update. Sorla keeps using the current model.", bundle: Localization.bundle)
        }
    }

    public var settingsURL: URL? {
        switch self {
        case .microphoneAccessNeeded:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .accessibilityAccessNeeded:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .modelNotLoaded, .noInputDevice, .transcriptionFailed, .modelDownloadFailed, .modelUpdateFailed:
            return nil
        }
    }
}
