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

@MainActor
final class RecordingLimitWatchTests: XCTestCase {
    private let clock = TestClock()
    private var warnings = 0
    private var limits = 0

    private func makeWatch() -> RecordingLimitWatch {
        RecordingLimitWatch(limit: .standard, now: { [clock] in clock.now }, sleep: { [clock] in await clock.sleep(for: $0) })
    }

    private func start(_ watch: RecordingLimitWatch) {
        watch.start(onWarning: { [unowned self] in self.warnings += 1 }, onLimit: { [unowned self] in self.limits += 1 })
    }

    func testWarnsOnceThenStopsAtTheLimit() async {
        let watch = makeWatch()
        start(watch)
        XCTAssertTrue(watch.isWatching)
        await clock.waitForSleeps(1)

        await clock.advance(by: .seconds(289))
        XCTAssertEqual([warnings, limits], [0, 0])
        await clock.advance(by: .seconds(1))
        XCTAssertEqual([warnings, limits], [1, 0])
        await clock.advance(by: .seconds(9))
        XCTAssertEqual([warnings, limits], [1, 0])
        await clock.advance(by: .seconds(1))

        XCTAssertEqual([warnings, limits], [1, 1])
        XCTAssertFalse(watch.isWatching)
    }

    func testARecordingThatEndsEarlyIsNeitherWarnedNorStopped() async {
        let watch = makeWatch()
        start(watch)
        await clock.waitForSleeps(1)
        watch.stop()
        XCTAssertFalse(watch.isWatching)

        await clock.advance(by: .seconds(400))

        XCTAssertEqual([warnings, limits], [0, 0])
        XCTAssertEqual(clock.sleeps.count, 1)
    }

    func testEndingAfterTheWarningCancelsTheStop() async {
        let watch = makeWatch()
        start(watch)
        await clock.waitForSleeps(1)
        await clock.advance(by: .seconds(290))
        XCTAssertEqual(warnings, 1)
        watch.stop()

        await clock.advance(by: .seconds(100))

        XCTAssertEqual([warnings, limits], [1, 0])
    }

    func testANewRecordingReplacesTheOldWatch() async {
        let watch = makeWatch()
        start(watch)
        await clock.waitForSleeps(1)
        await clock.advance(by: .seconds(200))
        start(watch)
        await clock.waitForSleeps(2)

        await clock.advance(by: .seconds(100))
        XCTAssertEqual([warnings, limits], [0, 0])
        await clock.advance(by: .seconds(200))

        XCTAssertEqual([warnings, limits], [1, 1])
        XCTAssertFalse(watch.isWatching)
    }
}
