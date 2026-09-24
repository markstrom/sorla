import XCTest
@testable import SorlaCore

final class PushToTalkGestureTests: XCTestCase {
    func testHoldAtLeastMinimumStartsThenFinishes() {
        var gesture = PushToTalkGesture(minimumHold: 0.3)

        XCTAssertEqual(gesture.handle(.triggerDown(at: 0)), .start)
        XCTAssertEqual(gesture.handle(.triggerUp(at: 0.5)), .finish)
    }

    func testHoldShorterThanMinimumIsDiscardedQuietly() {
        var gesture = PushToTalkGesture(minimumHold: 0.3)

        XCTAssertEqual(gesture.handle(.triggerDown(at: 0)), .start)
        XCTAssertEqual(gesture.handle(.triggerUp(at: 0.1)), .discard)
    }

    func testHoldExactlyMinimumFinishes() {
        var gesture = PushToTalkGesture(minimumHold: 0.3)

        XCTAssertEqual(gesture.handle(.triggerDown(at: 0)), .start)
        XCTAssertEqual(gesture.handle(.triggerUp(at: 0.3)), .finish)
    }

    // A ⌘-shortcut made with the trigger (Right ⌘ + C) drops the press without a word.
    func testAShortcutWithTheTriggerDiscardsThenIgnoresUpUntilNextDown() {
        var gesture = PushToTalkGesture(minimumHold: 0.3)

        XCTAssertEqual(gesture.handle(.triggerDown(at: 0)), .start)
        XCTAssertEqual(gesture.handle(.otherKeyDown(at: 0.1)), .discard)
        XCTAssertNil(gesture.handle(.triggerUp(at: 0.5)))
        XCTAssertEqual(gesture.handle(.triggerDown(at: 1)), .start)
    }

    // Past the minimum hold the dictation was audible, so a key still cancels it but Sorla says so.
    func testAKeyAfterTheMinimumHoldStillCancelsButOutLoud() {
        var gesture = PushToTalkGesture(minimumHold: 0.3)

        XCTAssertEqual(gesture.handle(.triggerDown(at: 0)), .start)
        XCTAssertEqual(gesture.handle(.otherKeyDown(at: 2)), .cancel)
        XCTAssertNil(gesture.handle(.triggerUp(at: 2.5)))
    }

    // #20: a stray click, or the click that opens the menu, no longer throws the dictation away.
    func testAClickAfterTheMinimumHoldIsIgnored() {
        var gesture = PushToTalkGesture(minimumHold: 0.3)

        XCTAssertEqual(gesture.handle(.triggerDown(at: 0)), .start)
        XCTAssertNil(gesture.handle(.click(at: 0.3)))
        XCTAssertNil(gesture.handle(.click(at: 1)))
        XCTAssertEqual(gesture.handle(.triggerUp(at: 2)), .finish)
    }

    // Within the minimum hold a click with the trigger down is a ⌘-click.
    func testAClickWithinTheMinimumHoldIsAShortcutClick() {
        var gesture = PushToTalkGesture(minimumHold: 0.3)

        XCTAssertEqual(gesture.handle(.triggerDown(at: 0)), .start)
        XCTAssertEqual(gesture.handle(.click(at: 0.1)), .discard)
        XCTAssertNil(gesture.handle(.triggerUp(at: 0.5)))
    }

    func testEscapeCancelsAHeldDictationAndWaitsForTheRelease() {
        var gesture = PushToTalkGesture(minimumHold: 0.3)

        XCTAssertEqual(gesture.handle(.triggerDown(at: 0)), .start)
        XCTAssertEqual(gesture.handle(.escape), .cancel)
        XCTAssertTrue(gesture.isWaitingForRelease)
        XCTAssertNil(gesture.handle(.escape))
        XCTAssertNil(gesture.handle(.triggerUp(at: 1)))
        XCTAssertEqual(gesture.handle(.triggerDown(at: 2)), .start)
    }

    func testEscapeWhileIdleDoesNothing() {
        var gesture = PushToTalkGesture(minimumHold: 0.3)

        XCTAssertNil(gesture.handle(.escape))
        XCTAssertEqual(gesture.handle(.triggerDown(at: 0)), .start)
    }

    func testDuplicateTriggerDownWhileHoldingIsIgnored() {
        var gesture = PushToTalkGesture(minimumHold: 0.3)

        XCTAssertEqual(gesture.handle(.triggerDown(at: 0)), .start)
        XCTAssertNil(gesture.handle(.triggerDown(at: 0.1)))
    }

    func testTriggerUpWhileIdleIsIgnored() {
        var gesture = PushToTalkGesture(minimumHold: 0.3)

        XCTAssertNil(gesture.handle(.triggerUp(at: 0)))
    }

    func testOtherKeyDownOrClickWhileIdleIsIgnored() {
        var gesture = PushToTalkGesture(minimumHold: 0.3)

        XCTAssertNil(gesture.handle(.otherKeyDown(at: 0)))
        XCTAssertNil(gesture.handle(.click(at: 0)))
    }

    func testResetWhileHoldingReturnsToIdle() {
        var gesture = PushToTalkGesture(minimumHold: 0.3)

        XCTAssertEqual(gesture.handle(.triggerDown(at: 0)), .start)
        gesture.reset()

        XCTAssertEqual(gesture.handle(.triggerDown(at: 1)), .start)
    }
}

final class PushToTalkGestureToggleModeTests: XCTestCase {
    func testCleanTapWhileIdleStarts() {
        var gesture = PushToTalkGesture(minimumHold: 0.3, mode: .toggle)

        XCTAssertNil(gesture.handle(.triggerDown(at: 0)))
        XCTAssertEqual(gesture.handle(.triggerUp(at: 0.05)), .start)
    }

    func testCleanTapWhileRecordingAfterMinimumHoldFinishes() {
        var gesture = PushToTalkGesture(minimumHold: 0.3, mode: .toggle)

        XCTAssertNil(gesture.handle(.triggerDown(at: 0)))
        XCTAssertEqual(gesture.handle(.triggerUp(at: 0.05)), .start)

        XCTAssertNil(gesture.handle(.triggerDown(at: 1.0)))
        XCTAssertEqual(gesture.handle(.triggerUp(at: 1.05)), .finish)
    }

    func testCleanTapWithinMinimumHoldCancels() {
        var gesture = PushToTalkGesture(minimumHold: 0.3, mode: .toggle)

        XCTAssertNil(gesture.handle(.triggerDown(at: 0)))
        XCTAssertEqual(gesture.handle(.triggerUp(at: 0.05)), .start)

        XCTAssertNil(gesture.handle(.triggerDown(at: 0.1)))
        XCTAssertEqual(gesture.handle(.triggerUp(at: 0.2)), .cancel)
    }

    func testCleanTapAtExactlyMinimumHoldFinishes() {
        var gesture = PushToTalkGesture(minimumHold: 0.3, mode: .toggle)

        XCTAssertNil(gesture.handle(.triggerDown(at: 0)))
        XCTAssertEqual(gesture.handle(.triggerUp(at: 0)), .start)

        XCTAssertNil(gesture.handle(.triggerDown(at: 0)))
        XCTAssertEqual(gesture.handle(.triggerUp(at: 0.3)), .finish)
    }

    func testOtherKeyDuringHeldStartCandidateSuppressesStart() {
        var gesture = PushToTalkGesture(minimumHold: 0.3, mode: .toggle)

        XCTAssertNil(gesture.handle(.triggerDown(at: 0)))
        XCTAssertNil(gesture.handle(.otherKeyDown(at: 1.05)))
        XCTAssertNil(gesture.handle(.triggerUp(at: 0.5)))

        XCTAssertNil(gesture.handle(.triggerDown(at: 1)))
        XCTAssertEqual(gesture.handle(.triggerUp(at: 1.05)), .start)
    }

    func testOtherKeyDuringHeldStopCandidateSuppressesFinishAndStaysRecording() {
        var gesture = PushToTalkGesture(minimumHold: 0.3, mode: .toggle)

        XCTAssertNil(gesture.handle(.triggerDown(at: 0)))
        XCTAssertEqual(gesture.handle(.triggerUp(at: 0.05)), .start)

        XCTAssertNil(gesture.handle(.triggerDown(at: 1.0)))
        XCTAssertNil(gesture.handle(.otherKeyDown(at: 1.05)))
        XCTAssertNil(gesture.handle(.triggerUp(at: 1.1)))

        XCTAssertNil(gesture.handle(.triggerDown(at: 2.0)))
        XCTAssertEqual(gesture.handle(.triggerUp(at: 2.05)), .finish)
    }

    func testOtherKeyWhileIdleNotHoldingIsIgnored() {
        var gesture = PushToTalkGesture(minimumHold: 0.3, mode: .toggle)

        XCTAssertNil(gesture.handle(.otherKeyDown(at: 1.05)))
        XCTAssertNil(gesture.handle(.triggerDown(at: 0)))
        XCTAssertEqual(gesture.handle(.triggerUp(at: 0.05)), .start)
    }

    func testOtherKeyWhileRecordingNotHoldingNeverCancels() {
        var gesture = PushToTalkGesture(minimumHold: 0.3, mode: .toggle)

        XCTAssertNil(gesture.handle(.triggerDown(at: 0)))
        XCTAssertEqual(gesture.handle(.triggerUp(at: 0.05)), .start)

        XCTAssertNil(gesture.handle(.otherKeyDown(at: 1.05)))

        XCTAssertNil(gesture.handle(.triggerDown(at: 1.0)))
        XCTAssertEqual(gesture.handle(.triggerUp(at: 1.05)), .finish)
    }

    func testResetWhileRecordingReturnsToIdleSoNextTapStartsAgain() {
        var gesture = PushToTalkGesture(minimumHold: 0.3, mode: .toggle)

        XCTAssertNil(gesture.handle(.triggerDown(at: 0)))
        XCTAssertEqual(gesture.handle(.triggerUp(at: 0.05)), .start)

        gesture.reset()

        XCTAssertNil(gesture.handle(.triggerDown(at: 1)))
        XCTAssertEqual(gesture.handle(.triggerUp(at: 1.05)), .start)
    }

    // A dictation started from the menu: the key stops it on a clean release, in both modes.
    func testAMenuStartedDictationFinishesOnACleanReleaseNotOnPress() {
        for mode in [RecordingMode.pushToTalk, .toggle] {
            var gesture = PushToTalkGesture(minimumHold: 0.3, mode: mode)
            gesture.recordingStartedElsewhere()

            XCTAssertEqual(gesture.handle(.triggerDown(at: 10)), nil, "\(mode)")
            XCTAssertTrue(gesture.isWaitingForRelease)
            XCTAssertEqual(gesture.handle(.triggerUp(at: 10.05)), .finish, "\(mode)")
            XCTAssertEqual(gesture.handle(.triggerDown(at: 20)), mode == .pushToTalk ? .start : nil, "\(mode): next press is a new dictation")
        }
    }

    func testAShortcutDuringAMenuStartedDictationNeitherFinishesNorCancelsIt() {
        for mode in [RecordingMode.pushToTalk, .toggle] {
            var gesture = PushToTalkGesture(minimumHold: 0.3, mode: mode)
            gesture.recordingStartedElsewhere()

            XCTAssertEqual(gesture.handle(.triggerDown(at: 10)), nil)
            XCTAssertEqual(gesture.handle(.otherKeyDown(at: 1.05)), nil)
            XCTAssertEqual(gesture.handle(.triggerUp(at: 11)), nil, "\(mode): ⌘Tab or ⌘C must not end it")
            XCTAssertFalse(gesture.isWaitingForRelease)

            XCTAssertEqual(gesture.handle(.triggerDown(at: 12)), nil)
            XCTAssertEqual(gesture.handle(.triggerUp(at: 12.5)), .finish, "\(mode): a later clean press still stops it")
        }
    }

    func testKeysAndClicksWithoutTheTriggerDoNothingToAMenuStartedDictation() {
        var gesture = PushToTalkGesture(minimumHold: 0.3)
        gesture.recordingStartedElsewhere()

        XCTAssertEqual(gesture.handle(.otherKeyDown(at: 1.05)), nil)
        XCTAssertEqual(gesture.handle(.triggerUp(at: 1)), nil)
        XCTAssertFalse(gesture.isWaitingForRelease)
    }

    // MARK: - #20: Esc, clicks and feedback, keyboard-started against menu-started

    func testEscapeCancelsAToggleDictationOutLoud() {
        var gesture = PushToTalkGesture(minimumHold: 0.3, mode: .toggle)

        XCTAssertNil(gesture.handle(.triggerDown(at: 0)))
        XCTAssertEqual(gesture.handle(.triggerUp(at: 0.05)), .start)
        XCTAssertEqual(gesture.handle(.escape), .cancel)
        XCTAssertFalse(gesture.isWaitingForRelease)

        XCTAssertNil(gesture.handle(.triggerDown(at: 1)))
        XCTAssertEqual(gesture.handle(.triggerUp(at: 1.05)), .start, "the next tap starts a new dictation")
    }

    func testEscapeWhileHoldingTheStopTapCancelsAndSwallowsTheRelease() {
        var gesture = PushToTalkGesture(minimumHold: 0.3, mode: .toggle)

        XCTAssertNil(gesture.handle(.triggerDown(at: 0)))
        XCTAssertEqual(gesture.handle(.triggerUp(at: 0.05)), .start)
        XCTAssertNil(gesture.handle(.triggerDown(at: 1)))
        XCTAssertEqual(gesture.handle(.escape), .cancel)
        XCTAssertNil(gesture.handle(.triggerUp(at: 1.1)), "the release must not start a new dictation")
        XCTAssertNil(gesture.handle(.triggerDown(at: 2)))
        XCTAssertEqual(gesture.handle(.triggerUp(at: 2.05)), .start)
    }

    func testEscapeBeforeAToggleDictationStartsOnlySpoilsTheTap() {
        var gesture = PushToTalkGesture(minimumHold: 0.3, mode: .toggle)

        XCTAssertNil(gesture.handle(.triggerDown(at: 0)))
        XCTAssertNil(gesture.handle(.escape))
        XCTAssertNil(gesture.handle(.triggerUp(at: 0.05)))
    }

    func testClicksDuringAToggleDictationNeverStopIt() {
        var gesture = PushToTalkGesture(minimumHold: 0.3, mode: .toggle)

        XCTAssertNil(gesture.handle(.triggerDown(at: 0)))
        XCTAssertEqual(gesture.handle(.triggerUp(at: 0.05)), .start)
        XCTAssertNil(gesture.handle(.click(at: 1)))
        XCTAssertNil(gesture.handle(.triggerDown(at: 2)))
        XCTAssertNil(gesture.handle(.click(at: 2.1)), "a ⌘-click is not a stop tap")
        XCTAssertNil(gesture.handle(.triggerUp(at: 2.2)))
        XCTAssertNil(gesture.handle(.triggerDown(at: 3)))
        XCTAssertEqual(gesture.handle(.triggerUp(at: 3.05)), .finish)
    }

    func testEscapeCancelsAMenuStartedDictationInBothModes() {
        for mode in [RecordingMode.pushToTalk, .toggle] {
            var gesture = PushToTalkGesture(minimumHold: 0.3, mode: mode)
            gesture.recordingStartedElsewhere()

            XCTAssertEqual(gesture.handle(.escape), .cancel, "\(mode)")
            XCTAssertNil(gesture.handle(.escape), "\(mode): nothing left to cancel")
        }
    }

    func testEscapeWithTheKeyDownCancelsAMenuStartedDictationAndSwallowsTheRelease() {
        for mode in [RecordingMode.pushToTalk, .toggle] {
            var gesture = PushToTalkGesture(minimumHold: 0.3, mode: mode)
            gesture.recordingStartedElsewhere()

            XCTAssertNil(gesture.handle(.triggerDown(at: 1)))
            XCTAssertEqual(gesture.handle(.escape), .cancel, "\(mode)")
            XCTAssertNil(gesture.handle(.triggerUp(at: 2)), "\(mode)")
        }
    }

    func testClicksNeverEndAMenuStartedDictation() {
        for mode in [RecordingMode.pushToTalk, .toggle] {
            var gesture = PushToTalkGesture(minimumHold: 0.3, mode: mode)
            gesture.recordingStartedElsewhere()

            XCTAssertNil(gesture.handle(.click(at: 1)), "\(mode)")
            XCTAssertNil(gesture.handle(.triggerDown(at: 2)))
            XCTAssertNil(gesture.handle(.click(at: 2.1)), "\(mode): a ⌘-click")
            XCTAssertNil(gesture.handle(.triggerUp(at: 2.2)), "\(mode)")
        }
    }
}
