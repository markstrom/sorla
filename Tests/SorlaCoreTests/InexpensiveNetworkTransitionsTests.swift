import XCTest
@testable import SorlaCore

final class InexpensiveNetworkTransitionsTests: XCTestCase {
    // #87: the network in use when watching starts was just tried, so only a change brings a retry.
    func testOnlyANetworkComingUpCounts() {
        var transitions = InexpensiveNetworkTransitions()
        XCTAssertFalse(transitions.update(isUsable: true), "the network at the start was just tried")
        XCTAssertFalse(transitions.update(isUsable: true))
        XCTAssertFalse(transitions.update(isUsable: false))
        XCTAssertTrue(transitions.update(isUsable: true))
        XCTAssertFalse(transitions.update(isUsable: true))
    }

    func testStartingWithoutAUsableNetworkWaitsForOne() {
        var transitions = InexpensiveNetworkTransitions()
        XCTAssertFalse(transitions.update(isUsable: false))
        XCTAssertTrue(transitions.update(isUsable: true))
    }

    func testAHotspotOrLowDataModeIsNoUsableNetwork() {
        XCTAssertTrue(InexpensiveNetworkTransitions.isUsable(isSatisfied: true, isExpensive: false, isConstrained: false))
        XCTAssertFalse(InexpensiveNetworkTransitions.isUsable(isSatisfied: true, isExpensive: true, isConstrained: false))
        XCTAssertFalse(InexpensiveNetworkTransitions.isUsable(isSatisfied: true, isExpensive: false, isConstrained: true))
        XCTAssertFalse(InexpensiveNetworkTransitions.isUsable(isSatisfied: false, isExpensive: false, isConstrained: false))
    }
}
