import Foundation

// Wording for every user-visible problem lives here, so the menu row and the indicator cue always agree.
public enum SorlaIssue: Hashable, Sendable {
    case microphoneAccessNeeded
    case accessibilityAccessNeeded
    case modelNotLoaded
    case noInputDevice
    case transcriptionFailed
    case modelDownloadFailed
    case modelUpdateFailed
    case microphoneMuted
    case textOnClipboard(pasteShortcut: String)
    case appReplaced

    public var menuTitle: String {
        switch self {
        case .microphoneAccessNeeded: return String(localized: "Microphone access needed", bundle: Localization.bundle)
        case .accessibilityAccessNeeded: return String(localized: "\(AccessibilityPaneName.current) permission needed to paste", bundle: Localization.bundle)
        case .modelNotLoaded: return String(localized: "Model couldn't be loaded", bundle: Localization.bundle)
        case .modelDownloadFailed: return String(localized: "Model download failed", bundle: Localization.bundle)
        case .modelUpdateFailed: return String(localized: "Model update failed", bundle: Localization.bundle)
        case .noInputDevice: return String(localized: "No microphone found — check Sound › Input", bundle: Localization.bundle)
        case .transcriptionFailed: return String(localized: "Couldn't transcribe the last recording", bundle: Localization.bundle)
        case .microphoneMuted: return String(localized: "Microphone seems to be muted — check Sound › Input", bundle: Localization.bundle)
        case .textOnClipboard(let pasteShortcut): return String(localized: "Text is on the clipboard — press \(pasteShortcut)", bundle: Localization.bundle)
        case .appReplaced: return String(localized: "Sorla has been updated — Restart", bundle: Localization.bundle)
        }
    }

    public var settingsURL: URL? {
        switch self {
        case .microphoneAccessNeeded:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .accessibilityAccessNeeded:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .noInputDevice, .microphoneMuted:
            return URL(string: "x-apple.systempreferences:com.apple.preference.sound?input")
        case .modelNotLoaded, .transcriptionFailed, .modelDownloadFailed, .modelUpdateFailed, .textOnClipboard, .appReplaced:
            return nil
        }
    }
}
