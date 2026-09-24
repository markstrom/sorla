import XCTest
@testable import SorlaCore

final class DictationPhaseTrackerTests: XCTestCase {
    func testSingleDictationGoesRecordingTranscribingIdle() {
        var tracker = DictationPhaseTracker()
        XCTAssertEqual(tracker.phase, .idle)

        let id = tracker.beginRecording()
        XCTAssertEqual(tracker.phase, .recording)

        XCTAssertTrue(tracker.release(id))
        XCTAssertEqual(tracker.phase, .transcribing)

        XCTAssertTrue(tracker.finish(id))
        XCTAssertEqual(tracker.phase, .idle)
    }

    func testCancelGoesStraightToIdle() {
        var tracker = DictationPhaseTracker()
        let id = tracker.beginRecording()

        XCTAssertTrue(tracker.cancel(id))
        XCTAssertEqual(tracker.phase, .idle)
        XCTAssertFalse(tracker.finish(id))
    }

    func testFinishIsIdempotent() {
        var tracker = DictationPhaseTracker()
        let id = tracker.beginRecording()
        tracker.release(id)

        XCTAssertTrue(tracker.finish(id))
        XCTAssertFalse(tracker.finish(id))
        XCTAssertEqual(tracker.phase, .idle)
    }

    func testOlderDictationFinishingDoesNotEndNewerRecording() {
        var tracker = DictationPhaseTracker()
        let older = tracker.beginRecording()
        tracker.release(older)

        let newer = tracker.beginRecording()
        XCTAssertEqual(tracker.phase, .recording)

        XCTAssertFalse(tracker.finish(older))
        XCTAssertEqual(tracker.phase, .recording)

        tracker.release(newer)
        XCTAssertFalse(tracker.finish(older))
        XCTAssertEqual(tracker.phase, .transcribing)

        XCTAssertTrue(tracker.finish(newer))
        XCTAssertEqual(tracker.phase, .idle)
    }

    func testFinishWhileStillRecordingIsIgnored() {
        var tracker = DictationPhaseTracker()
        let id = tracker.beginRecording()

        XCTAssertFalse(tracker.finish(id))
        XCTAssertEqual(tracker.phase, .recording)
    }

    func testStaleCancelAndReleaseAreIgnored() {
        var tracker = DictationPhaseTracker()
        let older = tracker.beginRecording()
        tracker.release(older)
        let newer = tracker.beginRecording()

        XCTAssertFalse(tracker.cancel(older))
        XCTAssertFalse(tracker.release(older))
        XCTAssertEqual(tracker.phase, .recording)
        XCTAssertNotEqual(older, newer)
    }

    func testCancellingANewerRecordingKeepsAnOlderTranscriptionPending() {
        var tracker = DictationPhaseTracker()
        let a = tracker.beginRecording()
        tracker.release(a)
        let b = tracker.beginRecording()
        XCTAssertEqual(tracker.phase, .recording)

        XCTAssertTrue(tracker.cancel(b))
        XCTAssertEqual(tracker.phase, .transcribing)

        XCTAssertTrue(tracker.finish(a))
        XCTAssertEqual(tracker.phase, .idle)
    }

    func testIdleOnlyOnceEveryTranscriptionHasFinished() {
        var tracker = DictationPhaseTracker()
        let a = tracker.beginRecording()
        tracker.release(a)
        let b = tracker.beginRecording()
        tracker.release(b)

        XCTAssertFalse(tracker.finish(a))
        XCTAssertEqual(tracker.phase, .transcribing)
        XCTAssertTrue(tracker.finish(b))
        XCTAssertEqual(tracker.phase, .idle)
    }

    func testAStaleFinishDoesNotEndANewerTranscription() {
        var tracker = DictationPhaseTracker()
        let a = tracker.beginRecording()
        tracker.cancel(a)
        let b = tracker.beginRecording()
        tracker.release(b)

        XCTAssertFalse(tracker.finish(a))
        XCTAssertEqual(tracker.phase, .transcribing)
    }

    func testPasteLastWaitsForAnOlderTranscriptionAfterACancel() {
        var tracker = DictationPhaseTracker()
        let a = tracker.beginRecording()
        tracker.release(a)
        tracker.cancel(tracker.beginRecording())

        XCTAssertFalse(PasteService.shouldPasteLast(hasTranscript: true, phase: tracker.phase, isPasteLastInFlight: false))
        tracker.finish(a)
        XCTAssertTrue(PasteService.shouldPasteLast(hasTranscript: true, phase: tracker.phase, isPasteLastInFlight: false))
    }
}
