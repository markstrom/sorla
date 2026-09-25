import XCTest
@testable import SorlaCore

// #64: ⌃⌥V is VoiceOver's VO-V, so with VoiceOver running Sorla's messages name the menu item and how to reach it.
final class PasteLastRouteTests: XCTestCase {
    private let keys = PasteLastRoute.current(shortcut: "⌃⌥V", isVoiceOverRunning: false)
    private let voiceOver = PasteLastRoute.current(shortcut: "⌃⌥V", isVoiceOverRunning: true)

    func testVoiceOverChoosesTheMenuItem() {
        XCTAssertEqual(keys, .shortcut("⌃⌥V"))
        XCTAssertEqual(voiceOver, .menu)
        XCTAssertEqual(PasteLastRoute.current(shortcut: nil, isVoiceOverRunning: true), .menu)
    }

    // Nothing to name: the text on the clipboard pastes with ⌘V, as before.
    func testWithoutAShortcutOrVoiceOverNothingIsNamed() {
        XCTAssertNil(PasteLastRoute.current(shortcut: nil, isVoiceOverRunning: false))
        XCTAssertNil(PasteLastRoute.current(shortcut: "", isVoiceOverRunning: false))
    }

    func testTheKeysSetApartInAWindow() {
        XCTAssertEqual(PasteLastRoute.shortcut("⌃⌥V").keys, "⌃⌥V")
        XCTAssertEqual(PasteLastRoute.menu.keys, "VO-M")
    }

    func testTheClipboardCue() {
        XCTAssertEqual(DictationCue.textOnClipboard.announcement(pasteLast: keys), "Your text is on the clipboard — press ⌃⌥V")
        XCTAssertEqual(
            DictationCue.textOnClipboard.announcement(pasteLast: voiceOver),
            "Your text is on the clipboard — choose Paste Last Transcription in Sorla's menu (VO-M twice)"
        )
        XCTAssertEqual(DictationCue.textOnClipboard.announcement(pasteLast: nil), "Your text is on the clipboard — press ⌘V")
        XCTAssertEqual(DictationCue.textOnClipboard.issue(pasteLast: voiceOver), .textOnClipboard(pasteLast: .menu))
    }

    func testTheReleaseKeysCue() {
        XCTAssertEqual(DictationCue.releaseKeys.announcement(pasteLast: keys), "Let go of the keys and press ⌃⌥V again")
        XCTAssertEqual(
            DictationCue.releaseKeys.announcement(pasteLast: voiceOver),
            "Let go of the keys and choose Paste Last Transcription in Sorla's menu (VO-M twice)"
        )
    }

    // It names no way to paste, so VoiceOver changes nothing.
    func testNothingToPasteIsTheSameWithVoiceOver() {
        XCTAssertEqual(DictationCue.nothingToPaste.announcement(pasteLast: voiceOver), "Nothing to paste")
        XCTAssertEqual(DictationCue.nothingToPaste.announcement(pasteLast: keys), "Nothing to paste")
        XCTAssertNil(DictationCue.nothingToPaste.issue(pasteLast: voiceOver))
    }

    // The menu's status row is already in the menu, so it needs no VO-M.
    func testTheMenuRow() {
        XCTAssertEqual(SorlaIssue.textOnClipboard(pasteLast: keys).menuTitle, "Text is on the clipboard — press ⌃⌥V")
        XCTAssertEqual(SorlaIssue.textOnClipboard(pasteLast: voiceOver).menuTitle, "Text is on the clipboard — choose Paste Last Transcription")
    }

    func testTheSetupWindowsNote() {
        XCTAssertEqual(BlockedPasteNote.pasteLastHint(keys), "Paste Last Transcription (⌃⌥V) also works now.")
        XCTAssertEqual(BlockedPasteNote.pasteLastHint(voiceOver), "Paste Last Transcription in Sorla's menu (VO-M twice) also works now.")
        XCTAssertEqual(BlockedPasteNote.pasteLastHint(nil), "Paste Last Transcription in Sorla's menu also works now.")
    }

    // Where Paste Last can't help (a blocked paste, a replaced app) the caller names no route, so ⌘V stays.
    func testABlockedPasteStillSaysCommandVWithVoiceOver() {
        XCTAssertEqual(DictationCue.textOnClipboardUntilRestart.announcement(pasteLast: nil), "Your text is on the clipboard — press ⌘V. Restart Sorla to paste again")
    }
}
