import XCTest
@testable import PrataCore

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
}
