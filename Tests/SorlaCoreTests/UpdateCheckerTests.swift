import XCTest
@testable import SorlaCore

private actor CountingReleaseSource: AppReleaseSource {
    private let result: Result<AppRelease, Error>
    private(set) var calls = 0

    init(_ result: Result<AppRelease, Error>) {
        self.result = result
    }

    func latestRelease() async throws -> AppRelease {
        calls += 1
        return try result.get()
    }
}

@MainActor
final class UpdateCheckerTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var now = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private var modelChecks = 0

    override func setUp() async throws {
        suiteName = "sorla-update-checker-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        modelChecks = 0
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
    }

    private func makeChecker(source: AppReleaseSource, automaticChecks: Bool) -> UpdateChecker {
        UpdateChecker(
            currentVersion: "1.0.0",
            source: source,
            automaticChecks: automaticChecks,
            defaults: defaults,
            now: { [unowned self] in self.now },
            checkModel: { [unowned self] in self.modelChecks += 1 }
        )
    }

    func testCheckNowAsksBothGitHubAndTheModel() async {
        let source = CountingReleaseSource(.success(AppRelease(tagName: "v1.1.0")))
        let checker = makeChecker(source: source, automaticChecks: false)

        checker.checkNow()
        XCTAssertEqual(checker.appStatus, .checking)
        await checker.appCheck?.value

        XCTAssertEqual(checker.appStatus, .available(version: "1.1.0"))
        XCTAssertEqual(modelChecks, 1)
        let calls = await source.calls
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(checker.lastAppCheck, now)
    }

    func testAFailedCheckNeverReadsAsLatest() async {
        let checker = makeChecker(source: CountingReleaseSource(.failure(URLError(.notConnectedToInternet))), automaticChecks: false)

        checker.checkNow()
        await checker.appCheck?.value

        XCTAssertEqual(checker.appStatus, .failed(.offline))
        XCTAssertNotEqual(UpdateRow.app(checker.appStatus).kind, .latest)
    }

    func testNoAutomaticAppCheckWhenTheToggleIsOff() async {
        let source = CountingReleaseSource(.success(AppRelease(tagName: "v1.1.0")))
        let checker = makeChecker(source: source, automaticChecks: false)

        checker.checkAppIfDue()
        await checker.appCheck?.value

        XCTAssertEqual(checker.appStatus, .notChecked)
        XCTAssertNil(checker.lastAppCheck)
        let calls = await source.calls
        XCTAssertEqual(calls, 0)
    }

    func testAnAutomaticCheckRunsOnceADay() async {
        let source = CountingReleaseSource(.success(AppRelease(tagName: "v1.0.0")))
        let checker = makeChecker(source: source, automaticChecks: true)

        checker.checkAppIfDue()
        await checker.appCheck?.value
        XCTAssertEqual(checker.appStatus, .upToDate)

        now = now.addingTimeInterval(6 * 60 * 60)
        checker.checkAppIfDue()
        await checker.appCheck?.value
        var calls = await source.calls
        XCTAssertEqual(calls, 1)

        now = now.addingTimeInterval(18 * 60 * 60)
        checker.checkAppIfDue()
        await checker.appCheck?.value
        calls = await source.calls
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(modelChecks, 0, "the model keeps its own schedule")
    }

    // The model's launch check reads this, so a relaunch within a day checks neither GitHub nor Hugging Face.
    func testTheSharedCheckIsDueOnlyAboutOnceADayAcrossRelaunches() async {
        let source = CountingReleaseSource(.success(AppRelease(tagName: "v1.0.0")))
        let first = makeChecker(source: source, automaticChecks: true)
        XCTAssertTrue(first.isAutomaticCheckDue)
        first.checkAppIfDue()
        await first.appCheck?.value
        XCTAssertFalse(first.isAutomaticCheckDue)

        now = now.addingTimeInterval(2 * 60 * 60)
        XCTAssertFalse(makeChecker(source: source, automaticChecks: true).isAutomaticCheckDue)
        now = now.addingTimeInterval(22 * 60 * 60)
        XCTAssertTrue(makeChecker(source: source, automaticChecks: true).isAutomaticCheckDue)
        XCTAssertFalse(makeChecker(source: source, automaticChecks: false).isAutomaticCheckDue)
    }

    func testTheLastCheckSurvivesARelaunch() async {
        let source = CountingReleaseSource(.success(AppRelease(tagName: "v1.0.0")))
        let first = makeChecker(source: source, automaticChecks: true)
        first.checkAppIfDue()
        await first.appCheck?.value

        now = now.addingTimeInterval(60)
        let relaunched = makeChecker(source: source, automaticChecks: true)
        relaunched.checkAppIfDue()
        await relaunched.appCheck?.value

        let calls = await source.calls
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(relaunched.appStatus, .notChecked)
    }

    func testTurningTheToggleOffStopsAutomaticChecks() async {
        let source = CountingReleaseSource(.success(AppRelease(tagName: "v1.0.0")))
        let checker = makeChecker(source: source, automaticChecks: true)

        checker.automaticChecks = false
        checker.checkAppIfDue()
        await checker.appCheck?.value

        let calls = await source.calls
        XCTAssertEqual(calls, 0)
    }
}

final class AppUpdateScheduleTests: XCTestCase {
    private let lastCheck = Date(timeIntervalSinceReferenceDate: 1_000_000)

    func testNeverDueWhenTurnedOff() {
        XCTAssertFalse(AppUpdateSchedule.isDue(automaticChecks: false, lastCheck: nil, now: lastCheck))
        XCTAssertFalse(AppUpdateSchedule.isDue(automaticChecks: false, lastCheck: lastCheck, now: lastCheck.addingTimeInterval(7 * 86_400)))
    }

    func testDueWhenNeverChecked() {
        XCTAssertTrue(AppUpdateSchedule.isDue(automaticChecks: true, lastCheck: nil, now: lastCheck))
    }

    func testDueAboutADayAfterTheLastCheck() {
        XCTAssertFalse(AppUpdateSchedule.isDue(automaticChecks: true, lastCheck: lastCheck, now: lastCheck.addingTimeInterval(12 * 3_600)))
        XCTAssertTrue(AppUpdateSchedule.isDue(automaticChecks: true, lastCheck: lastCheck, now: lastCheck.addingTimeInterval(86_400 - 60)))
        XCTAssertTrue(AppUpdateSchedule.isDue(automaticChecks: true, lastCheck: lastCheck, now: lastCheck.addingTimeInterval(3 * 86_400)))
    }

    // A clock set back would otherwise hold checks off until it caught up.
    func testALastCheckInTheFutureIsDue() {
        XCTAssertTrue(AppUpdateSchedule.isDue(automaticChecks: true, lastCheck: lastCheck, now: lastCheck.addingTimeInterval(-60)))
    }
}
