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

        let begin = tracker.begin { original }
        XCTAssertEqual(begin.original, original)
        XCTAssertEqual(begin.generation, 1)

        let action = tracker.finish(generation: begin.generation)
        XCTAssertEqual(action, .evaluate(original: original))
    }

    func testOverlappingSecondDictationReusesFirstOriginalAndFirstSkips() {
        var tracker = ClipboardOwnershipTracker()
        let original = snapshot("X")
        let transcript1 = snapshot("transcript-1")
        var captureCount = 0

        let begin1 = tracker.begin {
            captureCount += 1
            return original
        }

        let begin2 = tracker.begin {
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

    func testCancelClearsPendingOriginalSoFinishSkips() {
        var tracker = ClipboardOwnershipTracker()
        let original = snapshot("X")

        let begin = tracker.begin { original }
        tracker.cancel()

        let action = tracker.finish(generation: begin.generation)
        XCTAssertEqual(action, .skip)
    }

    func testAfterCancelANewDictationCapturesFreshOriginal() {
        var tracker = ClipboardOwnershipTracker()
        let original = snapshot("X")
        let laterOriginal = snapshot("Y")

        _ = tracker.begin { original }
        tracker.cancel()

        var captured = false
        let begin = tracker.begin {
            captured = true
            return laterOriginal
        }

        XCTAssertTrue(captured)
        XCTAssertEqual(begin.original, laterOriginal)
    }

    func testFinishWithStaleGenerationSkipsWithoutClearingLaterPending() {
        var tracker = ClipboardOwnershipTracker()
        let original = snapshot("X")

        let begin1 = tracker.begin { original }
        let begin2 = tracker.begin { original }

        let staleAction = tracker.finish(generation: begin1.generation)
        XCTAssertEqual(staleAction, .skip)

        let currentAction = tracker.finish(generation: begin2.generation)
        XCTAssertEqual(currentAction, .evaluate(original: original))
    }
}
