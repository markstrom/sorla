import XCTest
import AppKit
@testable import SorlaCore

final class ClipboardOwnershipTrackerTests: XCTestCase {
    private func snapshot(_ text: String) -> PasteboardSnapshot {
        PasteboardSnapshot(items: [.init(data: [.string: Data(text.utf8)])])
    }

    func testSingleDictationRestoresTheCapturedOriginal() {
        var tracker = ClipboardOwnershipTracker()
        let original = snapshot("X")

        let begin = tracker.begin(changeCount: 1) { original }
        XCTAssertEqual(begin.original, original)
        XCTAssertEqual(begin.generation, 1)
        tracker.didWrite(changeCount: 2, generation: begin.generation)

        let action = tracker.finish(generation: begin.generation)
        XCTAssertEqual(action, .evaluate(original: original))
    }

    func testOverlappingSecondDictationReusesFirstOriginalAndFirstSkips() {
        var tracker = ClipboardOwnershipTracker()
        let original = snapshot("X")
        let transcript1 = snapshot("transcript-1")
        var captureCount = 0

        let begin1 = tracker.begin(changeCount: 1) {
            captureCount += 1
            return original
        }
        tracker.didWrite(changeCount: 2, generation: begin1.generation)

        let begin2 = tracker.begin(changeCount: 2) {
            captureCount += 1
            return transcript1
        }

        XCTAssertEqual(captureCount, 1, "the second dictation must not re-capture; it should reuse the pending original")
        XCTAssertEqual(begin2.original, original)
        XCTAssertEqual(begin2.generation, begin1.generation + 1)

        let firstAction = tracker.finish(generation: begin1.generation)
        XCTAssertEqual(firstAction, .skip)

        let secondAction = tracker.finish(generation: begin2.generation)
        XCTAssertEqual(secondAction, .evaluate(original: original))
    }

    // #2: X on the clipboard, A pasted, the user copies Y, then B is pasted before A's restore runs.
    func testACopyBetweenOverlappingPastesBecomesTheNewOriginal() {
        var tracker = ClipboardOwnershipTracker()
        let x = snapshot("X")
        let y = snapshot("Y")

        let a = tracker.begin(changeCount: 1) { x }
        tracker.didWrite(changeCount: 2, generation: a.generation)

        let b = tracker.begin(changeCount: 3) { y }
        tracker.didWrite(changeCount: 4, generation: b.generation)

        XCTAssertEqual(b.original, y)
        XCTAssertEqual(tracker.finish(generation: a.generation), .skip)
        XCTAssertEqual(tracker.finish(generation: b.generation), .evaluate(original: y))
    }

    func testAPasteThatNeverRecordedItsWriteIsNotTrustedAsOwner() {
        var tracker = ClipboardOwnershipTracker()
        _ = tracker.begin(changeCount: 1) { self.snapshot("X") }

        let b = tracker.begin(changeCount: 2) { self.snapshot("Y") }
        XCTAssertEqual(b.original, snapshot("Y"))
    }

    func testCancelClearsPendingOriginalSoFinishSkips() {
        var tracker = ClipboardOwnershipTracker()
        let original = snapshot("X")

        let begin = tracker.begin(changeCount: 1) { original }
        tracker.cancel(generation: begin.generation)

        let action = tracker.finish(generation: begin.generation)
        XCTAssertEqual(action, .skip)
    }

    // #2 comment: an older paste that wasn't delivered must not drop the newer paste's pending restore.
    func testCancellingAnOlderGenerationKeepsTheNewerPendingRestore() {
        var tracker = ClipboardOwnershipTracker()
        let x = snapshot("X")

        let a = tracker.begin(changeCount: 1) { x }
        tracker.didWrite(changeCount: 2, generation: a.generation)
        let b = tracker.begin(changeCount: 2) { self.snapshot("A") }
        tracker.didWrite(changeCount: 3, generation: b.generation)

        tracker.cancel(generation: a.generation)
        XCTAssertEqual(tracker.finish(generation: b.generation), .evaluate(original: x))
    }

    // #2 comment: a skipped paste writes its text without owning a generation, so A's restore is still evaluated.
    func testASkippedPasteLeavesThePendingRestoreToTheChangeCountCheck() {
        var tracker = ClipboardOwnershipTracker()
        let x = snapshot("X")

        let a = tracker.begin(changeCount: 1) { x }
        tracker.didWrite(changeCount: 2, generation: a.generation)
        let changeCountAfterSkippedWrite = 3

        XCTAssertEqual(tracker.finish(generation: a.generation), .evaluate(original: x))
        XCTAssertFalse(PasteService.shouldRestoreClipboard(
            keepSetting: true,
            pasteDelivered: true,
            changeCountAfterWrite: 2,
            currentChangeCount: changeCountAfterSkippedWrite
        ), "the skipped transcript stays on the clipboard")
    }

    func testAfterCancelANewDictationCapturesFreshOriginal() {
        var tracker = ClipboardOwnershipTracker()
        let original = snapshot("X")
        let laterOriginal = snapshot("Y")

        let first = tracker.begin(changeCount: 1) { original }
        tracker.didWrite(changeCount: 2, generation: first.generation)
        tracker.cancel(generation: first.generation)

        var captured = false
        let begin = tracker.begin(changeCount: 2) {
            captured = true
            return laterOriginal
        }

        XCTAssertTrue(captured)
        XCTAssertEqual(begin.original, laterOriginal)
    }

    func testFinishWithStaleGenerationSkipsWithoutClearingLaterPending() {
        var tracker = ClipboardOwnershipTracker()
        let original = snapshot("X")

        let begin1 = tracker.begin(changeCount: 1) { original }
        tracker.didWrite(changeCount: 2, generation: begin1.generation)
        let begin2 = tracker.begin(changeCount: 2) { original }

        let staleAction = tracker.finish(generation: begin1.generation)
        XCTAssertEqual(staleAction, .skip)

        let currentAction = tracker.finish(generation: begin2.generation)
        XCTAssertEqual(currentAction, .evaluate(original: original))
    }
}
