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
    private let shortLimit = RecordingLimit(maximum: 0.2, warningLead: 0.1)
    private var warnings = 0
    private var limits = 0

    private func start(_ watch: RecordingLimitWatch) {
        watch.start(onWarning: { [unowned self] in self.warnings += 1 }, onLimit: { [unowned self] in self.limits += 1 })
    }

    private func wait(_ seconds: Double) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }

    func testWarnsOnceThenStopsAtTheLimit() async throws {
        let watch = RecordingLimitWatch(limit: shortLimit)
        start(watch)
        XCTAssertTrue(watch.isWatching)

        let deadline = Date().addingTimeInterval(5)
        while limits == 0, Date() < deadline { try await wait(0.01) }

        XCTAssertEqual([warnings, limits], [1, 1])
        XCTAssertFalse(watch.isWatching)
    }

    func testARecordingThatEndsEarlyIsNeitherWarnedNorStopped() async throws {
        let watch = RecordingLimitWatch(limit: shortLimit)
        start(watch)
        watch.stop()
        XCTAssertFalse(watch.isWatching)

        try await wait(0.4)
        XCTAssertEqual([warnings, limits], [0, 0])
    }

    func testEndingAfterTheWarningCancelsTheStop() async throws {
        let watch = RecordingLimitWatch(limit: RecordingLimit(maximum: 0.3, warningLead: 0.2))
        start(watch)
        let deadline = Date().addingTimeInterval(5)
        while warnings == 0, Date() < deadline { try await wait(0.005) }
        watch.stop()

        try await wait(0.4)
        XCTAssertEqual([warnings, limits], [1, 0])
    }

    func testANewRecordingReplacesTheOldWatch() async throws {
        let watch = RecordingLimitWatch(limit: shortLimit)
        start(watch)
        start(watch)

        let deadline = Date().addingTimeInterval(5)
        while limits == 0, Date() < deadline { try await wait(0.01) }
        try await wait(0.3)

        XCTAssertEqual([warnings, limits], [1, 1])
    }
}
