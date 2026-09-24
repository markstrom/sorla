import XCTest
@testable import SorlaCore

final class PushToTalkGestureTests: XCTestCase {
    func testHoldAtLeastMinimumStartsThenFinishes() {
        var gesture = PushToTalkGesture(minimumHold: 0.3)

        XCTAssertEqual(gesture.handle(.triggerDown(at: 0)), .start)
        XCTAssertEqual(gesture.handle(.triggerUp(at: 0.5)), .finish)
    }

    func testHoldShorterThanMinimumCancels() {
        var gesture = PushToTalkGesture(minimumHold: 0.3)

        XCTAssertEqual(gesture.handle(.triggerDown(at: 0)), .start)
        XCTAssertEqual(gesture.handle(.triggerUp(at: 0.1)), .cancel)
    }

    func testHoldExactlyMinimumFinishes() {
        var gesture = PushToTalkGesture(minimumHold: 0.3)

        XCTAssertEqual(gesture.handle(.triggerDown(at: 0)), .start)
        XCTAssertEqual(gesture.handle(.triggerUp(at: 0.3)), .finish)
    }

    func testOtherKeyWhileHoldingCancelsThenIgnoresUpUntilNextDown() {
        var gesture = PushToTalkGesture(minimumHold: 0.3)

        XCTAssertEqual(gesture.handle(.triggerDown(at: 0)), .start)
        XCTAssertEqual(gesture.handle(.otherKeyDown), .cancel)
        XCTAssertNil(gesture.handle(.triggerUp(at: 0.5)))
        XCTAssertEqual(gesture.handle(.triggerDown(at: 1)), .start)
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

    func testOtherKeyDownWhileIdleIsIgnored() {
        var gesture = PushToTalkGesture(minimumHold: 0.3)

        XCTAssertNil(gesture.handle(.otherKeyDown))
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
        XCTAssertNil(gesture.handle(.otherKeyDown))
        XCTAssertNil(gesture.handle(.triggerUp(at: 0.5)))

        XCTAssertNil(gesture.handle(.triggerDown(at: 1)))
        XCTAssertEqual(gesture.handle(.triggerUp(at: 1.05)), .start)
    }

    func testOtherKeyDuringHeldStopCandidateSuppressesFinishAndStaysRecording() {
        var gesture = PushToTalkGesture(minimumHold: 0.3, mode: .toggle)

        XCTAssertNil(gesture.handle(.triggerDown(at: 0)))
        XCTAssertEqual(gesture.handle(.triggerUp(at: 0.05)), .start)

        XCTAssertNil(gesture.handle(.triggerDown(at: 1.0)))
        XCTAssertNil(gesture.handle(.otherKeyDown))
        XCTAssertNil(gesture.handle(.triggerUp(at: 1.1)))

        XCTAssertNil(gesture.handle(.triggerDown(at: 2.0)))
        XCTAssertEqual(gesture.handle(.triggerUp(at: 2.05)), .finish)
    }

    func testOtherKeyWhileIdleNotHoldingIsIgnored() {
        var gesture = PushToTalkGesture(minimumHold: 0.3, mode: .toggle)

        XCTAssertNil(gesture.handle(.otherKeyDown))
        XCTAssertNil(gesture.handle(.triggerDown(at: 0)))
        XCTAssertEqual(gesture.handle(.triggerUp(at: 0.05)), .start)
    }

    func testOtherKeyWhileRecordingNotHoldingNeverCancels() {
        var gesture = PushToTalkGesture(minimumHold: 0.3, mode: .toggle)

        XCTAssertNil(gesture.handle(.triggerDown(at: 0)))
        XCTAssertEqual(gesture.handle(.triggerUp(at: 0.05)), .start)

        XCTAssertNil(gesture.handle(.otherKeyDown))

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
            XCTAssertEqual(gesture.handle(.otherKeyDown), nil)
            XCTAssertEqual(gesture.handle(.triggerUp(at: 11)), nil, "\(mode): ⌘Tab or ⌘C must not end it")
            XCTAssertFalse(gesture.isWaitingForRelease)

            XCTAssertEqual(gesture.handle(.triggerDown(at: 12)), nil)
            XCTAssertEqual(gesture.handle(.triggerUp(at: 12.5)), .finish, "\(mode): a later clean press still stops it")
        }
    }

    func testKeysAndClicksWithoutTheTriggerDoNothingToAMenuStartedDictation() {
        var gesture = PushToTalkGesture(minimumHold: 0.3)
        gesture.recordingStartedElsewhere()

        XCTAssertEqual(gesture.handle(.otherKeyDown), nil)
        XCTAssertEqual(gesture.handle(.triggerUp(at: 1)), nil)
        XCTAssertFalse(gesture.isWaitingForRelease)
    }
}
