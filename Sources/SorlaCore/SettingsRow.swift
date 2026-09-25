import Foundation

// Every labelled row in Settings, named in one place so tests can check that none is missing or untranslated.
public enum SettingsRow: CaseIterable, Sendable {
    case trigger
    case customShortcut
    case mode
    case model
    case keepClipboardContent
    case playSounds
    case keepLastTranscription
    case pasteLastShortcut
    case launchAtLogin
    case appUpdates
    case speechModel
    case autoCheckUpdates
    case autoInstallUpdates

    public var title: String {
        switch self {
        case .trigger: return String(localized: "Trigger", bundle: Localization.bundle)
        case .customShortcut: return String(localized: "Shortcut", bundle: Localization.bundle)
        case .mode: return String(localized: "Mode", bundle: Localization.bundle)
        case .model: return String(localized: "Model", bundle: Localization.bundle)
        case .keepClipboardContent: return String(localized: "Put back what you had copied", bundle: Localization.bundle)
        case .playSounds: return String(localized: "Play sounds", bundle: Localization.bundle)
        case .keepLastTranscription: return String(localized: "Keep last transcription", bundle: Localization.bundle)
        case .pasteLastShortcut: return String(localized: "Paste last transcription", bundle: Localization.bundle)
        case .launchAtLogin: return String(localized: "Launch at login", bundle: Localization.bundle)
        case .appUpdates: return "Sorla"
        case .speechModel: return String(localized: "Speech model", bundle: Localization.bundle)
        case .autoCheckUpdates: return String(localized: "Check for updates automatically", bundle: Localization.bundle)
        case .autoInstallUpdates: return String(localized: "Install updates automatically", bundle: Localization.bundle)
        }
    }

    // A shortcut recorder shows only the keys, so VoiceOver needs the row's title as its name.
    public var isShortcutField: Bool {
        self == .customShortcut || self == .pasteLastShortcut
    }

    // The hints under Trigger and Launch at login name System Settings items, so they follow the running macOS (#79).
    public static var fnKeyHint: String {
        let pressKeyTo = SystemSettingsName.name(.pressGlobeKeyTo, quoted: true)
        let doNothing = SystemSettingsName.name(.doNothing, quoted: true)
        let keyboard = SystemSettingsName.name(.keyboard)
        return String(localized: "Pressing 🌐/Fn alone may also change the input source, show emoji or start dictation, depending on the system's \(pressKeyTo) setting. Set it to \(doNothing) in \(keyboard) settings.", bundle: Localization.bundle)
    }

    public static var openKeyboardSettings: String {
        String(localized: "Open \(SystemSettingsName.name(.keyboard)) Settings…", bundle: Localization.bundle)
    }

    public static var loginItemApprovalHint: String {
        String(localized: "Sorla needs approval in \(SystemSettingsName.name(.loginItems)) to launch at login.", bundle: Localization.bundle)
    }

    public static var openLoginItemsSettings: String {
        String(localized: "Open \(SystemSettingsName.name(.loginItems)) Settings…", bundle: Localization.bundle)
    }
}
