import XCTest
@testable import SorlaCore

@MainActor
final class RecordingControllerDictationTests: XCTestCase {
    private let clock = TestClock()
    private let input = FakeAudioInput()
    private let resampler = FakeResampler()
    private let engine = HeldTranscriptionEngine()
    private let paste = FakePasteEnvironment()
    private var controller: RecordingController!
    private var events: [String] = []

    override func setUp() async throws {
        let clock = self.clock
        controller = RecordingController(
            engine: engine,
            modelName: "test",
            inputDeviceState: SilentInputDevice(),
            recorder: AudioRecorder(input: input, resampler: resampler),
            pasteEnvironment: paste,
            isMicrophoneAccessDenied: { false },
            sleep: { await clock.sleep(for: $0) }
        )
        controller.onCue = { [unowned self] in events.append("cue \($0.symbolName)") }
        controller.onIssue = { [unowned self] in events.append("issue \($0.menuTitle)") }
        controller.onPaste = { [unowned self] in events.append("pasted \(paste.contents ?? "")") }
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
        await clock.waitForSleeps(3)
        XCTAssertEqual(paste.pastes, ["A"])
        // B isn't written while A's ⌘V may still be waiting to be handled.
        XCTAssertEqual(paste.writes, ["A"])
        XCTAssertEqual(controller.lastTranscript(), "A")

        await clock.advance(by: settle)
        await clock.waitForSleeps(4)
        XCTAssertEqual(paste.pastes, ["A", "B"])
        XCTAssertEqual(controller.lastTranscript(), "B")

        await clock.advance(by: settle)
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
        await clock.advance(by: settle)
        await controller.deliveries?.value
        XCTAssertEqual(paste.writes, ["B"])
        XCTAssertEqual(controller.lastTranscript(), "B")
        XCTAssertEqual(controller.phase, .idle)
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

    func testPasteLastWaitsUntilTheDictationsPasteHasLanded() async {
        let first = await dictate(call: 0)
        await engine.finish(0, with: "A")
        await first.value
        await clock.waitForSleeps(2)
        XCTAssertEqual(controller.phase, .idle)

        controller.pasteLastTranscript()
        // Lets the request run as far as it can on the main actor before the clock moves.
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(paste.writes, ["A"])
        await clock.advance(by: settle)
        await clock.waitForSleeps(3)
        await clock.advance(by: settle)
        await controller.deliveries?.value

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
        XCTAssertEqual(paste.writes, ["A"])
        await clock.advance(by: settle)
        await clock.waitForSleeps(4)
        await clock.advance(by: settle)
        await controller.deliveries?.value

        XCTAssertEqual(paste.events, ["write A", "paste A", "write B", "paste B"])
    }

    // MARK: - Paste Last waits for the shortcut's keys (#11)

    private var modifiersHeld = true

    private func deliverOneDictation(_ text: String) async {
        let job = await dictate(call: 0)
        await engine.finish(0, with: text)
        await job.value
        await clock.waitForSleeps(2)
        await clock.advance(by: settle)
        await controller.deliveries?.value
        events = []
    }

    // Sleeps 1 and 2 were the dictation's tail and settle; the first poll for the keys is sleep 3.
    private func pasteLastWithTheShortcut() async {
        let clock = self.clock
        controller.pasteLastTranscript(after: {
            await ModifierRelease.wait(
                isHeld: { [unowned self] in self.modifiersHeld },
                now: { clock.now },
                sleep: { await clock.sleep(for: $0) }
            )
        })
        await clock.waitForSleeps(3)
    }

    func testPasteLastPastesOnceTheShortcutsKeysAreLetGo() async {
        await deliverOneDictation("A")
        await pasteLastWithTheShortcut()

        modifiersHeld = false
        await clock.advance(by: ModifierRelease.pollInterval)
        await clock.waitForSleeps(4)
        XCTAssertEqual(paste.pastes, ["A", "A"])

        await clock.advance(by: settle)
        await controller.deliveries?.value
    }

    func testPasteLastHeldPastTheDeadlineLeavesTheTextOnTheClipboard() async {
        await deliverOneDictation("A")
        await pasteLastWithTheShortcut()

        for poll in 0..<50 {
            await clock.waitForSleeps(3 + poll)
            await clock.advance(by: ModifierRelease.pollInterval)
        }
        await controller.deliveries?.value

        XCTAssertEqual(paste.pastes, ["A"])
        XCTAssertEqual(paste.contents, "A")
        XCTAssertEqual(events, ["cue \(DictationCue.textOnClipboard.symbolName)"])
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
}
