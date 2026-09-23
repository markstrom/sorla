import CoreGraphics

public enum TriggerHint {
    public static func menuTitle(for mode: RecordingMode) -> String {
        switch mode {
        case .pushToTalk: return "Hold to Record"
        case .toggle: return "Press to Record"
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

    public static let menuKeyGap: CGFloat = 24

    // Right tab stop for "title<TAB>key": past the title plus a gap, and never short of the widest other title.
    public static func menuTabStop(titleWidth: CGFloat, keyWidth: CGFloat, otherTitleWidths: [CGFloat]) -> CGFloat {
        max(titleWidth + menuKeyGap + keyWidth, otherTitleWidths.max() ?? 0)
    }
}
