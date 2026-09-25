import Foundation

// How Sorla's own messages tell someone to reach Paste Last (#64). Its default ⌃⌥V is VoiceOver's VO-V, which
// VoiceOver may take for itself, so while VoiceOver runs they name the menu item, and how to get there, instead.
public enum PasteLastRoute: Hashable, Sendable {
    case shortcut(String)
    case menu

    // nil when Paste Last has no shortcut and VoiceOver is off; a text on the clipboard then pastes with ⌘V.
    public static func current(shortcut: String?, isVoiceOverRunning: Bool) -> PasteLastRoute? {
        if isVoiceOverRunning { return .menu }
        guard let shortcut, !shortcut.isEmpty else { return nil }
        return .shortcut(shortcut)
    }

    // The keys the sentence names, set apart as a keycap in a window.
    public var keys: String {
        switch self {
        case .shortcut(let shortcut): return shortcut
        case .menu: return "VO-M"
        }
    }
}
