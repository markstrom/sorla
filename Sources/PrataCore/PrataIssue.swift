import Foundation

// Wording for every user-visible problem lives here, so the menu row and the notification always agree.
public enum PrataIssue: Hashable, Sendable {
    case microphoneAccessNeeded
    case accessibilityAccessNeeded
    case modelNotLoaded
    case noInputDevice
    case transcriptionFailed
    case modelDownloadFailed
    case modelUpdateFailed

    public var menuTitle: String? {
        switch self {
        case .microphoneAccessNeeded: return "Microphone access needed"
        case .accessibilityAccessNeeded: return "Accessibility access needed to paste"
        case .modelNotLoaded: return "Swedish model couldn't be loaded"
        case .modelDownloadFailed: return "Swedish model download failed"
        case .modelUpdateFailed: return "Model update failed"
        case .noInputDevice, .transcriptionFailed: return nil
        }
    }

    public var notificationBody: String? {
        switch self {
        case .microphoneAccessNeeded:
            return "Couldn't record — grant Prata access to the microphone in System Settings."
        case .accessibilityAccessNeeded:
            return "Your text is on the clipboard — press ⌘V. Grant Accessibility access so Prata can paste for you."
        case .modelNotLoaded:
            return "The Swedish model couldn't be loaded. Dictation won't work until this is fixed."
        case .noInputDevice:
            return "Couldn't start recording: no microphone found."
        case .transcriptionFailed:
            return "Couldn't transcribe that recording."
        case .modelDownloadFailed:
            return "Couldn't download the Swedish model. Open the Prata menu to try again."
        case .modelUpdateFailed:
            return "Couldn't install the model update. Prata keeps using the current model."
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
