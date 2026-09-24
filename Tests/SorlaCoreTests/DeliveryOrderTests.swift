import XCTest
@testable import SorlaCore

final class DeliveryOrderTests: XCTestCase {
    func testALaterResultWaitsForTheEarlierOne() {
        var order = DeliveryOrder<String>()
        order.expect(1)
        order.expect(2)

        XCTAssertEqual(order.finish(2, with: "B"), [])
        XCTAssertEqual(order.finish(1, with: "A"), ["A", "B"])
    }

    func testResultsInOrderAreDueAtOnce() {
        var order = DeliveryOrder<String>()
        order.expect(1)
        order.expect(2)

        XCTAssertEqual(order.finish(1, with: "A"), ["A"])
        XCTAssertEqual(order.finish(2, with: "B"), ["B"])
    }

    func testAfterDroppingALaterRecordingWaitsForNothingEarlier() {
        var order = DeliveryOrder<String>()
        order.expect(1)
        order.expect(2)
        XCTAssertEqual(order.finish(2, with: "B"), [])
        XCTAssertEqual(order.dropAll(), ["B"])
        order.expect(3)

        XCTAssertEqual(order.finish(3, with: "C"), ["C"])
        XCTAssertEqual(order.finish(1, with: "A"), [])
    }

    func testAResultNobodyExpectsIsIgnored() {
        var order = DeliveryOrder<String>()
        XCTAssertEqual(order.finish(7, with: "X"), [])
    }
}
