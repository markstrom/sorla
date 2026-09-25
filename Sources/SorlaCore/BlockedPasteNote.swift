import Foundation

// What the Set Up Sorla window says about a paste that was blocked, and what it offers (#72). The clipboard is only
// mentioned while the text really is there, and Paste Last only once it can work, since it needs the same access.
public enum BlockedPasteNote: Equatable, Sendable, CaseIterable {
    // Access is missing and the text is on the clipboard, for the user's own ⌘V.
    case onClipboardNeedsAccess
    // Access is missing and only Sorla has the text; the user's clipboard is as it was, and Copy Text changes that.
    case savedNeedsAccess
    // Access is there: one button pastes where the user was typing.
    case readyToPaste
    // Access is there, but Sorla no longer has the text; the clipboard still does.
    case onClipboard
    // Neither Sorla nor the clipboard has it any more.
    case gone

    public static func current(isTextOnClipboard: Bool, isTextKept: Bool, isAccessibilityTrusted: Bool) -> BlockedPasteNote {
        if isAccessibilityTrusted {
            if isTextKept { return .readyToPaste }
            return isTextOnClipboard ? .onClipboard : .gone
        }
        if isTextOnClipboard { return .onClipboardNeedsAccess }
        return isTextKept ? .savedNeedsAccess : .gone
    }

    public var message: String {
        switch self {
        // Clicking where to type brings that app forward, so ⌘V lands there; the rows below say what is missing.
        case .onClipboardNeedsAccess, .onClipboard:
            return Self.onClipboardMessage
        case .savedNeedsAccess:
            return String(localized: "The text is ready but couldn't be pasted automatically. Sorla keeps the text for a few minutes and has left your clipboard as it was.", bundle: Localization.bundle)
        case .readyToPaste:
            return String(localized: "Sorla can paste now. Your text is ready.", bundle: Localization.bundle)
        case .gone:
            return String(localized: "The text is no longer kept. Dictate it again.", bundle: Localization.bundle)
        }
    }

    // Only while the text really is on the clipboard (#75).
    public static var onClipboardMessage: String {
        String(localized: "The text is ready but couldn't be pasted automatically. Click where you want to type and press ⌘V.", bundle: Localization.bundle)
    }

    public var offersCopy: Bool { self == .savedNeedsAccess }
    public var offersPaste: Bool { self == .readyToPaste }

    // Paste Last also works once access is there; without a shortcut, or with VoiceOver (#64), the menu item is named instead.
    public static func pasteLastHint(_ route: PasteLastRoute?) -> String {
        switch route {
        case .shortcut(let shortcut):
            return String(localized: "Paste Last Transcription (\(shortcut)) also works now.", bundle: Localization.bundle)
        case .menu:
            return String(localized: "Paste Last Transcription in Sorla's menu (VO-M twice) also works now.", bundle: Localization.bundle)
        case nil:
            return String(localized: "Paste Last Transcription in Sorla's menu also works now.", bundle: Localization.bundle)
        }
    }

    public static var pasteTitle: String { String(localized: "Paste Where You Were Typing", bundle: Localization.bundle) }
    // Says what else the button does, for VoiceOver and Tab; Voice Control still answers to the visible title.
    public static var pasteName: String { String(localized: "Close this window and paste the text where you were typing", bundle: Localization.bundle) }
    public static var copyTitle: String { String(localized: "Copy Text", bundle: Localization.bundle) }
    public static var copyName: String { String(localized: "Copy the text to the clipboard", bundle: Localization.bundle) }

    // Said once when access arrives while the window is open, after the focus has moved to the button.
    public static var readyAnnouncement: String {
        String(localized: "Sorla can paste now: \(pasteTitle).", bundle: Localization.bundle)
    }
}
