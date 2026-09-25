import XCTest
@testable import SorlaCore

// #72: what the Set Up Sorla window says and offers about a blocked paste, as access and the text come and go.
final class BlockedPasteNoteTests: XCTestCase {
    private func note(onClipboard: Bool, kept: Bool, trusted: Bool) -> BlockedPasteNote {
        BlockedPasteNote.current(isTextOnClipboard: onClipboard, isTextKept: kept, isAccessibilityTrusted: trusted)
    }

    // Put back what you had copied on: Sorla has the text, the clipboard doesn't.
    func testGrantingAccessWithTheTextKeptOffersThePasteButton() {
        let before = note(onClipboard: false, kept: true, trusted: false)
        XCTAssertEqual(before, .savedNeedsAccess)
        XCTAssertTrue(before.offersCopy)
        XCTAssertFalse(before.offersPaste)

        let after = note(onClipboard: false, kept: true, trusted: true)
        XCTAssertEqual(after, .readyToPaste)
        XCTAssertTrue(after.offersPaste)
        XCTAssertFalse(after.offersCopy)
    }

    // Setting off: ⌘V while access is missing, then the button once it's there.
    func testWithTheTextOnTheClipboardCommandVUntilAccessThenTheButton() {
        XCTAssertEqual(note(onClipboard: true, kept: true, trusted: false), .onClipboardNeedsAccess)
        XCTAssertFalse(BlockedPasteNote.onClipboardNeedsAccess.offersPaste, "Paste Last needs the missing access too")
        XCTAssertEqual(note(onClipboard: true, kept: true, trusted: true), .readyToPaste)
    }

    // After Copy Text the ⌘V wording is true, so it is used.
    func testCopyingTheTextSwitchesToTheCommandVWording() {
        XCTAssertEqual(note(onClipboard: true, kept: true, trusted: false), .onClipboardNeedsAccess)
    }

    func testAnExpiredTextGetsNoButton() {
        XCTAssertEqual(note(onClipboard: false, kept: false, trusted: true), .gone)
        XCTAssertEqual(note(onClipboard: false, kept: false, trusted: false), .gone)
        XCTAssertEqual(note(onClipboard: true, kept: false, trusted: true), .onClipboard)
        XCTAssertEqual(note(onClipboard: true, kept: false, trusted: false), .onClipboardNeedsAccess)
        for state in [BlockedPasteNote.gone, .onClipboard, .onClipboardNeedsAccess] {
            XCTAssertFalse(state.offersPaste, "\(state)")
            XCTAssertFalse(state.offersCopy, "\(state)")
        }
    }

    // Only a note whose text is on the clipboard mentions ⌘V.
    func testOnlyTheClipboardStatesMentionCommandV() {
        AccessibilityPaneName.$systemMajorVersion.withValue(26) {
            for state in BlockedPasteNote.allCases {
                let mentions = state.message.contains("⌘V")
                XCTAssertEqual(mentions, state == .onClipboard || state == .onClipboardNeedsAccess, "\(state): \(state.message)")
            }
        }
    }

    func testWording() {
        // #75: the same words whenever the text is on the clipboard; the rows below say what access is missing.
        let onClipboard = "The text is ready but couldn't be pasted automatically. Click where you want to type and press ⌘V."
        XCTAssertEqual(BlockedPasteNote.onClipboardNeedsAccess.message, onClipboard)
        XCTAssertEqual(BlockedPasteNote.onClipboard.message, onClipboard)
        XCTAssertEqual(
            BlockedPasteNote.savedNeedsAccess.message,
            "The text is ready but couldn't be pasted automatically. Sorla keeps the text for a few minutes and has left your clipboard as it was."
        )
        XCTAssertEqual(BlockedPasteNote.readyToPaste.message, "Sorla can paste now. Your text is ready.")
        XCTAssertEqual(BlockedPasteNote.gone.message, "The text is no longer kept. Dictate it again.")
        XCTAssertEqual(BlockedPasteNote.pasteTitle, "Paste Where You Were Typing")
        XCTAssertEqual(BlockedPasteNote.pasteName, "Close this window and paste the text where you were typing")
        XCTAssertNotEqual(BlockedPasteNote.pasteName, BlockedPasteNote.pasteTitle)
        XCTAssertEqual(BlockedPasteNote.copyTitle, "Copy Text")
        XCTAssertEqual(BlockedPasteNote.copyName, "Copy the text to the clipboard")
        XCTAssertEqual(BlockedPasteNote.pasteLastHint(.shortcut("⌃⌥V")), "Paste Last Transcription (⌃⌥V) also works now.")
        XCTAssertEqual(BlockedPasteNote.pasteLastHint(nil), "Paste Last Transcription in Sorla's menu also works now.")
        XCTAssertEqual(BlockedPasteNote.readyAnnouncement, "Sorla can paste now: Paste Where You Were Typing.")
    }
}
