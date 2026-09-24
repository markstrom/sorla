import XCTest
@testable import SorlaCore

final class RecordingLimitTests: XCTestCase {
    func testTheStandardLimitIsFiveMinutesWithATenSecondWarning() {
        XCTAssertEqual(RecordingLimit.standard.maximum, 5 * 60)
        XCTAssertEqual(RecordingLimit.standard.warningLead, 10)
    }

    func testAFreshRecordingWaitsUntilTenSecondsBeforeTheLimitToWarn() {
        XCTAssertEqual(RecordingLimit.standard.nextStep(elapsed: 0), .warn(after: 290))
    }

    func testPartWayThroughTheWarningComesAtTheSameMoment() {
        XCTAssertEqual(RecordingLimit.standard.nextStep(elapsed: 100), .warn(after: 190))
    }

    func testOnceWarnedTheRecordingStopsAtTheLimit() {
        XCTAssertEqual(RecordingLimit.standard.nextStep(elapsed: 290), .stop(after: 10))
        XCTAssertEqual(RecordingLimit.standard.nextStep(elapsed: 295), .stop(after: 5))
    }

    func testAtOrPastTheLimitItStopsAtOnce() {
        XCTAssertEqual(RecordingLimit.standard.nextStep(elapsed: 300), .stop(after: 0))
        XCTAssertEqual(RecordingLimit.standard.nextStep(elapsed: 400), .stop(after: 0))
    }

    func testAWarningLongerThanTheLimitGoesStraightToTheStop() {
        let limit = RecordingLimit(maximum: 5, warningLead: 10)
        XCTAssertEqual(limit.nextStep(elapsed: 0), .stop(after: 5))
    }
}
