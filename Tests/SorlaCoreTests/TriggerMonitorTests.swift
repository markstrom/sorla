import XCTest
@testable import SorlaCore

@MainActor
final class TriggerMonitorTests: XCTestCase {
    private var starts = 0
    private var finishes = 0
    private var cancels = 0
    private var discards = 0
    private var startSucceeds = true
    private var keyWatches: [TriggerKey] = []
    private var keyWatchRemovals = 0
    private var isWatchingKeys: Bool { keyWatches.count > keyWatchRemovals }

    private func makeMonitor(trigger: TriggerKey = .rightCommand, mode: RecordingMode) -> TriggerMonitor {
        TriggerMonitor(
            trigger: trigger,
            mode: mode,
            installKeyWatch: { [unowned self] trigger, _ in
                self.keyWatches.append(trigger)
                return { [unowned self] in self.keyWatchRemovals += 1 }
            },
            onStart: { [unowned self] in
                self.starts += 1
                return self.startSucceeds
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

    func testAStaleUpDuringARealFnHoldDoesNotFinishTheRecording() {
        let monitor = makeMonitor(trigger: .fn, mode: .pushToTalk)
        monitor.handle(.triggerDown(at: 0))
        monitor.handle(.click(at: 3), isTriggerDown: { false })
        monitor.handle(.escape, isTriggerDown: { false })
        XCTAssertEqual([starts, finishes, cancels, discards], [1, 0, 1, 0], "the click is ignored and Esc still cancels")

        let toggle = makeMonitor(trigger: .fn, mode: .toggle)
        toggle.handle(.triggerDown(at: 10))
        toggle.handle(.triggerUp(at: 10.05))
        toggle.handle(.triggerDown(at: 12))
        toggle.handle(.click(at: 13), isTriggerDown: { false })
        XCTAssertEqual([starts, finishes], [2, 0])
        toggle.handle(.triggerUp(at: 14))
        XCTAssertEqual([starts, finishes], [2, 0], "a ⌘-click-like press is not a stop tap")
    }

    // MARK: - Keys are only watched while a press or a recording is under way

    func testKeysAreWatchedOnlyWhileAPushToTalkPressLasts() {
        let monitor = makeMonitor(mode: .pushToTalk)
        XCTAssertFalse(isWatchingKeys)
        monitor.handle(.triggerDown(at: 0))
        XCTAssertTrue(isWatchingKeys)
        monitor.handle(.triggerUp(at: 1))
        XCTAssertFalse(isWatchingKeys)
        XCTAssertEqual([keyWatches.count, keyWatchRemovals], [1, 1])
    }

    func testAToggleDictationIsWatchedFromTheTapUntilItEnds() {
        let monitor = makeMonitor(mode: .toggle)
        monitor.handle(.triggerDown(at: 0))
        XCTAssertTrue(isWatchingKeys, "a ⌘-shortcut during the tap must spoil it")
        monitor.handle(.triggerUp(at: 0.05))
        XCTAssertTrue(isWatchingKeys, "Esc must reach the recording")
        monitor.handle(.escape)
        XCTAssertFalse(isWatchingKeys)
        XCTAssertEqual(keyWatches.count, 1, "one watch for the whole dictation")
    }

    func testACustomShortcutWatchesForEscOnlyWhileRecording() {
        let toggle = makeMonitor(trigger: .customShortcut, mode: .toggle)
        toggle.handle(.triggerDown(at: 0))
        XCTAssertFalse(isWatchingKeys, "no recording yet")
        toggle.handle(.triggerUp(at: 0.05))
        XCTAssertTrue(isWatchingKeys)
        toggle.handle(.triggerDown(at: 2))
        toggle.handle(.triggerUp(at: 2.05))
        XCTAssertFalse(isWatchingKeys)

        let pushToTalk = makeMonitor(trigger: .customShortcut, mode: .pushToTalk)
        pushToTalk.handle(.triggerDown(at: 5))
        XCTAssertTrue(isWatchingKeys)
        pushToTalk.handle(.escape)
        XCTAssertFalse(isWatchingKeys, "cancelled, even though the shortcut is still held")
        XCTAssertEqual(keyWatches, [.customShortcut, .customShortcut])
    }

    func testAMenuStartedDictationIsWatchedUntilItEndsOrSettingsTakesTheKeys() {
        let monitor = makeMonitor(mode: .pushToTalk)
        monitor.recordingDidStartElsewhere()
        XCTAssertTrue(isWatchingKeys)
        monitor.recordingDidEndElsewhere()
        XCTAssertFalse(isWatchingKeys)

        monitor.recordingDidStartElsewhere()
        monitor.isSuspended = true
        XCTAssertFalse(isWatchingKeys)
    }

    // MARK: - Settings gives the keys back (#14)

    func testAfterSettingsLetsGoTheNextPressStartsAFreshDictation() {
        let pushToTalk = makeMonitor(mode: .pushToTalk)
        pushToTalk.handle(.triggerDown(at: 0))
        pushToTalk.isSuspended = true
        pushToTalk.isSuspended = false
        pushToTalk.handle(.triggerDown(at: 5))
        pushToTalk.handle(.triggerUp(at: 6))
        XCTAssertEqual([starts, finishes, cancels], [2, 1, 1])

        // Without the reset, the first tap after Settings would stop a dictation that no longer exists.
        let toggle = makeMonitor(mode: .toggle)
        toggle.handle(.triggerDown(at: 10))
        toggle.handle(.triggerUp(at: 10.05))
        toggle.isSuspended = true
        toggle.isSuspended = false
        toggle.handle(.triggerDown(at: 15))
        toggle.handle(.triggerUp(at: 15.05))
        XCTAssertEqual([starts, finishes, cancels], [4, 1, 2])
        XCTAssertTrue(isWatchingKeys, "Esc must reach the new recording")
    }

    // Start Dictation from the menu while Settings is key hands focus back to the previous app, which resumes the monitor.
    func testAMenuStartedDictationBegunWhileSettingsIsKeyIsWatchedOnceSettingsLetsGo() {
        for trigger in [TriggerKey.rightCommand, .customShortcut] {
            keyWatches = []
            keyWatchRemovals = 0
            let monitor = makeMonitor(trigger: trigger, mode: .pushToTalk)
            monitor.isSuspended = true
            monitor.recordingDidStartElsewhere()
            XCTAssertFalse(isWatchingKeys, "\(trigger)")

            monitor.isSuspended = false
            XCTAssertTrue(isWatchingKeys, "\(trigger): Esc must reach the recording")
        }
        XCTAssertEqual(cancels, 0)
    }

    func testAPressThatCouldNotStartStopsWatching() {
        startSucceeds = false
        let monitor = makeMonitor(mode: .pushToTalk)
        monitor.handle(.triggerDown(at: 0))
        XCTAssertEqual(keyWatches.count, 1, "watched before the microphone starts")
        XCTAssertFalse(isWatchingKeys)
    }

    func testKeysAreWatchedUntilALostReleaseIsCleared() {
        let monitor = makeMonitor(mode: .pushToTalk)
        monitor.handle(.triggerDown(at: 0))
        monitor.handle(.otherKeyDown(at: 0.1))
        XCTAssertTrue(isWatchingKeys, "a key with the trigger up must still clear the cancelled press")
        monitor.handle(.click(at: 2), isTriggerDown: { false })
        XCTAssertFalse(isWatchingKeys)
    }

    func testTheWatchRule() {
        XCTAssertFalse(TriggerEdge.watchesKeys(trigger: .rightCommand, isRecordingActive: false, isWaitingForRelease: false))
        XCTAssertTrue(TriggerEdge.watchesKeys(trigger: .rightCommand, isRecordingActive: false, isWaitingForRelease: true))
        XCTAssertTrue(TriggerEdge.watchesKeys(trigger: .fn, isRecordingActive: true, isWaitingForRelease: false))
        XCTAssertFalse(TriggerEdge.watchesKeys(trigger: .customShortcut, isRecordingActive: false, isWaitingForRelease: true))
        XCTAssertTrue(TriggerEdge.watchesKeys(trigger: .customShortcut, isRecordingActive: true, isWaitingForRelease: false))
    }
}
