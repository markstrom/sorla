import XCTest
@testable import SorlaCore

@MainActor
final class StartSoundScheduleTests: XCTestCase {
    private let clock = TestClock()
    private var plays = 0

    private func makeSchedule() -> StartSoundSchedule {
        StartSoundSchedule(sleep: { [clock] in await clock.sleep(for: $0) })
    }

    func testACancelBeforeTheStartSoundStaysQuiet() async {
        let schedule = makeSchedule()
        schedule.schedule(after: 0.3) { [unowned self] in self.plays += 1 }
        await clock.waitForSleeps(1)
        await clock.advance(by: .milliseconds(290))

        XCTAssertFalse(schedule.stop(), "no start was heard, so no cancel cue")
        await clock.advance(by: .milliseconds(20))
        XCTAssertEqual(plays, 0, "the start sound is called off too")
    }

    func testACancelAfterTheStartSoundIsAnnounced() async {
        let schedule = makeSchedule()
        schedule.schedule(after: 0.3) { [unowned self] in self.plays += 1 }
        await clock.waitForSleeps(1)
        await clock.advance(by: .milliseconds(300))

        XCTAssertEqual(plays, 1)
        XCTAssertFalse(schedule.isPending)
        XCTAssertTrue(schedule.stop())
        XCTAssertFalse(schedule.stop(), "each start answers once")
    }

    func testAStartWithoutADelayCountsAsHeardAtOnce() {
        let schedule = makeSchedule()
        schedule.schedule(after: 0) {}
        XCTAssertTrue(schedule.stop())
    }

    func testANewStartForgetsThePreviousOne() async {
        let schedule = makeSchedule()
        schedule.schedule(after: 0) {}
        schedule.schedule(after: 0.3) { [unowned self] in self.plays += 1 }
        XCTAssertTrue(schedule.isPending)
        XCTAssertFalse(schedule.stop())

        await clock.waitForSleeps(1)
        await clock.advance(by: .seconds(1))
        XCTAssertEqual(plays, 0)
    }
}
