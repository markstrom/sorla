import XCTest
@testable import Sorla

@MainActor
final class DictationCoordinatorTests: XCTestCase {
    private var recorder: FakeRecorder!
    private var system: FakeSystem!
    private var limitWatch: FakeLimitWatch!
    private var transcriber: FakeTranscriber!
    private var timeLimit: ManualTimeLimit!
    private var coordinator: DictationCoordinator!

    override func setUp() async throws {
        recorder = FakeRecorder()
        system = FakeSystem()
        limitWatch = FakeLimitWatch()
        timeLimit = ManualTimeLimit()
        makeCoordinator(FakeTranscriber())
    }

    override func tearDown() async throws {
        // Lets any timer the tests left waiting finish, so nothing outlives the test.
        timeLimit.fire()
        await transcriber.reply(.text(""))
    }

    private func makeCoordinator(_ transcriber: FakeTranscriber) {
        self.transcriber = transcriber
        let timeLimit = self.timeLimit!
        coordinator = DictationCoordinator(
            recorder: recorder,
            transcriber: transcriber,
            system: system,
            limitWatch: limitWatch,
            waitForTimeLimit: { await timeLimit.wait($0) }
        )
    }

    // MARK: Start

    func testTheFirstTriggerStartsListeningAndReturnsAtOnce() async {
        let outcome = await coordinator.toggle()

        XCTAssertEqual(outcome, .started)
        XCTAssertEqual(coordinator.phase, .listening)
        XCTAssertEqual(recorder.starts, 1)
        XCTAssertTrue(system.isActivityShowing)
        XCTAssertNotNil(system.sessionMarker)
        XCTAssertTrue(limitWatch.isWatching)
        XCTAssertNil(outcome.textToCopy)
    }

    func testStartingLoadsTheModelWhileTheUserSpeaks() async {
        _ = await coordinator.toggle()
        await transcriber.waitForPrepare()

        let prepares = await transcriber.prepareCalls
        XCTAssertEqual(prepares, 1)
    }

    func testWithoutTheMicrophoneNothingStarts() async {
        system.isMicrophoneAuthorized = false

        let outcome = await coordinator.toggle()

        XCTAssertEqual(outcome, .failed(.microphoneNotAuthorized))
        XCTAssertEqual(recorder.starts, 0)
        XCTAssertFalse(system.isActivityShowing)
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testWithoutAModelNothingIsRecorded() async {
        system.isModelInstalled = false

        let outcome = await coordinator.toggle()

        XCTAssertEqual(outcome, .failed(.modelMissing))
        XCTAssertEqual(recorder.starts, 0)
    }

    func testWithoutALiveActivityTheMicrophoneStaysOff() async {
        system.canStartActivity = false

        let outcome = await coordinator.toggle()

        XCTAssertEqual(outcome, .failed(.liveActivityUnavailable))
        XCTAssertEqual(recorder.starts, 0)
        XCTAssertNil(system.sessionMarker)
    }

    func testTheRecordersSessionSetupIsLoggedBeforeStarted() async {
        _ = await coordinator.toggle()

        XCTAssertEqual(system.metrics.map(\.outcome), ["diagnostic.session: category playAndRecord", "started"])
    }

    func testTheSessionSetupIsLoggedEvenWhenTheMicrophoneFailsToStart() async {
        recorder.startError = CocoaError(.featureUnsupported)

        _ = await coordinator.toggle()

        let outcomes = system.metrics.map(\.outcome)
        XCTAssertEqual(outcomes.first, "diagnostic.session: category playAndRecord")
        XCTAssertTrue(outcomes[1].hasPrefix("diagnostic.audioStart: "))
        XCTAssertEqual(outcomes.last, "failed.audioStartFailed")
    }

    func testRecorderDiagnosticsWhileListeningAreLogged() async {
        _ = await coordinator.toggle()

        recorder.diagnose("audioRestart: first second silent, started over on a new engine")

        XCTAssertEqual(system.metrics.last?.outcome, "diagnostic.audioRestart: first second silent, started over on a new engine")
    }

    func testTheAudioRowSaysWhereTheSoundWasAndHowLongItListened() async {
        let clock = ManualClock()
        let timeLimit = self.timeLimit!
        coordinator = DictationCoordinator(
            recorder: recorder,
            transcriber: FakeTranscriber(immediateReply: .text("Hej")),
            system: system,
            limitWatch: limitWatch,
            now: { clock.now },
            waitForTimeLimit: { await timeLimit.wait($0) }
        )
        let silence = [Float](repeating: 0, count: 16_000)
        recorder.samples = silence + FakeRecorder.speech(seconds: 1) + silence
        _ = await coordinator.toggle()
        clock.advance(by: .seconds(5))

        _ = await coordinator.toggle()

        let audio = system.metrics.first { $0.outcome.hasPrefix("diagnostic.audio:") }?.outcome
        XCTAssertNotNil(audio)
        XCTAssertTrue(audio?.hasSuffix("sound 1.0–2.0 s of 3.0 s, listened 5.0 s") ?? false, audio ?? "")
    }

    func testTheAudioRowSaysWhenThereWasNoSoundAtAll() {
        XCTAssertEqual(
            DictationCoordinator.levels(of: Array(repeating: 0, count: 32_000), listenedSeconds: 9),
            "audio: 32000 samples, peak -inf dBFS, rms -inf dBFS, no sound in 2.0 s, listened 9.0 s"
        )
        XCTAssertEqual(DictationCoordinator.levels(of: [], listenedSeconds: 3), "audio: no samples, listened 3.0 s")
    }

    func testAMicrophoneThatFailsToStartEndsTheLiveActivity() async {
        recorder.startError = CocoaError(.featureUnsupported)

        let outcome = await coordinator.toggle()

        XCTAssertEqual(outcome, .failed(.audioStartFailed))
        XCTAssertFalse(system.isActivityShowing)
        XCTAssertNil(system.sessionMarker)
        XCTAssertEqual(coordinator.phase, .idle)
    }

    // MARK: Stop

    func testTheSecondTriggerStopsTheMicrophoneBeforeTranscribing() async {
        _ = await coordinator.toggle()
        let stop = Task { await coordinator.toggle() }
        await transcriber.waitForTranscribeCall()

        XCTAssertEqual(recorder.stops, 1)
        XCTAssertFalse(recorder.isCapturing)
        XCTAssertEqual(coordinator.phase, .transcribing)
        XCTAssertEqual(system.activityPhases.last, .transcribing)
        XCTAssertTrue(system.isBackgroundTaskRunning)

        await transcriber.reply(.text(" Hej på dig. "))
        let outcome = await stop.value

        XCTAssertEqual(outcome, .transcribed("Hej på dig."))
        XCTAssertEqual(outcome.textToCopy, "Hej på dig.")
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertFalse(system.isActivityShowing)
        XCTAssertFalse(system.isBackgroundTaskRunning)
        XCTAssertNil(system.sessionMarker)
        XCTAssertFalse(limitWatch.isWatching)
    }

    func testAnEmptyTranscriptIsNothingHeardAndNothingToCopy() async {
        makeCoordinator(FakeTranscriber(immediateReply: .text("  \n")))
        _ = await coordinator.toggle()

        let outcome = await coordinator.toggle()

        XCTAssertEqual(outcome, .nothingHeard)
        XCTAssertNil(outcome.textToCopy)
    }

    func testTooLittleAudioIsNotTranscribed() async {
        recorder.samples = FakeRecorder.speech(seconds: 0.05)
        _ = await coordinator.toggle()

        let outcome = await coordinator.toggle()

        XCTAssertEqual(outcome, .nothingHeard)
        let calls = await transcriber.transcribeCalls
        XCTAssertEqual(calls, 0)
    }

    func testDigitalSilenceIsASilentMicrophoneNotNothingHeard() async {
        recorder.samples = Array(repeating: 0, count: 32_000)
        _ = await coordinator.toggle()

        let outcome = await coordinator.toggle()

        XCTAssertEqual(outcome, .failed(.silentInput))
        XCTAssertEqual(outcome.message, "The microphone delivered no sound.")
        XCTAssertNil(outcome.textToCopy)
        let calls = await transcriber.transcribeCalls
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(system.metrics.last?.outcome, "failed.silentInput")
        XCTAssertTrue(system.metrics.contains { $0.outcome.hasPrefix("diagnostic.audio: 32000 samples, peak -inf dBFS") })
        XCTAssertFalse(system.isActivityShowing)
        XCTAssertNil(system.sessionMarker)
    }

    func testInputBelowMinus90dBFSIsASilentMicrophone() async {
        recorder.samples = Array(repeating: 1e-5, count: 32_000)
        _ = await coordinator.toggle()

        let outcome = await coordinator.toggle()

        XCTAssertEqual(outcome, .failed(.silentInput))
    }

    func testCapturedSilenceAfterAnInterruptionIsASilentMicrophoneToo() async {
        recorder.samples = Array(repeating: 0, count: 32_000)
        _ = await coordinator.toggle()
        recorder.endCapture(.interrupted)

        let outcome = await coordinator.toggle()

        XCTAssertEqual(outcome, .failed(.silentInput))
        XCTAssertEqual(system.metrics.last?.captureEnd, "interrupted")
    }

    func testAFailedTranscriptionIsReportedWithoutText() async {
        makeCoordinator(FakeTranscriber(immediateReply: .failure))
        _ = await coordinator.toggle()

        let outcome = await coordinator.toggle()

        XCTAssertEqual(outcome, .failed(.transcriptionFailed))
        XCTAssertNil(outcome.textToCopy)
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testATranscriptionThatHangsEndsAtTheTimeLimit() async {
        _ = await coordinator.toggle()
        let stop = Task { await coordinator.toggle() }
        await transcriber.waitForTranscribeCall()
        await timeLimit.waitUntilRequested()

        timeLimit.fire()
        let outcome = await stop.value

        XCTAssertEqual(outcome, .failed(.timedOut))
        XCTAssertEqual(timeLimit.requested, [.seconds(30)])
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testExpiredBackgroundTimeEndsTheTranscription() async {
        _ = await coordinator.toggle()
        let stop = Task { await coordinator.toggle() }
        await transcriber.waitForTranscribeCall()

        system.expireBackgroundTime()
        let outcome = await stop.value

        XCTAssertEqual(outcome, .failed(.backgroundTimeExpired))
        XCTAssertFalse(system.isActivityShowing)
    }

    func testTheTimeLimitGrowsWithTheRecording() {
        XCTAssertEqual(DictationCoordinator.transcriptionTimeLimit(audioSeconds: 5), .seconds(30))
        XCTAssertEqual(DictationCoordinator.transcriptionTimeLimit(audioSeconds: 60), .seconds(180))
    }

    // MARK: Repeated and rapid triggers

    func testATriggerDuringTranscriptionIsBusyAndDoesNotTakeTheResult() async {
        _ = await coordinator.toggle()
        let stop = Task { await coordinator.toggle() }
        await transcriber.waitForTranscribeCall()

        let second = await coordinator.toggle()
        XCTAssertEqual(second, .busy)
        XCTAssertNil(second.textToCopy)
        XCTAssertEqual(recorder.starts, 1)

        await transcriber.reply(.text("Ett"))
        let first = await stop.value
        XCTAssertEqual(first, .transcribed("Ett"))
    }

    func testConsecutiveDictationsEachGetTheirOwnText() async {
        makeCoordinator(FakeTranscriber())
        for (index, word) in ["Ett", "Två", "Tre"].enumerated() {
            let started = await coordinator.toggle()
            XCTAssertEqual(started, .started)
            let stop = Task { await coordinator.toggle() }
            await transcriber.waitForTranscribeCall(index + 1)
            await transcriber.reply(.text(word))
            let outcome = await stop.value
            XCTAssertEqual(outcome, .transcribed(word))
        }
        XCTAssertEqual(recorder.starts, 3)
        XCTAssertEqual(system.activityStarts, 3)
    }

    // MARK: Cancel

    func testCancellingWhileListeningDiscardsTheAudio() async {
        _ = await coordinator.toggle()

        XCTAssertTrue(coordinator.cancel())

        XCTAssertEqual(recorder.cancels, 1)
        XCTAssertEqual(recorder.stops, 0)
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertFalse(system.isActivityShowing)
        XCTAssertNil(system.sessionMarker)
        XCTAssertEqual(system.metrics.last?.outcome, "cancelled")
    }

    func testCancellingWhenIdleDoesNothing() {
        XCTAssertFalse(coordinator.cancel())
        XCTAssertTrue(system.metrics.isEmpty)
    }

    func testCancellingDuringTranscriptionDropsTheLateResult() async {
        _ = await coordinator.toggle()
        let stop = Task { await coordinator.toggle() }
        await transcriber.waitForTranscribeCall()

        XCTAssertTrue(coordinator.cancel())
        let outcome = await stop.value
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertNil(outcome.textToCopy)

        // The abandoned transcription finishes later; its text must not reach the next dictation.
        await transcriber.reply(.text("Gammal text"))
        let started = await coordinator.toggle()
        XCTAssertEqual(started, .started)
        let next = Task { await coordinator.toggle() }
        await transcriber.waitForTranscribeCall(2)
        await transcriber.reply(.text("Ny text"))
        let nextOutcome = await next.value
        XCTAssertEqual(nextOutcome, .transcribed("Ny text"))
    }

    // MARK: Capture ending by itself

    func testTheRecordingLimitClosesTheMicrophoneAndKeepsTheAudioForTheNextTrigger() async {
        makeCoordinator(FakeTranscriber(immediateReply: .text("Lång diktering")))
        _ = await coordinator.toggle()

        limitWatch.reachLimit()

        XCTAssertEqual(coordinator.phase, .captured(.limitReached))
        XCTAssertFalse(recorder.isCapturing)
        XCTAssertEqual(system.activityPhases.last, .captured)
        XCTAssertNotNil(system.sessionMarker)

        let outcome = await coordinator.toggle()
        XCTAssertEqual(outcome, .transcribed("Lång diktering"))
        XCTAssertEqual(recorder.stops, 1)
        XCTAssertEqual(system.metrics.last?.captureEnd, "limitReached")
    }

    func testAnInterruptionEndsCaptureTheSameWay() async {
        _ = await coordinator.toggle()

        recorder.endCapture(.interrupted)

        XCTAssertEqual(coordinator.phase, .captured(.interrupted))
        XCTAssertFalse(limitWatch.isWatching)
    }

    func testCancellingCapturedAudioDiscardsIt() async {
        _ = await coordinator.toggle()
        recorder.endCapture(.routeChanged)

        XCTAssertTrue(coordinator.cancel())

        XCTAssertEqual(coordinator.phase, .idle)
        let calls = await transcriber.transcribeCalls
        XCTAssertEqual(calls, 0)
    }

    func testAnInterruptionWhenNotListeningIsIgnored() {
        recorder.endCapture(.interrupted)
        XCTAssertEqual(coordinator.phase, .idle)
    }

    // MARK: Lost sessions

    func testATriggerAfterTheRecordingProcessDiedReportsItInsteadOfStarting() async {
        system.sessionMarker = Date(timeIntervalSinceNow: -30)

        let outcome = await coordinator.toggle()

        XCTAssertEqual(outcome, .failed(.sessionLost))
        XCTAssertEqual(recorder.starts, 0)
        XCTAssertNil(system.sessionMarker)
        let next = await coordinator.toggle()
        XCTAssertEqual(next, .started)
    }

    // MARK: Metrics

    func testMetricsCarryTimingsButNeverText() async {
        makeCoordinator(FakeTranscriber(immediateReply: .text("Hemlig mening")))
        _ = await coordinator.toggle()
        _ = await coordinator.toggle()

        let outcomes = system.metrics.filter { !$0.outcome.hasPrefix("diagnostic.") }
        XCTAssertEqual(outcomes.map(\.outcome), ["started", "transcribed"])
        XCTAssertNotNil(outcomes[0].invocationToListeningMs)
        XCTAssertNotNil(outcomes[1].stopToResultMs)
        XCTAssertEqual(outcomes[1].audioSeconds ?? 0, 2, accuracy: 0.001)
        XCTAssertEqual(outcomes[1].backgroundSecondsRemainingAtStop, 25)
        // Levels are numbers only, so the diagnostic row can't carry the transcript either.
        XCTAssertTrue(system.metrics.contains { $0.outcome.hasPrefix("diagnostic.audio: 32000 samples") })
        let encoded = String(decoding: try! JSONEncoder().encode(system.metrics), as: UTF8.self)
        XCTAssertFalse(encoded.contains("Hemlig"))
    }

    func testUnloadingWaitsUntilIdle() async {
        _ = await coordinator.toggle()
        await coordinator.unloadModelIfIdle()
        var unloads = await transcriber.unloadCalls
        XCTAssertEqual(unloads, 0)

        coordinator.cancel()
        await coordinator.unloadModelIfIdle()
        unloads = await transcriber.unloadCalls
        XCTAssertEqual(unloads, 1)
    }
}
