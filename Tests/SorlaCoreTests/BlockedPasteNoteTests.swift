import XCTest
@testable import SorlaCore

// #72: what the Set Up Sorla window says about a blocked paste. The clipboard is never involved; the text is only
// Paste Last's, while it keeps it.
final class BlockedPasteNoteTests: XCTestCase {
    func testWhetherTheTextIsKeptDecidesTheNote() {
        XCTAssertEqual(BlockedPasteNote(isTextKept: true), .kept)
        XCTAssertEqual(BlockedPasteNote(isTextKept: false), .notKept)
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

    // Keep last transcription off, the five minutes over or a lock: nothing to paste, whatever the route.
    func testATextThatIsNotKeptIsDictatedAgain() {
        for route in [PasteLastRoute.shortcut("⌃⌥V"), .menu, nil] {
            XCTAssertEqual(
                BlockedPasteNote.notKept.message(pasteLast: route),
                "The text couldn't be saved. Grant the permission and dictate again."
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
