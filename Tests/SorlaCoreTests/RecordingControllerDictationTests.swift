import XCTest
@testable import SorlaCore

@MainActor
final class RecordingControllerDictationTests: XCTestCase {
    private let clock = TestClock()
    private let input = FakeAudioInput()
    private let resampler = FakeResampler()
    private let engine = HeldTranscriptionEngine()
    private var controller: RecordingController!

    override func setUp() async throws {
        let clock = self.clock
        controller = RecordingController(
            engine: engine,
            modelName: "test",
            inputDeviceState: SilentInputDevice(),
            recorder: AudioRecorder(input: input, resampler: resampler),
            isMicrophoneAccessDenied: { false },
            sleep: { await clock.sleep(for: $0) }
        )
    }

    // One second of audio, well over the model's minimum.
    private func record() {
        XCTAssertTrue(controller.startRecording())
        for _ in 0..<16 { input.feed(count: 1_000) }
    }

    private var tail: Duration { .seconds(controller.tailDuration) }

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
        await clock.waitForSleeps(1)

        await clock.advance(by: tail)

        XCTAssertEqual(controller.recorder.heldSampleCount, 0)
        XCTAssertEqual(controller.phase, .idle)
    }
}
