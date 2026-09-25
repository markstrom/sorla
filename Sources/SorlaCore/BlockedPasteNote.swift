import Foundation

// What the Set Up Sorla window says about a paste that was blocked (#72). Sorla left the clipboard as it was, so the
// text is only where Paste Last keeps it: five minutes, forgotten at a lock, and not at all with the setting off.
public enum BlockedPasteNote: Equatable, Sendable, CaseIterable {
    case kept
    // Keep last transcription was off when the paste was blocked.
    case notSaved
    // Saved, then gone: the five minutes ran out, the Mac locked or the setting was turned off.
    case noLongerKept

    public init(wasSaved: Bool, isTextKept: Bool) {
        switch (wasSaved, isTextKept) {
        case (true, true): self = .kept
        case (true, false): self = .noLongerKept
        case (false, _): self = .notSaved
        }
    }

    // Without a shortcut, or with VoiceOver (#64), the menu item is named instead of the keys.
    public func message(pasteLast: PasteLastRoute?) -> String {
        switch self {
        case .kept:
            return Self.keptMessage(pasteLast) + " " + String(localized: "A test dictation in Try it here replaces the saved text.", bundle: Localization.bundle)
        case .notSaved:
            return String(localized: "The text couldn't be saved. Grant the permission and dictate again.", bundle: Localization.bundle)
        case .noLongerKept:
            return String(localized: "The text is no longer saved. Grant the permission and dictate again.", bundle: Localization.bundle)
        }
    }

    private static func keptMessage(_ pasteLast: PasteLastRoute?) -> String {
        switch pasteLast {
        case .shortcut(let shortcut):
            return String(localized: "The text is saved. Grant the permission, click where you want to type and choose Paste Last Transcription (\(shortcut)).", bundle: Localization.bundle)
        case .menu:
            return String(localized: "The text is saved. Grant the permission, click where you want to type and choose Paste Last Transcription in Sorla's menu (VO-M twice).", bundle: Localization.bundle)
        case nil:
            return String(localized: "The text is saved. Grant the permission, click where you want to type and choose Paste Last Transcription in Sorla's menu.", bundle: Localization.bundle)
        }
    }
}
