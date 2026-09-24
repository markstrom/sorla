import XCTest
@testable import SorlaCore

final class TriggerEdgeTests: XCTestCase {
    private func edge(
        isSynthetic: Bool = false,
        hasTriggerFlag: Bool,
        isKeyPhysicallyDown: Bool
    ) -> TriggerEdge? {
        TriggerEdge.forModifierEvent(
            isSynthetic: isSynthetic,
            hasTriggerFlag: hasTriggerFlag,
            isKeyPhysicallyDown: { isKeyPhysicallyDown }
        )
    }

    func testAPressIsADown() {
        XCTAssertEqual(edge(hasTriggerFlag: true, isKeyPhysicallyDown: true), .down)
    }

    func testAGenuineReleaseIsAnUp() {
        XCTAssertEqual(edge(hasTriggerFlag: false, isKeyPhysicallyDown: false), .up)
    }

    // #4: a modifier change without the trigger's flag while the key is still held must not stop the recording.
    func testAMissingFlagWhileTheKeyIsStillHeldIsIgnored() {
        XCTAssertNil(edge(hasTriggerFlag: false, isKeyPhysicallyDown: true))
    }

    func testSorlasOwnPasteNeverCountsAsTheTrigger() {
        XCTAssertNil(edge(isSynthetic: true, hasTriggerFlag: false, isKeyPhysicallyDown: false))
        XCTAssertNil(edge(isSynthetic: true, hasTriggerFlag: true, isKeyPhysicallyDown: true))
    }

    func testAnIgnoredReleaseIsRecheckedOnlyWhileAPressIsInProgress() {
        XCTAssertTrue(TriggerEdge.shouldRecheckRelease(isSynthetic: false, hasTriggerFlag: false, isWaitingForRelease: true))
        XCTAssertFalse(TriggerEdge.shouldRecheckRelease(isSynthetic: false, hasTriggerFlag: false, isWaitingForRelease: false))
        XCTAssertFalse(TriggerEdge.shouldRecheckRelease(isSynthetic: true, hasTriggerFlag: false, isWaitingForRelease: true))
        XCTAssertFalse(TriggerEdge.shouldRecheckRelease(isSynthetic: false, hasTriggerFlag: true, isWaitingForRelease: true))
    }

    func testTheRecheckReleasesOnlyAKeyThatIsUpByThen() {
        XCTAssertEqual(TriggerEdge.afterRecheck(isKeyPhysicallyDown: false), .up)
        XCTAssertNil(TriggerEdge.afterRecheck(isKeyPhysicallyDown: true))
    }

    func testAGestureWaitsForTheReleaseOnlyDuringAPress() {
        var pushToTalk = PushToTalkGesture(mode: .pushToTalk)
        XCTAssertFalse(pushToTalk.isWaitingForRelease)
        _ = pushToTalk.handle(.triggerDown(at: 0))
        XCTAssertTrue(pushToTalk.isWaitingForRelease)
        _ = pushToTalk.handle(.triggerUp(at: 1))
        XCTAssertFalse(pushToTalk.isWaitingForRelease)

        var toggle = PushToTalkGesture(mode: .toggle)
        _ = toggle.handle(.triggerDown(at: 0))
        XCTAssertTrue(toggle.isWaitingForRelease)
        _ = toggle.handle(.triggerUp(at: 0.1))
        XCTAssertFalse(toggle.isWaitingForRelease, "recording, key up: no release pending")
        _ = toggle.handle(.triggerDown(at: 2))
        XCTAssertTrue(toggle.isWaitingForRelease)
    }

    func testThePhysicalStateIsOnlyAskedForOnARelease() {
        var asked = 0
        _ = TriggerEdge.forModifierEvent(isSynthetic: false, hasTriggerFlag: true) { asked += 1; return true }
        _ = TriggerEdge.forModifierEvent(isSynthetic: true, hasTriggerFlag: false) { asked += 1; return true }
        XCTAssertEqual(asked, 0)
    }
}
