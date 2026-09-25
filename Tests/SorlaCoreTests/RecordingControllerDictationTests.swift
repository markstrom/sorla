import XCTest
@testable import SorlaCore

@MainActor
final class RecordingControllerDictationTests: XCTestCase {
    private let clock = TestClock()
    // The transcription time limit runs on its own clock, so its waits don't count among the others.
    private let limitClock = TestClock()
    private let input = FakeAudioInput()
    private let resampler = FakeResampler()
    private let engine = HeldTranscriptionEngine()
    private let paste = FakePasteEnvironment()
    private var controller: RecordingController!
    private var events: [String] = []

    override func setUp() async throws {
        let clock = self.clock
        let limitClock = self.limitClock
        controller = RecordingController(
            engine: engine,
            modelName: "test",
            inputDeviceState: SilentInputDevice(),
            recorder: AudioRecorder(input: input, resampler: resampler),
            pasteEnvironment: paste,
            isMicrophoneAccessDenied: { false },
            sleep: { await clock.sleep(for: $0) },
            now: { clock.now },
            waitForTimeLimit: { await limitClock.sleep(for: $0) }
        )
        controller.onCue = { [unowned self] in events.append("cue \($0.symbolName)") }
        controller.onIssue = { [unowned self] in events.append("issue \($0.menuTitle)") }
        controller.onPaste = { [unowned self] in events.append("pasted \(paste.contents ?? "")") }
    }

    // Returns once the request made by `action` has reached the delivery queue.
    private func untilEnqueued(_ action: () -> Void) async {
        await withCheckedContinuation { continuation in
            controller.didEnqueueDelivery = { [unowned self] in
                controller.didEnqueueDelivery = nil
                continuation.resume()
            }
            action()
        }
    }

    // One second of audio, well over the model's minimum.
    private func record() {
        XCTAssertTrue(controller.startRecording())
        for _ in 0..<16 { input.feed(count: 1_000) }
    }

    private var tail: Duration { .seconds(controller.tailDuration) }
    private let settle = RecordingController.pasteSettleTime

    // Records and releases, and lets the tail run out so the transcription has started.
    private func dictate(call: Int) async -> Task<Void, Never> {
        record()
        controller.stopRecordingAndTranscribe()
        await clock.waitForSleeps(clock.sleeps.count + 1)
        await clock.advance(by: tail)
        await engine.waitForCalls(call + 1)
        return controller.dictationJobs[call + 1]!
    }

    // MARK: - The recorded audio is let go (#38)

    func testAfterTheTailTheRecorderKeepsNoAudioWhileTranscribing() async {
        record()
        XCTAssertTrue(controller.stopRecordingAndTranscribe())
        await clock.waitForSleeps(1)
        XCTAssertEqual(controller.recorder.heldSampleCount, 16_000)

        await clock.advance(by: tail)
        await engine.waitForCalls(1)

        XCTAssertEqual(controller.recorder.heldSampleCount, 0)
        let counts = await engine.sampleCounts
        XCTAssertEqual(counts, [16_000])
        await engine.finish(0, with: "")
    }

    func testCancellingLetsGoOfTheAudioWithoutResampling() {
        record()

        controller.cancelRecording()

        XCTAssertEqual(controller.recorder.heldSampleCount, 0)
        XCTAssertEqual(resampler.calls, 0)
        XCTAssertFalse(input.isRunning)
    }

    func testLockingWhileRecordingLetsGoOfTheAudio() {
        record()

        controller.cancelRecording()
        controller.forgetLastTranscript()

        XCTAssertEqual(controller.recorder.heldSampleCount, 0)
        XCTAssertEqual(resampler.calls, 0)
    }

    func testLockingDuringTheTailDropsTheAudioWithoutTranscribingIt() async {
        record()
        controller.stopRecordingAndTranscribe()
        await clock.waitForSleeps(1)

        controller.cancelRecording()
        controller.forgetLastTranscript()
        await clock.advance(by: tail)

        XCTAssertEqual(controller.recorder.heldSampleCount, 0)
        XCTAssertEqual(resampler.calls, 0)
        XCTAssertFalse(input.isRunning)
        XCTAssertEqual(controller.phase, .idle)
        let counts = await engine.sampleCounts
        XCTAssertEqual(counts, [])
    }

    func testAFailedResampleLetsGoOfTheAudio() async {
        resampler.error = AudioRecorderError.bufferAllocationFailed
        record()
        controller.stopRecordingAndTranscribe()
        let job = controller.dictationJobs[1]
        await clock.waitForSleeps(1)

        await clock.advance(by: tail)
        await job?.value
        await controller.deliveries?.value

        XCTAssertEqual(controller.recorder.heldSampleCount, 0)
        XCTAssertEqual(controller.phase, .idle)
    }

    // MARK: - Results are delivered in recording order (#37)

    func testASlowFirstDictationIsDeliveredBeforeAFastSecondOne() async {
        let first = await dictate(call: 0)
        let second = await dictate(call: 1)

        await engine.finish(1, with: "B")
        await second.value
        XCTAssertEqual(paste.writes, [])
        XCTAssertNil(controller.lastTranscript())
        XCTAssertEqual(controller.phase, .transcribing)

        await engine.finish(0, with: "A")
        await first.value
        // Sleep 3 restores A's clipboard, sleep 4 is B waiting for A's ⌘V to land.
        await clock.waitForSleeps(4)
        XCTAssertEqual(paste.pastes, ["A"])
        XCTAssertEqual(paste.writes, ["A"])
        XCTAssertEqual(controller.lastTranscript(), "A")

        await clock.advance(by: settle)
        await clock.waitForSleeps(5)
        XCTAssertEqual(paste.pastes, ["A", "B"])
        XCTAssertEqual(controller.lastTranscript(), "B")

        await clock.advance(by: settle)
        await controller.clipboardRestore?.value
        await controller.deliveries?.value
        XCTAssertEqual(paste.events, ["write A", "paste A", "restore", "write B", "paste B", "restore"])
        XCTAssertEqual(controller.phase, .idle)
    }

    func testAFailedFirstDictationDoesNotHoldUpTheNext() async {
        let first = await dictate(call: 0)
        let second = await dictate(call: 1)

        await engine.finish(1, with: "B")
        await second.value
        await engine.fail(0)
        await first.value
        await clock.waitForSleeps(3)

        XCTAssertEqual(events, ["issue \(SorlaIssue.transcriptionFailed.menuTitle)", "pasted B"])
        XCTAssertEqual(controller.lastTranscript(), "B")
    }

    func testAnEmptyFirstDictationDoesNotHoldUpTheNext() async {
        let first = await dictate(call: 0)
        let second = await dictate(call: 1)

        await engine.finish(1, with: "B")
        await second.value
        await engine.finish(0, with: "")
        await first.value
        await clock.waitForSleeps(3)

        XCTAssertEqual(events, ["cue \(DictationCue.noText.symbolName)", "pasted B"])
        XCTAssertEqual(controller.lastTranscript(), "B")
    }

    func testADictationDroppedByALockDoesNotHoldUpTheNext() async {
        let first = await dictate(call: 0)
        controller.forgetLastTranscript()
        let second = await dictate(call: 1)

        await engine.finish(1, with: "B")
        await second.value
        await clock.waitForSleeps(3)
        XCTAssertEqual(paste.pastes, ["B"])

        await engine.finish(0, with: "A")
        await first.value
        await controller.deliveries?.value
        XCTAssertEqual(paste.writes, ["B"])
        XCTAssertEqual(controller.lastTranscript(), "B")
        XCTAssertEqual(controller.phase, .idle)
    }

    func testAHungTranscriptionGivesUpAtItsTimeLimitSoTheNextIsDelivered() async {
        let first = await dictate(call: 0)
        let second = await dictate(call: 1)
        await engine.finish(1, with: "B")
        await second.value
        await limitClock.waitForSleeps(2)
        XCTAssertEqual(limitClock.sleeps, [.seconds(30), .seconds(30)])
        XCTAssertEqual(paste.pastes, [])

        await limitClock.advance(by: .seconds(30))
        await first.value
        await controller.deliveries?.value

        XCTAssertEqual(events, ["issue \(SorlaIssue.transcriptionFailed.menuTitle)", "pasted B"])
        XCTAssertEqual(controller.lastTranscript(), "B")
        XCTAssertEqual(controller.phase, .idle)
        await engine.finish(0, with: "A")
    }

    func testTheTimeLimitGrowsWithLongRecordings() {
        XCTAssertEqual(RecordingController.transcriptionTimeLimit(audioSeconds: 1), .seconds(30))
        XCTAssertEqual(RecordingController.transcriptionTimeLimit(audioSeconds: 60), .seconds(180))
    }

    func testALockWhileAResultWaitsItsTurnDropsIt() async {
        let first = await dictate(call: 0)
        let second = await dictate(call: 1)
        await engine.finish(1, with: "B")
        await second.value

        controller.forgetLastTranscript()
        await engine.finish(0, with: "A")
        await first.value
        await controller.deliveries?.value

        XCTAssertEqual(paste.writes, [])
        XCTAssertNil(controller.lastTranscript())
        XCTAssertEqual(controller.phase, .idle)
    }

    func testTheTargetAppIsCheckedWhenTheTextIsDelivered() async {
        let first = await dictate(call: 0)
        let second = await dictate(call: 1)
        await engine.finish(1, with: "B")
        await second.value

        paste.frontmostProcessID = 200
        await engine.finish(0, with: "A")
        await first.value
        await controller.deliveries?.value

        XCTAssertEqual(paste.pastes, [])
        XCTAssertEqual(paste.writes, ["A", "B"])
        let onClipboard = "cue \(DictationCue.textOnClipboard.symbolName)"
        XCTAssertEqual(events, [onClipboard, onClipboard])
        XCTAssertEqual(controller.lastTranscript(), "B")
    }

    // MARK: - Only a pasteboard write waits for the previous ⌘V (#37)

    func testTheFirstPasteDoesNotWaitAfterTheTail() async {
        var pastedAt: ContinuousClock.Instant?
        controller.onPaste = { [unowned self] in pastedAt = clock.now }
        let released = clock.now

        let job = await dictate(call: 0)
        await engine.finish(0, with: "A")
        await job.value
        await controller.deliveries?.value

        XCTAssertEqual(paste.pastes, ["A"])
        XCTAssertEqual(pastedAt.map { $0 - released }, tail)
    }

    func testACueOrFailureAfterAPasteIsNotHeldBack() async {
        let first = await dictate(call: 0)
        let second = await dictate(call: 1)
        let third = await dictate(call: 2)

        await engine.finish(0, with: "A")
        await first.value
        await engine.finish(1, with: "")
        await second.value
        await engine.fail(2)
        await third.value
        await controller.deliveries?.value

        XCTAssertEqual(events, ["pasted A", "cue \(DictationCue.noText.symbolName)", "issue \(SorlaIssue.transcriptionFailed.menuTitle)"])
        XCTAssertEqual(controller.phase, .idle)
    }

    func testASecondPasteWaitsOnlyForWhatIsLeftOfTheGap() async {
        let job = await dictate(call: 0)
        await engine.finish(0, with: "A")
        await job.value
        await controller.deliveries?.value
        await clock.waitForSleeps(2)
        XCTAssertEqual(controller.phase, .idle)

        await clock.advance(by: .milliseconds(200))
        let sleepsBefore = clock.sleeps.count
        controller.pasteLastTranscript()
        await clock.waitForSleeps(sleepsBefore + 1)
        XCTAssertEqual(clock.sleeps.last, settle - .milliseconds(200))
        XCTAssertEqual(paste.writes, ["A"])

        await clock.advance(by: settle - .milliseconds(200))
        await controller.deliveries?.value
        XCTAssertEqual(paste.pastes, ["A", "A"])

        await clock.waitForSleeps(sleepsBefore + 2)
        await clock.advance(by: settle)
        await controller.clipboardRestore?.value
        XCTAssertEqual(paste.events, ["write A", "paste A", "restore", "write A", "paste A", "restore"])
    }

    func testWithoutRestoringTheClipboardTheNextTextStillWaitsForThePasteToLand() async {
        controller.keepClipboardContent = false
        let first = await dictate(call: 0)
        let second = await dictate(call: 1)
        await engine.finish(0, with: "A")
        await first.value
        await engine.finish(1, with: "B")
        await second.value

        await clock.waitForSleeps(3)
        XCTAssertEqual(clock.sleeps.last, settle)
        XCTAssertEqual(paste.writes, ["A"])
        await clock.advance(by: settle)
        await controller.deliveries?.value

        XCTAssertEqual(paste.events, ["write A", "paste A", "write B", "paste B"])
    }

    // MARK: - Paste Last waits for the shortcut's keys (#11)

    private var modifiersHeld = true

    private var firstPoll = 0

    private func deliverOneDictation(_ text: String) async {
        let job = await dictate(call: 0)
        await engine.finish(0, with: text)
        await job.value
        await controller.deliveries?.value
        // Sleep 1 was the tail; sleep 2 puts back the clipboard, when there is one to put back.
        if controller.keepClipboardContent {
            await clock.waitForSleeps(2)
        }
        await clock.advance(by: settle)
        await controller.clipboardRestore?.value
        events = []
    }

    private func pasteLastWithTheShortcut() async {
        let clock = self.clock
        firstPoll = clock.sleeps.count + 1
        controller.pasteLastTranscript(after: {
            await ModifierRelease.wait(
                isHeld: { [unowned self] in self.modifiersHeld },
                now: { clock.now },
                sleep: { await clock.sleep(for: $0) }
            )
        })
        await clock.waitForSleeps(firstPoll)
    }

    func testPasteLastPastesOnceTheShortcutsKeysAreLetGo() async {
        await deliverOneDictation("A")
        await pasteLastWithTheShortcut()

        modifiersHeld = false
        await clock.advance(by: ModifierRelease.pollInterval)
        await clock.waitForSleeps(firstPoll + 1)
        XCTAssertEqual(paste.pastes, ["A", "A"])

        await clock.advance(by: settle)
        await controller.clipboardRestore?.value
        await controller.deliveries?.value
    }

    private func holdTheKeysPastTheDeadline() async {
        for poll in 0..<50 {
            await clock.waitForSleeps(firstPoll + poll)
            await clock.advance(by: ModifierRelease.pollInterval)
        }
        await controller.deliveries?.value
    }

    func testPasteLastHeldPastTheDeadlineLeavesTheClipboardAlone() async {
        await deliverOneDictation("A")
        paste.copy("mine")
        let writesBefore = paste.writes
        await pasteLastWithTheShortcut()

        await holdTheKeysPastTheDeadline()

        XCTAssertEqual(paste.writes, writesBefore)
        XCTAssertEqual(paste.contents, "mine")
        XCTAssertEqual(events, ["cue \(DictationCue.releaseKeys.symbolName)"])
        XCTAssertEqual(controller.lastTranscript(), "A")
    }

    func testWithoutKeepingTheClipboardPasteLastHeldPastTheDeadlineLeavesItAloneToo() async {
        controller.keepClipboardContent = false
        await deliverOneDictation("A")
        paste.copy("mine")
        let writesBefore = paste.writes
        await pasteLastWithTheShortcut()

        await holdTheKeysPastTheDeadline()

        XCTAssertEqual(paste.writes, writesBefore)
        XCTAssertEqual(paste.contents, "mine")
        XCTAssertEqual(events, ["cue \(DictationCue.releaseKeys.symbolName)"])
        XCTAssertEqual(controller.lastTranscript(), "A")
    }

    func testALockWhileWaitingForTheKeysAbandonsPasteLast() async {
        await deliverOneDictation("A")
        let writesBefore = paste.writes
        await pasteLastWithTheShortcut()

        controller.forgetLastTranscript()
        modifiersHeld = false
        await clock.advance(by: ModifierRelease.pollInterval)
        await controller.deliveries?.value

        XCTAssertEqual(paste.writes, writesBefore)
        XCTAssertEqual(events, [])
    }

    func testANewDictationWhileWaitingForTheKeysAbandonsPasteLast() async {
        await deliverOneDictation("A")
        let writesBefore = paste.writes
        await pasteLastWithTheShortcut()

        record()
        modifiersHeld = false
        await clock.advance(by: ModifierRelease.pollInterval)
        await controller.deliveries?.value

        XCTAssertEqual(paste.writes, writesBefore)
        XCTAssertEqual(controller.phase, .recording)
        controller.cancelRecording()
    }

    // MARK: - Paste Last with nothing kept says so (#60)

    func testPasteLastWithNothingKeptSaysThereIsNothingToPaste() {
        controller.pasteLastTranscript()

        XCTAssertEqual(events, ["cue \(DictationCue.nothingToPaste.symbolName)"])
        XCTAssertEqual(paste.writes, [])
        XCTAssertNil(controller.pasteLastRequest)
    }

    func testPasteLastAfterALockForgotTheTextSaysThereIsNothingToPaste() async {
        await deliverOneDictation("A")
        controller.forgetLastTranscript()
        let writesBefore = paste.writes

        controller.pasteLastTranscript()

        XCTAssertEqual(events, ["cue \(DictationCue.nothingToPaste.symbolName)"])
        XCTAssertEqual(paste.writes, writesBefore)
    }

    // The dictation in progress will paste its own text, so the request goes quietly.
    func testPasteLastDuringADictationStaysQuiet() {
        record()

        controller.pasteLastTranscript()

        XCTAssertEqual(events, [])
        controller.cancelRecording()
    }

    // MARK: - VoiceOver waits for the microphone (#17)

    private var voiceOver = true
    private var announced: [(text: String, microphoneRunning: Bool)] = []

    // Wired the way the app wires it, posting to a list instead of to VoiceOver.
    private func makeAnnouncer() -> DictationAnnouncer {
        DictationAnnouncer(
            controller: controller,
            isVoiceOverEnabled: { [unowned self] in voiceOver },
            post: { [unowned self] in announced.append(($0, input.isRunning)) }
        )
    }

    func testAResultArrivingDuringTheNextRecordingsTailIsAnnouncedOnlyOnceTheMicrophoneHasClosed() async {
        let announcer = makeAnnouncer()
        let first = await dictate(call: 0)
        record()
        controller.stopRecordingAndTranscribe()
        await clock.waitForSleeps(2)
        XCTAssertFalse(controller.isRecording)
        XCTAssertTrue(controller.isMicrophoneOpen)

        await engine.finish(0, with: "A")
        await first.value
        await controller.deliveries?.value
        XCTAssertEqual(paste.pastes, ["A"])
        XCTAssertTrue(announced.isEmpty)

        await clock.advance(by: tail)
        XCTAssertFalse(controller.isMicrophoneOpen)
        XCTAssertEqual(announced.map(\.text), ["Pasting text"])
        XCTAssertEqual(announced.map(\.microphoneRunning), [false])
        withExtendedLifetime(announcer) {}
    }

    // #63: said when the limit ends a recording, after the tail and before the result.
    func testTheLimitAnnouncementWaitsForTheTailAndComesBeforeTheResult() async {
        let announcer = makeAnnouncer()
        record()
        controller.stopRecordingAndTranscribe()
        announcer.announce(RecordingLimit.stopAnnouncement)
        XCTAssertTrue(announced.isEmpty)

        await clock.waitForSleeps(1)
        await clock.advance(by: tail)
        await engine.waitForCalls(1)
        XCTAssertEqual(announced.map(\.text), ["Recording stopped at the five-minute limit"])
        XCTAssertEqual(announced.map(\.microphoneRunning), [false])

        await engine.finish(0, with: "A")
        await controller.dictationJobs[1]?.value
        await controller.deliveries?.value
        XCTAssertEqual(announced.map(\.text), ["Recording stopped at the five-minute limit", "Pasting text"])
        withExtendedLifetime(announcer) {}
    }

    func testACueWhileTheMicrophoneIsClosedIsAnnouncedAtOnce() {
        let announcer = makeAnnouncer()

        announcer.announce("Nothing heard")

        XCTAssertEqual(announced.map(\.text), ["Nothing heard"])
    }

    func testWithoutVoiceOverAPasteIsNotAnnounced() async {
        voiceOver = false
        let announcer = makeAnnouncer()

        let job = await dictate(call: 0)
        await engine.finish(0, with: "A")
        await job.value
        await controller.deliveries?.value

        XCTAssertEqual(paste.pastes, ["A"])
        XCTAssertTrue(announced.isEmpty)
        withExtendedLifetime(announcer) {}
    }

    // MARK: - Keep last transcription (#40)

    func testWithTheSettingOffADictationIsPastedButNotKept() async {
        controller.keepsLastTranscript = false

        await deliverOneDictation("A")

        XCTAssertEqual(paste.pastes, ["A"])
        XCTAssertNil(controller.lastTranscript())
    }

    func testTurningTheSettingOffForgetsTheKeptText() async {
        await deliverOneDictation("A")
        XCTAssertEqual(controller.lastTranscript(), "A")

        controller.keepsLastTranscript = false

        XCTAssertNil(controller.lastTranscript())
    }

    func testADictationInFlightWhenTheSettingIsTurnedOffIsNotKept() async {
        let job = await dictate(call: 0)

        controller.keepsLastTranscript = false
        await engine.finish(0, with: "A")
        await job.value
        await clock.waitForSleeps(2)

        XCTAssertEqual(paste.pastes, ["A"])
        XCTAssertNil(controller.lastTranscript())
    }

    func testTurningTheSettingOffCancelsAPasteLastWaitingForTheKeys() async {
        await deliverOneDictation("A")
        let writesBefore = paste.writes
        await pasteLastWithTheShortcut()

        controller.keepsLastTranscript = false
        modifiersHeld = false
        await clock.advance(by: ModifierRelease.pollInterval)
        await controller.deliveries?.value

        XCTAssertEqual(paste.writes, writesBefore)
    }

    func testTurningTheSettingOffAndOnDoesNotBringBackAQueuedPasteLast() async {
        let job = await dictate(call: 0)
        await engine.finish(0, with: "A")
        await job.value
        await clock.waitForSleeps(2)
        await untilEnqueued { controller.pasteLastTranscript() }

        controller.keepsLastTranscript = false
        controller.keepsLastTranscript = true
        await clock.waitForSleeps(3)
        await clock.advance(by: settle)
        await controller.deliveries?.value

        XCTAssertEqual(paste.writes, ["A"])
        XCTAssertNil(controller.lastTranscript())
    }

    func testTurningTheSettingBackOnKeepsOnlyNewDictations() async {
        await deliverOneDictation("A")
        controller.keepsLastTranscript = false
        controller.keepsLastTranscript = true
        XCTAssertNil(controller.lastTranscript())

        let job = await dictate(call: 1)
        await engine.finish(1, with: "B")
        await job.value
        await clock.waitForSleeps(4)

        XCTAssertEqual(controller.lastTranscript(), "B")
        controller.forgetLastTranscript()
        XCTAssertNil(controller.lastTranscript())
    }

    // MARK: - Replaced on disk (#7)

    func testAfterSorlaIsReplacedADictationIsLeftOnTheClipboardAndKept() async {
        controller.isAppReplaced = { true }
        let job = await dictate(call: 0)
        await engine.finish(0, with: "A")
        await job.value
        await controller.deliveries?.value

        XCTAssertEqual(paste.events, ["write A"], "no ⌘V that macOS would drop")
        XCTAssertEqual(paste.lastWriteWasTransient, false)
        XCTAssertEqual(events, ["issue \(SorlaIssue.appReplaced.menuTitle)"])
        XCTAssertEqual(controller.lastTranscript(), "A")
        XCTAssertEqual(controller.phase, .idle)
    }

    func testPasteLastAfterSorlaIsReplacedLeavesTheTextOnTheClipboard() async {
        await deliverOneDictation("A")
        controller.isAppReplaced = { true }
        let issued = expectation(description: "issue")
        controller.onIssue = { [unowned self] in
            events.append("issue \($0.menuTitle)")
            issued.fulfill()
        }

        controller.pasteLastTranscript()
        await fulfillment(of: [issued], timeout: 5)

        XCTAssertEqual(paste.events, ["write A", "paste A", "restore", "write A"])
        XCTAssertEqual(events, ["issue \(SorlaIssue.appReplaced.menuTitle)"])
        XCTAssertEqual(controller.lastTranscript(), "A")
    }

    func testTheReplacementIsCheckedJustBeforeEachPaste() async {
        var checks = 0
        controller.isAppReplaced = { checks += 1; return false }
        await deliverOneDictation("A")

        XCTAssertEqual(checks, 1)
        XCTAssertEqual(paste.pastes, ["A"])
    }

    // MARK: - An update waits for everything in flight, not just the indicator (#29)

    func testTheActivityIsQuietOnlyOnceTheClipboardIsBack() async {
        XCTAssertTrue(controller.activity.isQuiet)

        record()
        XCTAssertTrue(controller.activity.isRecording)
        controller.stopRecordingAndTranscribe()
        XCTAssertTrue(controller.activity.isCapturingTail)
        XCTAssertFalse(controller.activity.isQuiet)

        await clock.waitForSleeps(1)
        await clock.advance(by: tail)
        await engine.waitForCalls(1)
        XCTAssertFalse(controller.activity.isCapturingTail)
        XCTAssertTrue(controller.activity.isTranscribing)

        await engine.finish(0, with: "A")
        await controller.dictationJobs[1]?.value
        await controller.deliveries?.value
        XCTAssertEqual(paste.pastes, ["A"])
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertEqual(controller.activity, DictationActivity(isRestoringClipboard: true))

        await clock.waitForSleeps(2)
        await clock.advance(by: settle)
        await controller.clipboardRestore?.value
        XCTAssertTrue(controller.activity.isQuiet)
    }

    func testAPasteLastWaitingForItsTurnIsActivity() async {
        let job = await dictate(call: 0)
        await engine.finish(0, with: "A")
        await job.value
        await controller.deliveries?.value

        await untilEnqueued { controller.pasteLastTranscript() }
        XCTAssertTrue(controller.activity.isPasteLastInFlight)
        XCTAssertEqual(controller.activity.pendingDeliveries, 1)

        await clock.waitForSleeps(3)
        await clock.advance(by: settle)
        await controller.deliveries?.value
        await clock.waitForSleeps(4)
        await clock.advance(by: settle)
        await controller.clipboardRestore?.value
        await controller.pasteLastRequest?.value
        XCTAssertEqual(paste.pastes, ["A", "A"])
        XCTAssertTrue(controller.activity.isQuiet)
    }

    func testEachPartOfTheActivityKeepsItFromBeingQuiet() {
        XCTAssertTrue(DictationActivity.quiet.isQuiet)
        XCTAssertFalse(DictationActivity(isRecording: true).isQuiet)
        XCTAssertFalse(DictationActivity(isCapturingTail: true).isQuiet)
        XCTAssertFalse(DictationActivity(isTranscribing: true).isQuiet)
        XCTAssertFalse(DictationActivity(pendingDeliveries: 1).isQuiet)
        XCTAssertFalse(DictationActivity(isPasteLastInFlight: true).isQuiet)
        XCTAssertFalse(DictationActivity(isRestoringClipboard: true).isQuiet)
    }
}
