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

    func testThePhysicalStateIsOnlyAskedForOnARelease() {
        var asked = 0
        _ = TriggerEdge.forModifierEvent(isSynthetic: false, hasTriggerFlag: true) { asked += 1; return true }
        _ = TriggerEdge.forModifierEvent(isSynthetic: true, hasTriggerFlag: false) { asked += 1; return true }
        XCTAssertEqual(asked, 0)
    }
}
