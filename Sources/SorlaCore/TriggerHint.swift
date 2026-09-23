public enum TriggerHint {
    public static func menuTitle(trigger: TriggerKey, mode: RecordingMode, customShortcut: String?) -> String {
        if trigger == .customShortcut, customShortcut?.isEmpty ?? true {
            return "Record: Shortcut Not Set"
        }
        let key = keyLabel(for: trigger, customShortcut: customShortcut)
        switch mode {
        case .pushToTalk: return "Hold \(key) to Record"
        case .toggle: return "Press \(key) to Record"
        }
    }

    public static func keyLabel(for trigger: TriggerKey, customShortcut: String?) -> String {
        guard trigger == .customShortcut else { return trigger.displayName }
        guard let customShortcut, !customShortcut.isEmpty else { return "Not set" }
        return customShortcut
    }

    public static func explanation(trigger: TriggerKey, mode: RecordingMode, customShortcut: String?) -> String {
        if trigger == .customShortcut, customShortcut?.isEmpty ?? true {
            return "Record a shortcut above to start dictating."
        }
        let key = keyLabel(for: trigger, customShortcut: customShortcut)
        switch mode {
        case .pushToTalk: return "Hold \(key) while speaking; release to paste."
        case .toggle: return "Press \(key) to start, press again to stop."
        }
    }

    public static func readyMessage(trigger: TriggerKey, mode: RecordingMode, customShortcut: String?) -> String {
        if trigger == .customShortcut, customShortcut?.isEmpty ?? true {
            return "Sorla is ready. Set a shortcut in Settings to dictate."
        }
        let key = keyLabel(for: trigger, customShortcut: customShortcut)
        switch mode {
        case .pushToTalk: return "Sorla is ready. Hold \(key) to dictate."
        case .toggle: return "Sorla is ready. Press \(key) to dictate."
        }
    }
}
