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
}
