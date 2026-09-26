import XCTest
@testable import Sorla

// The hand-off to the Sorla keyboard. `Handoff/TranscriptHandoff.swift` is compiled into the app and the keyboard;
// the tests reach it through the app module.
@MainActor
final class TranscriptHandoffTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var clock: Date!
    private var notifications: [String] = []

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("handoff-\(UUID().uuidString)", isDirectory: true)
        suiteName = "handoff-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        clock = Date(timeIntervalSinceReferenceDate: 800_000_000)
        notifications = []
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
    }

    // Two stores on one directory and one defaults suite stand for the app and the keyboard processes.
    private func makeStore() -> TranscriptHandoffStore {
        TranscriptHandoffStore(
            directory: directory, defaults: defaults,
            now: { [unowned self] in self.clock },
            notify: { [unowned self] in self.notifications.append($0) }
        )
    }

    private var pendingFile: URL { directory.appendingPathComponent("pending-transcript.json") }

    private func filesLeft() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    }

    // MARK: Record

    func testADeliveryRoundTripsThroughJSON() throws {
        let delivery = TranscriptDelivery(id: UUID(), text: "Hej på dig, åäö.", createdAt: clock)

        let decoded = try JSONDecoder().decode(TranscriptDelivery.self, from: JSONEncoder().encode(delivery))

        XCTAssertEqual(decoded, delivery)
    }

    func testADeliveryExpiresAfterFiveMinutes() {
        let delivery = TranscriptDelivery(id: UUID(), text: "Hej", createdAt: clock)

        XCTAssertFalse(delivery.isExpired(at: clock))
        XCTAssertFalse(delivery.isExpired(at: clock.addingTimeInterval(299)))
        XCTAssertTrue(delivery.isExpired(at: clock.addingTimeInterval(300)))
        XCTAssertTrue(delivery.isExpired(at: clock.addingTimeInterval(-1)), "a clock set back is not trusted")
    }

    // MARK: Delivery

    func testAnOfferedTranscriptIsDeliveredOnceAndThenDeleted() throws {
        let app = makeStore()
        let keyboard = makeStore()

        let offered = try app.offer("Hej på dig.")

        XCTAssertEqual(notifications, [TranscriptHandoff.transcriptReadyNotification])
        XCTAssertEqual(keyboard.claimPendingDelivery(), offered)
        XCTAssertNil(keyboard.claimPendingDelivery())
        XCTAssertEqual(filesLeft(), [], "the text is deleted as soon as it is delivered")
    }

    func testTheSameRecordIsNeverInsertedTwice() throws {
        let app = makeStore()
        try app.offer("Hej")
        let saved = try Data(contentsOf: pendingFile)
        XCTAssertNotNil(makeStore().claimPendingDelivery())

        // The same record appearing again (e.g. restored) is deleted unused.
        try saved.write(to: pendingFile)

        XCTAssertNil(makeStore().claimPendingDelivery())
        XCTAssertEqual(filesLeft(), [])
    }

    func testANewerTranscriptReplacesAnUnclaimedOne() throws {
        let app = makeStore()
        try app.offer("Första")
        let second = try app.offer("Andra")

        XCTAssertEqual(makeStore().claimPendingDelivery(), second)
    }

    func testAnExpiredTranscriptIsDeletedUnused() throws {
        try makeStore().offer("Hej")
        clock = clock.addingTimeInterval(TranscriptHandoff.lifetime)

        XCTAssertNil(makeStore().claimPendingDelivery())
        XCTAssertEqual(filesLeft(), [])
    }

    func testAFreshTranscriptIsDeliveredJustBeforeItExpires() throws {
        let offered = try makeStore().offer("Hej")
        clock = clock.addingTimeInterval(TranscriptHandoff.lifetime - 1)

        XCTAssertEqual(makeStore().claimPendingDelivery(), offered)
    }

    func testTheAppRemovesOnlyExpiredTranscripts() throws {
        let app = makeStore()
        try app.offer("Hej")

        app.removeExpired()
        XCTAssertTrue(FileManager.default.fileExists(atPath: pendingFile.path))

        clock = clock.addingTimeInterval(TranscriptHandoff.lifetime)
        app.removeExpired()
        XCTAssertFalse(FileManager.default.fileExists(atPath: pendingFile.path))
    }

    func testAnUnreadableRecordIsDeletedUnused() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: pendingFile)

        XCTAssertNil(makeStore().claimPendingDelivery())
        XCTAssertEqual(filesLeft(), [])
    }

    func testNothingPendingIsNothingDelivered() {
        XCTAssertNil(makeStore().claimPendingDelivery())
    }

    func testTheTextNeverReachesUserDefaults() throws {
        let store = makeStore()
        try store.offer("Hemlig text")
        store.publish(.transcribing)
        _ = store.claimPendingDelivery()

        let stored = defaults.persistentDomain(forName: suiteName) ?? [:]
        XCTAssertFalse(stored.isEmpty)
        XCTAssertFalse(stored.values.contains { "\($0)".contains("Hemlig") })
    }

    // MARK: Phase

    func testAPublishedPhaseReachesTheKeyboard() {
        let app = makeStore()
        let keyboard = makeStore()

        XCTAssertEqual(keyboard.phase, .idle)
        app.publish(.listening)
        XCTAssertEqual(keyboard.phase, .listening)
        app.publish(.transcribing)
        XCTAssertEqual(keyboard.phase, .transcribing)
        app.publish(.idle)
        XCTAssertEqual(keyboard.phase, .idle)
        XCTAssertEqual(notifications, Array(repeating: TranscriptHandoff.phaseChangedNotification, count: 3))
    }

    func testAPhaseLeftByAGoneProcessReadsAsIdle() {
        makeStore().publish(.listening)
        clock = clock.addingTimeInterval(TranscriptHandoff.phaseLifetime)

        XCTAssertEqual(makeStore().phase, .idle)
    }

    func testTheDictationPhasesMapToTheKeyboardsStatus() {
        XCTAssertEqual(KeyboardPhase(DictationPhase.idle), .idle)
        XCTAssertEqual(KeyboardPhase(DictationPhase.listening), .listening)
        XCTAssertEqual(KeyboardPhase(DictationPhase.captured(.limitReached)), .captured)
        XCTAssertEqual(KeyboardPhase(DictationPhase.transcribing), .transcribing)
    }

    // MARK: App publisher

    func testThePublisherHandsOverOnlyTextThatMayBePasted() {
        let publisher = KeyboardHandoffPublisher(store: makeStore(), diagnose: { _ in XCTFail("no diagnostic expected") })

        for outcome: DictationOutcome in [.started, .nothingHeard, .cancelled, .busy, .failed(.timedOut), .transcribed("")] {
            publisher.deliver(outcome)
        }
        XCTAssertNil(makeStore().claimPendingDelivery())

        publisher.deliver(.transcribed("Hej på dig."))
        XCTAssertEqual(makeStore().claimPendingDelivery()?.text, "Hej på dig.")
    }

    func testThePublisherSendsEachPhaseChangeOnce() {
        let publisher = KeyboardHandoffPublisher(store: makeStore(), diagnose: { _ in })

        publisher.launch()
        publisher.publish(.idle)
        publisher.publish(.listening)
        publisher.publish(.listening)
        publisher.publish(.captured(.interrupted))

        XCTAssertEqual(notifications.count, 3)
        XCTAssertEqual(makeStore().phase, .captured)
    }

    func testWithoutTheAppGroupTheTranscriptIsNotHandedOverAndTheReasonIsLoggedWithoutText() {
        var diagnostics: [String] = []
        let publisher = KeyboardHandoffPublisher(store: nil, diagnose: { diagnostics.append($0) })

        publisher.deliver(.transcribed("Hemlig text"))

        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertFalse(diagnostics[0].contains("Hemlig"))
    }

    // MARK: Coordinator

    func testADictationPublishesListeningTranscribingAndIdle() async {
        let transcriber = FakeTranscriber()
        let timeLimit = ManualTimeLimit()
        let coordinator = DictationCoordinator(
            recorder: FakeRecorder(), transcriber: transcriber, system: FakeSystem(), limitWatch: FakeLimitWatch(),
            waitForTimeLimit: { await timeLimit.wait($0) }
        )
        var phases: [DictationPhase] = []
        coordinator.onPhaseChange = { phases.append($0) }

        _ = await coordinator.toggle()
        let stop = Task { await coordinator.toggle() }
        await transcriber.waitForTranscribeCall()
        await transcriber.reply(.text("Hej"))
        _ = await stop.value

        XCTAssertEqual(phases, [.listening, .transcribing, .idle])
        timeLimit.fire()
    }

    // MARK: Darwin notification

    func testTheObserverHearsAPostedNotification() async {
        let name = "se.sorla.ios.test-\(UUID().uuidString)"
        let heard = expectation(description: "notification heard")
        let observer = DarwinNotificationObserver(names: [name]) { heard.fulfill() }

        DarwinNotification.post(name)

        await fulfillment(of: [heard], timeout: 5)
        withExtendedLifetime(observer) {}
    }
}
