import XCTest
@testable import SorlaCore

// #72: what the Set Up Sorla window says about a blocked paste. The clipboard is never involved; the text is only
// Paste Last's, while it keeps it.
final class BlockedPasteNoteTests: XCTestCase {
    func testWhetherTheTextWasSavedAndIsStillKeptDecidesTheNote() {
        XCTAssertEqual(BlockedPasteNote(wasSaved: true, isTextKept: true), .kept)
        XCTAssertEqual(BlockedPasteNote(wasSaved: true, isTextKept: false), .noLongerKept)
        XCTAssertEqual(BlockedPasteNote(wasSaved: false, isTextKept: false), .notSaved)
        // A later text Paste Last has isn't the one that was blocked.
        XCTAssertEqual(BlockedPasteNote(wasSaved: false, isTextKept: true), .notSaved)
    }

    func testAKeptTextIsPastedWithPasteLast() {
        XCTAssertEqual(
            BlockedPasteNote.kept.message(pasteLast: .shortcut("⌃⌥V")),
            "The text is saved. Grant the permission, click where you want to type and choose Paste Last Transcription (⌃⌥V). A test dictation in Try it here replaces the saved text."
        )
        XCTAssertEqual(
            BlockedPasteNote.kept.message(pasteLast: nil),
            "The text is saved. Grant the permission, click where you want to type and choose Paste Last Transcription in Sorla's menu. A test dictation in Try it here replaces the saved text."
        )
    }

    // #64: VoiceOver may take ⌃⌥V for itself, so the menu item and how to reach it are named instead.
    func testWithVoiceOverTheMenuItemIsNamed() {
        XCTAssertEqual(
            BlockedPasteNote.kept.message(pasteLast: .menu),
            "The text is saved. Grant the permission, click where you want to type and choose Paste Last Transcription in Sorla's menu (VO-M twice). A test dictation in Try it here replaces the saved text."
        )
    }

    // Keep last transcription off: nothing to paste, whatever the route.
    func testATextThatWasNotSavedIsDictatedAgain() {
        for route in [PasteLastRoute.shortcut("⌃⌥V"), .menu, nil] {
            XCTAssertEqual(
                BlockedPasteNote.notSaved.message(pasteLast: route),
                "The text couldn't be saved. Grant the permission and dictate again."
            )
        }
    }

    // The five minutes over, a lock or the setting turned off: it was saved, so the note doesn't say it couldn't be.
    func testATextThatIsNoLongerKeptIsDictatedAgain() {
        for route in [PasteLastRoute.shortcut("⌃⌥V"), .menu, nil] {
            XCTAssertEqual(
                BlockedPasteNote.noLongerKept.message(pasteLast: route),
                "The text is no longer saved. Grant the permission and dictate again."
            )
        }
    }

    // The text was never put on the clipboard, so no note sends the user to ⌘V.
    func testNoNoteMentionsTheClipboard() {
        for note in BlockedPasteNote.allCases {
            for route in [PasteLastRoute.shortcut("⌃⌥V"), .menu, nil] {
                let message = note.message(pasteLast: route)
                XCTAssertFalse(message.contains("⌘V"), message)
                XCTAssertFalse(message.contains("clipboard"), message)
            }
        }
    }
}
