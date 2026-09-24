import XCTest
@testable import SorlaCore

@MainActor
final class TriggerMonitorTests: XCTestCase {
    private var starts = 0
    private var finishes = 0
    private var cancels = 0
    private var discards = 0

    private func makeMonitor(mode: RecordingMode) -> TriggerMonitor {
        TriggerMonitor(
            mode: mode,
            onStart: { [unowned self] in
                self.starts += 1
                return true
            },
            onFinish: { [unowned self] in self.finishes += 1 },
            onCancel: { [unowned self] in self.cancels += 1 },
            onDiscard: { [unowned self] in self.discards += 1 }
        )
    }

    func testAKeyStartedDictationStartsOnPressInPushToTalk() {
        let monitor = makeMonitor(mode: .pushToTalk)
        monitor.handle(.triggerDown(at: 0))
        monitor.handle(.triggerUp(at: 1))
        XCTAssertEqual([starts, finishes, cancels], [1, 1, 0])
    }

    func testAMenuStartedDictationIsFinishedOnReleaseNotOnPress() {
        let monitor = makeMonitor(mode: .pushToTalk)
        monitor.recordingDidStartElsewhere()

        monitor.handle(.triggerDown(at: 0))
        XCTAssertEqual([starts, finishes, cancels], [0, 0, 0])
        monitor.handle(.triggerUp(at: 1))
        XCTAssertEqual([starts, finishes, cancels], [0, 1, 0])
    }

    func testAShortcutDoesNotEndAMenuStartedDictation() {
        let monitor = makeMonitor(mode: .pushToTalk)
        monitor.recordingDidStartElsewhere()

        monitor.handle(.triggerDown(at: 0))
        monitor.handle(.otherKeyDown(at: 0.5))
        monitor.handle(.triggerUp(at: 1))

        XCTAssertEqual([starts, finishes, cancels], [0, 0, 0])
    }

    func testAMenuStartedDictationIsCancelledLikeAKeyOneWhenSettingsTakesTheKeys() {
        let monitor = makeMonitor(mode: .toggle)
        monitor.recordingDidStartElsewhere()
        monitor.isSuspended = true
        XCTAssertEqual(cancels, 1)
    }

    // A toggle dictation stopped from the menu or at the limit: the next tap must start, not stop.
    func testAfterADictationEndsElsewhereTheNextTapStartsANewOne() {
        let monitor = makeMonitor(mode: .toggle)
        monitor.handle(.triggerDown(at: 0))
        monitor.handle(.triggerUp(at: 0.1))
        XCTAssertEqual(starts, 1)

        monitor.recordingDidEndElsewhere()
        monitor.handle(.triggerDown(at: 5))
        monitor.handle(.triggerUp(at: 5.1))

        XCTAssertEqual([starts, finishes, cancels], [2, 0, 0])
    }

    func testADictationThatEndedElsewhereIsNotCancelledAgain() {
        let monitor = makeMonitor(mode: .toggle)
        monitor.recordingDidStartElsewhere()
        monitor.recordingDidEndElsewhere()
        monitor.isSuspended = true
        XCTAssertEqual(cancels, 0)
    }

    // MARK: - #20

    func testAStrayClickDuringAKeyboardStartedHoldIsIgnored() {
        let monitor = makeMonitor(mode: .pushToTalk)
        monitor.handle(.triggerDown(at: 0))
        monitor.handle(.click(at: 1))
        monitor.handle(.triggerUp(at: 2))
        XCTAssertEqual([starts, finishes, cancels, discards], [1, 1, 0, 0])
    }

    func testARightCommandShortcutStillDropsAKeyboardStartedHoldQuietly() {
        let monitor = makeMonitor(mode: .pushToTalk)
        monitor.handle(.triggerDown(at: 0))
        monitor.handle(.otherKeyDown(at: 0.1))
        monitor.handle(.triggerUp(at: 0.2))
        XCTAssertEqual([starts, finishes, cancels, discards], [1, 0, 0, 1])
    }

    func testEscapeCancelsAKeyboardStartedHoldOutLoud() {
        let monitor = makeMonitor(mode: .pushToTalk)
        monitor.handle(.triggerDown(at: 0))
        monitor.handle(.escape)
        monitor.handle(.triggerUp(at: 2))
        XCTAssertEqual([starts, finishes, cancels, discards], [1, 0, 1, 0])
    }

    func testEscapeCancelsAKeyboardStartedToggleDictationOutLoud() {
        let monitor = makeMonitor(mode: .toggle)
        monitor.handle(.triggerDown(at: 0))
        monitor.handle(.triggerUp(at: 0.05))
        monitor.handle(.escape)
        XCTAssertEqual([starts, finishes, cancels, discards], [1, 0, 1, 0])
    }

    func testEscapeCancelsAMenuStartedDictation() {
        let monitor = makeMonitor(mode: .pushToTalk)
        monitor.recordingDidStartElsewhere()
        monitor.handle(.click(at: 1))
        monitor.handle(.escape)
        XCTAssertEqual([starts, finishes, cancels, discards], [0, 0, 1, 0])
        monitor.isSuspended = true
        XCTAssertEqual(cancels, 1, "a cancelled dictation isn't cancelled again")
    }

    // Sticky Keys: the latched trigger's release never came, so the next key or click finds the key up and ends the hold.
    func testAKeyAfterAMissedReleaseFinishesInsteadOfCancelling() {
        let monitor = makeMonitor(mode: .pushToTalk)
        monitor.handle(.triggerDown(at: 0))
        monitor.handle(.otherKeyDown(at: 3), isTriggerDown: { false })
        XCTAssertEqual([starts, finishes, cancels, discards], [1, 1, 0, 0])
        monitor.handle(.triggerUp(at: 3.1))
        XCTAssertEqual([starts, finishes, cancels, discards], [1, 1, 0, 0])
    }

    func testAClickAfterAMissedReleaseFinishesTheHold() {
        let monitor = makeMonitor(mode: .pushToTalk)
        monitor.handle(.triggerDown(at: 0))
        monitor.handle(.click(at: 3), isTriggerDown: { false })
        XCTAssertEqual([starts, finishes, cancels, discards], [1, 1, 0, 0])
    }

    func testAMissedReleaseIsNotAssumedWithoutAPressInProgress() {
        let monitor = makeMonitor(mode: .pushToTalk)
        monitor.recordingDidStartElsewhere()
        monitor.handle(.otherKeyDown(at: 1), isTriggerDown: { false })
        monitor.handle(.click(at: 2), isTriggerDown: { false })
        XCTAssertEqual([starts, finishes, cancels, discards], [0, 0, 0, 0])
    }

    func testAShortcutWithTheTriggerHeldStillKeepsAToggleDictationGoing() {
        let monitor = makeMonitor(mode: .toggle)
        monitor.handle(.triggerDown(at: 0))
        monitor.handle(.triggerUp(at: 0.05))
        monitor.handle(.triggerDown(at: 1))
        monitor.handle(.otherKeyDown(at: 1.1), isTriggerDown: { true })
        monitor.handle(.triggerUp(at: 1.2))
        XCTAssertEqual([starts, finishes, cancels, discards], [1, 0, 0, 0])
    }

    func testEscapeWithTheReleaseLostStillLetsTheNextPressStart() {
        let monitor = makeMonitor(mode: .pushToTalk)
        monitor.handle(.triggerDown(at: 0))
        monitor.handle(.escape, isTriggerDown: { false })
        XCTAssertEqual([starts, finishes, cancels, discards], [1, 0, 1, 0], "Esc still cancels rather than finishes")

        monitor.handle(.triggerDown(at: 5))
        XCTAssertEqual(starts, 2)
    }

    func testEscapeWithTheKeyHeldThenALostReleaseIsClearedByTheNextKey() {
        let monitor = makeMonitor(mode: .pushToTalk)
        monitor.handle(.triggerDown(at: 0))
        monitor.handle(.escape)
        monitor.handle(.otherKeyDown(at: 3), isTriggerDown: { false })

        monitor.handle(.triggerDown(at: 5))
        XCTAssertEqual([starts, finishes, cancels, discards], [2, 0, 1, 0])
    }

    func testARightCommandShortcutWithTheReleaseLostLetsTheNextPressStart() {
        let monitor = makeMonitor(mode: .pushToTalk)
        monitor.handle(.triggerDown(at: 0))
        monitor.handle(.otherKeyDown(at: 0.1))
        monitor.handle(.click(at: 2), isTriggerDown: { false })

        monitor.handle(.triggerDown(at: 5))
        XCTAssertEqual([starts, finishes, cancels, discards], [2, 0, 0, 1])
    }

    func testAToggleStartTapWithTheReleaseLostStillStarts() {
        let monitor = makeMonitor(mode: .toggle)
        monitor.handle(.triggerDown(at: 0))
        monitor.handle(.otherKeyDown(at: 1), isTriggerDown: { false })
        XCTAssertEqual([starts, finishes, cancels, discards], [1, 0, 0, 0])

        monitor.handle(.triggerDown(at: 4))
        monitor.handle(.triggerUp(at: 4.1))
        XCTAssertEqual([starts, finishes, cancels, discards], [1, 1, 0, 0])
    }

    func testAToggleStopTapWithTheReleaseLostStillStops() {
        let monitor = makeMonitor(mode: .toggle)
        monitor.handle(.triggerDown(at: 0))
        monitor.handle(.triggerUp(at: 0.05))
        monitor.handle(.triggerDown(at: 2))
        monitor.handle(.click(at: 3), isTriggerDown: { false })
        XCTAssertEqual([starts, finishes, cancels, discards], [1, 1, 0, 0])

        monitor.handle(.triggerDown(at: 5))
        monitor.handle(.triggerUp(at: 5.1))
        XCTAssertEqual(starts, 2, "the next tap starts a new dictation")
    }
}
