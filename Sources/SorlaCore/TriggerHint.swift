import Foundation

public enum TriggerHint {
    // The menu row starts and stops dictation for people who can't use the key, and names the key for everyone else.
    public static func menuTitle(trigger: TriggerKey, mode: RecordingMode, customShortcut: String?, isRecording: Bool = false) -> String {
        if isRecording {
            return String(localized: "Stop Dictation", bundle: Localization.bundle)
        }
        if trigger == .customShortcut, customShortcut?.isEmpty ?? true {
            return String(localized: "Start Dictation", bundle: Localization.bundle)
        }
        let key = keyLabel(for: trigger, customShortcut: customShortcut)
        switch mode {
        case .pushToTalk: return String(localized: "Start Dictation (Hold \(key))", bundle: Localization.bundle)
        case .toggle: return String(localized: "Start Dictation (Press \(key))", bundle: Localization.bundle)
        }
    }

    public static func keyLabel(for trigger: TriggerKey, customShortcut: String?) -> String {
        guard trigger == .customShortcut else { return trigger.displayName }
        guard let customShortcut, !customShortcut.isEmpty else { return String(localized: "Not set", bundle: Localization.bundle) }
        return customShortcut
    }

    public static func explanation(trigger: TriggerKey, mode: RecordingMode, customShortcut: String?) -> String {
        if trigger == .customShortcut, customShortcut?.isEmpty ?? true {
            return String(localized: "Record a shortcut above to start dictating.", bundle: Localization.bundle)
        }
        let key = keyLabel(for: trigger, customShortcut: customShortcut)
        switch mode {
        case .pushToTalk: return String(localized: "Hold \(key) while speaking; release to paste.", bundle: Localization.bundle)
        case .toggle: return String(localized: "Press \(key) to start, press again to stop.", bundle: Localization.bundle)
        }
    }

    public static func readyMessage(trigger: TriggerKey, mode: RecordingMode, customShortcut: String?) -> String {
        if trigger == .customShortcut, customShortcut?.isEmpty ?? true {
            return String(localized: "Sorla is ready. Set a shortcut in Settings to dictate.", bundle: Localization.bundle)
        }
        let key = keyLabel(for: trigger, customShortcut: customShortcut)
        switch mode {
        case .pushToTalk: return String(localized: "Sorla is ready. Hold \(key) to dictate.", bundle: Localization.bundle)
        case .toggle: return String(localized: "Sorla is ready. Press \(key) to dictate.", bundle: Localization.bundle)
        }
    }
}
