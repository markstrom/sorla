import AVFoundation
import UIKit
import XCTest
@testable import Sorla

@MainActor
final class LiveDictationRecorderTests: XCTestCase {
    private var calls: CallLog!
    private var session: FakeAudioSession!
    private var input: FakeAudioInput!
    private var center: NotificationCenter!
    private var clock: ManualClock!
    private var recorder: LiveDictationRecorder!
    private var diagnostics: [String] = []
    private var captureEnds: [CaptureEnd] = []
    private var isInForeground = true
    // Jobs the recorder asked to run after a delay; a test runs them when it chooses, so nothing waits on time.
    private var delayed: [(delay: Duration, job: @MainActor () -> Void)] = []

    override func setUp() async throws {
        calls = CallLog()
        session = FakeAudioSession(calls: calls)
        input = FakeAudioInput(calls: calls)
        center = NotificationCenter()
        clock = ManualClock()
        diagnostics = []
        captureEnds = []
        isInForeground = true
        delayed = []
        let clock = self.clock!
        recorder = LiveDictationRecorder(
            session: session,
            input: input,
            resample: { samples, _ in samples },
            center: center,
            now: { clock.now },
            isInForeground: { [unowned self] in self.isInForeground },
            onMain: { job in MainActor.assumeIsolated(job) },
            after: { [unowned self] delay, job in self.delayed.append((delay, job)) }
        )
        recorder.onDiagnostic = { [weak self] in self?.diagnostics.append($0) }
        recorder.onCaptureEnded = { [weak self] in self?.captureEnds.append($0) }
    }

    // MARK: Session

    func testTheDictationSessionIsTheNonMixableRecordSessionThatCapturedSpeech() {
        let configuration = DictationSessionConfiguration.dictation
        XCTAssertEqual(configuration.category, .record)
        XCTAssertEqual(configuration.mode, .default)
        XCTAssertEqual(configuration.options, [.allowBluetoothHFP])
        XCTAssertFalse(configuration.options.contains(.mixWithOthers))
    }

    func testStartConfiguresAndActivatesTheSessionBeforeTouchingTheEngine() throws {
        try recorder.start()

        XCTAssertEqual(calls.entries, ["configure", "activate", "prepareInput", "startInput"])
        XCTAssertEqual(session.configurations, [.dictation])
        XCTAssertTrue(session.isActive)
    }

    func testStartLogsTheSessionAndTheEngine() throws {
        try recorder.start()

        XCTAssertEqual(diagnostics, [
            "session: category record, mode default, options allowBluetoothHFP, input MicrophoneBuiltIn, 48000 Hz, 1 ch, input available yes, other audio no",
            "engine: engine 1, 16000 Hz",
        ])
    }

    func testARefusedActivationNeverOpensTheMicrophoneButStillLogsTheSession() {
        session.activationError = NSError(domain: NSOSStatusErrorDomain, code: 560_557_684)

        XCTAssertThrowsError(try recorder.start())

        XCTAssertEqual(input.enginesMade, 0)
        XCTAssertFalse(input.isRunning)
        XCTAssertEqual(calls.entries, ["configure", "activate", "deactivate"])
        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertTrue(diagnostics[0].hasPrefix("session: "))
    }

    func testAnInputThatFailsToStartDeactivatesTheSessionAndLogsTheEngine() {
        input.prepareError = AudioRecorderError.noInputDevice

        XCTAssertThrowsError(try recorder.start())

        XCTAssertFalse(session.isActive)
        XCTAssertEqual(diagnostics.count, 2)
        XCTAssertTrue(diagnostics[1].hasPrefix("engine: "))
    }

    func testStopReturnsTheAudioAndDeactivatesTheSession() throws {
        try recorder.start()
        input.deliver(seconds: 0.5, level: 0.3)

        let samples = try recorder.stop()

        XCTAssertEqual(samples.count, 8_000)
        XCTAssertFalse(input.isRunning)
        XCTAssertFalse(session.isActive)
    }

    func testCancelDropsTheAudioAndDeactivatesTheSession() throws {
        try recorder.start()
        input.deliver(seconds: 0.5, level: 0.3)

        recorder.cancel()

        XCTAssertFalse(input.isRunning)
        XCTAssertFalse(session.isActive)
    }

    func testTheSnapshotNamesUnknownOptionsAndAMissingInput() {
        let snapshot = AudioSessionSnapshot(
            category: .record, mode: .measurement, options: [.duckOthers, .init(rawValue: 0x4000_0000)],
            inputPort: nil, sampleRate: 44_100, inputChannels: 0, isInputAvailable: false, isOtherAudioPlaying: true
        )
        XCTAssertEqual(
            snapshot.summary,
            "category record, mode measurement, options duckOthers+0x40000000, input none, 44100 Hz, 0 ch, "
                + "input available no, other audio yes"
        )
        XCTAssertEqual(AudioSessionSnapshot.names(of: []), "none")
    }

    // MARK: One engine

    func testOneEngineServesEveryRecording() throws {
        try recorder.start()
        _ = try recorder.stop()
        try recorder.start()
        recorder.cancel()
        try recorder.start()

        XCTAssertEqual(input.enginesMade, 1)
        XCTAssertEqual(input.prepares, 3)
    }

    func testAnInputRouteAppearingAfterActivationRestartsNothing() throws {
        try recorder.start()
        center.post(
            name: AVAudioSession.routeChangeNotification, object: nil,
            userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.categoryChange.rawValue]
        )
        input.deliver(seconds: 0.5, level: 0.3)

        XCTAssertEqual(input.prepares, 1)
        XCTAssertEqual(diagnostics.count, 2)
        XCTAssertEqual(try recorder.stop().count, 8_000)
    }

    // MARK: A silent start

    func testASilentFirstSecondStopsTheEngineAndRestartsSessionAndANewEngineAfterAPause() throws {
        try recorder.start()
        calls.clear()
        clock.advance(by: .milliseconds(1_000))

        input.deliver(seconds: 1, level: 0)

        XCTAssertEqual(calls.entries, ["deactivate"])
        XCTAssertFalse(input.isRunning)
        XCTAssertEqual(input.discards, 1)
        XCTAssertEqual(delayed.map(\.delay), [.milliseconds(200)])
        XCTAssertEqual(diagnostics.last, "audioRestart: silent for 1.0 s, 1000 ms after the start, restart 1 of 3 in 200 ms")

        clock.advance(by: .milliseconds(200))
        runDelayed()

        XCTAssertEqual(calls.entries, ["deactivate", "configure", "activate", "prepareInput", "startInput"])
        XCTAssertEqual(input.enginesMade, 2)
        XCTAssertTrue(input.isRunning)
        XCTAssertTrue(session.isActive)
        XCTAssertTrue(diagnostics[diagnostics.count - 2].hasPrefix("session: "))
        XCTAssertEqual(diagnostics.last, "audioRestart: restart 1, session and a new engine started 1200 ms after the start (engine 2, 16000 Hz)")
    }

    func testSoundAfterARestartIsKeptWithoutTheSilenceAndLogged() throws {
        try recorder.start()
        input.deliver(seconds: 1, level: 0)
        clock.advance(by: .milliseconds(1_700))
        runDelayed()

        input.deliver(seconds: 0.5, level: 0.3)

        XCTAssertEqual(diagnostics.last, "audioRestart: sound after restart 1, 1700 ms after the start")
        XCTAssertEqual(try recorder.stop(), Array(repeating: 0.3, count: 8_000))
    }

    func testASilentInputIsRestartedUpToThreeTimesSpacedFurtherApart() throws {
        try recorder.start()

        input.deliver(seconds: 1, level: 0)
        runDelayed()
        input.deliver(seconds: 0.5, level: 0)
        runDelayed()
        input.deliver(seconds: 0.5, level: 0)
        runDelayed()

        XCTAssertEqual(input.enginesMade, 4)
        XCTAssertEqual(input.discards, 3)
        XCTAssertTrue(input.isRunning)
        XCTAssertEqual(
            diagnostics.filter { $0.contains(" in ") && $0.hasPrefix("audioRestart: silent") }.map { $0.components(separatedBy: ", ").last! },
            ["restart 1 of 3 in 200 ms", "restart 2 of 3 in 400 ms", "restart 3 of 3 in 600 ms"]
        )
    }

    func testSoundOnTheLastRestartIsStillKept() throws {
        try recorder.start()
        input.deliver(seconds: 1, level: 0)
        runDelayed()
        input.deliver(seconds: 0.5, level: 0)
        runDelayed()
        input.deliver(seconds: 0.5, level: 0)
        runDelayed()

        input.deliver(seconds: 1, level: 0.2)

        XCTAssertEqual(diagnostics.last, "audioRestart: sound after restart 3, 0 ms after the start")
        XCTAssertEqual(try recorder.stop(), Array(repeating: 0.2, count: 16_000))
    }

    func testAnInputThatStaysSilentAfterEveryRestartEndsAsSilentInput() throws {
        try recorder.start()
        input.deliver(seconds: 1, level: 0)
        runDelayed()
        input.deliver(seconds: 0.5, level: 0)
        runDelayed()
        input.deliver(seconds: 0.5, level: 0)
        runDelayed()

        input.deliver(seconds: 0.5, level: 0)
        input.deliver(seconds: 3, level: 0)

        XCTAssertEqual(input.enginesMade, 4)
        XCTAssertTrue(delayed.isEmpty)
        XCTAssertEqual(diagnostics.last, "audioRestart: silent for 0.5 s after restart 3, 0 ms after the start, not restarted again")
        // The dropped silence (1 + 0.5 + 0.5 s) comes back with the rest, so the stop sees all of it as silence.
        let samples = try recorder.stop()
        XCTAssertEqual(samples.count, 88_000)
        XCTAssertEqual(SpeechCheck.assess(samples), .silentInput)
    }

    func testAStopDuringThePauseStillReportsTheSilenceAndNeverRestarts() throws {
        try recorder.start()
        input.deliver(seconds: 1, level: 0)

        let samples = try recorder.stop()
        runDelayed()

        XCTAssertEqual(samples.count, 16_000)
        XCTAssertEqual(SpeechCheck.assess(samples), .silentInput)
        XCTAssertEqual(input.enginesMade, 1)
        XCTAssertFalse(input.isRunning)
        XCTAssertFalse(session.isActive)
    }

    func testACancelDuringThePauseLeavesNothingToRestart() throws {
        try recorder.start()
        input.deliver(seconds: 1, level: 0)

        recorder.cancel()
        runDelayed()

        XCTAssertFalse(input.isRunning)
        XCTAssertFalse(session.isActive)
        try recorder.start()
        XCTAssertEqual(try recorder.stop(), [])
    }

    func testAPendingRestartFromAnEarlierRecordingNeverTouchesTheNextOne() throws {
        try recorder.start()
        input.deliver(seconds: 1, level: 0)
        _ = try recorder.stop()
        try recorder.start()
        calls.clear()

        runDelayed()

        XCTAssertEqual(calls.entries, [])
        XCTAssertEqual(input.prepares, 2)
    }

    func testAQuietButRealFirstSecondIsLeftAlone() throws {
        try recorder.start()

        input.deliver(seconds: 1, level: 0.001)

        XCTAssertEqual(input.prepares, 1)
        XCTAssertTrue(delayed.isEmpty)
        XCTAssertEqual(try recorder.stop().count, 16_000)
    }

    func testASilentFirstSecondInTheBackgroundIsOnlyLogged() throws {
        try recorder.start()
        isInForeground = false

        input.deliver(seconds: 1, level: 0)

        XCTAssertEqual(input.prepares, 1)
        XCTAssertTrue(delayed.isEmpty)
        XCTAssertTrue(session.isActive)
        XCTAssertEqual(diagnostics.last, "audioRestart: silent for 1.0 s, in the background, not restarted")
        XCTAssertEqual(try recorder.stop().count, 16_000)
    }

    func testGoingToTheBackgroundDuringThePauseEndsCaptureAsSilence() throws {
        try recorder.start()
        input.deliver(seconds: 1, level: 0)
        isInForeground = false

        runDelayed()

        XCTAssertEqual(captureEnds, [.interrupted])
        XCTAssertEqual(diagnostics.last, "audioRestart: in the background before restart 1, capture ended")
        XCTAssertEqual(SpeechCheck.assess(try recorder.stop()), .silentInput)
    }

    func testAFailedRestartEndsCapture() throws {
        try recorder.start()
        session.activationError = NSError(domain: NSOSStatusErrorDomain, code: 560_557_684)

        input.deliver(seconds: 1, level: 0)
        runDelayed()

        XCTAssertEqual(captureEnds, [.interrupted])
        XCTAssertTrue(diagnostics.last?.hasPrefix("audioRestart: restart 1 failed: ") ?? false)
    }

    func testAConfigurationChangeDuringThePauseIsIgnored() throws {
        try recorder.start()
        input.deliver(seconds: 1, level: 0)

        center.post(name: .AVAudioEngineConfigurationChange, object: nil)

        XCTAssertEqual(input.resumes, 0)
        XCTAssertEqual(captureEnds, [])
        runDelayed()
        XCTAssertTrue(input.isRunning)
    }

    func testEveryRecordingGetsItsOwnRestarts() throws {
        try recorder.start()
        input.deliver(seconds: 1, level: 0)
        runDelayed()
        input.deliver(seconds: 0.5, level: 0)
        runDelayed()
        input.deliver(seconds: 0.5, level: 0)
        runDelayed()
        _ = try recorder.stop()
        try recorder.start()

        input.deliver(seconds: 1, level: 0)

        XCTAssertEqual(delayed.map(\.delay), [.milliseconds(200)])
    }

    func testTheFirstWindowOfEveryRecordingIsAWholeSecond() throws {
        try recorder.start()
        input.deliver(seconds: 1, level: 0)
        runDelayed()
        input.deliver(seconds: 0.2, level: 0.3)
        _ = try recorder.stop()
        try recorder.start()

        input.deliver(seconds: 0.5, level: 0)

        XCTAssertTrue(delayed.isEmpty)
    }

    // MARK: Configuration changes, interruptions, background

    func testAConfigurationChangeAtTheSameRateCarriesOnOnTheSameEngineAndKeepsTheAudio() throws {
        try recorder.start()
        input.deliver(seconds: 0.5, level: 0.3)

        center.post(name: .AVAudioEngineConfigurationChange, object: nil)
        input.deliver(seconds: 0.5, level: 0.2)

        XCTAssertEqual(input.resumes, 1)
        XCTAssertEqual(input.enginesMade, 1)
        XCTAssertEqual(captureEnds, [])
        XCTAssertEqual(diagnostics.last, "audioRestart: configuration change, continued (engine 1, 16000 Hz)")
        XCTAssertEqual(try recorder.stop().count, 16_000)
    }

    func testAConfigurationChangeBeforeAnythingWasHeardCarriesOnToo() throws {
        try recorder.start()

        center.post(name: .AVAudioEngineConfigurationChange, object: nil)

        XCTAssertEqual(input.resumes, 1)
        XCTAssertEqual(input.prepares, 1)
        XCTAssertTrue(input.isRunning)
    }

    func testANewRateBeforeAnythingWasHeardStartsOverAtThatRate() throws {
        try recorder.start()
        input.deliver(seconds: 0.5, level: 0)
        input.sampleRate = 24_000

        center.post(name: .AVAudioEngineConfigurationChange, object: nil)
        input.deliver(seconds: 0.5, level: 0.3)

        XCTAssertEqual(captureEnds, [])
        XCTAssertEqual(input.prepares, 2)
        XCTAssertEqual(diagnostics.last, "audioRestart: configuration change, new rate, nothing heard yet, started over (engine 1, 24000 Hz)")
        XCTAssertEqual(try recorder.stop(), Array(repeating: 0.3, count: 12_000))
    }

    func testANewRateAfterSpeechEndsCaptureAndKeepsTheAudio() throws {
        try recorder.start()
        input.deliver(seconds: 0.5, level: 0.3)
        input.sampleRate = 24_000

        center.post(name: .AVAudioEngineConfigurationChange, object: nil)

        XCTAssertEqual(captureEnds, [.routeChanged])
        XCTAssertEqual(try recorder.stop().count, 8_000)
    }

    func testAnInputThatCantCarryOnEndsCaptureAndKeepsTheAudio() throws {
        input.resumeFails = true
        try recorder.start()
        input.deliver(seconds: 0.5, level: 0.3)

        center.post(name: .AVAudioEngineConfigurationChange, object: nil)

        XCTAssertEqual(captureEnds, [.routeChanged])
        XCTAssertEqual(diagnostics.last, "audioRestart: configuration change, input could not continue: test")
        XCTAssertEqual(try recorder.stop().count, 8_000)
    }

    func testConfigurationChangesAreFollowedOnlyAFewTimesPerRecording() throws {
        try recorder.start()
        input.deliver(seconds: 0.5, level: 0.3)

        for _ in 0...LiveDictationRecorder.maximumResumes {
            center.post(name: .AVAudioEngineConfigurationChange, object: nil)
        }

        XCTAssertEqual(input.resumes, LiveDictationRecorder.maximumResumes)
        XCTAssertEqual(captureEnds, [.routeChanged])
    }

    func testAnInterruptionEndsCapture() throws {
        try recorder.start()

        postInterruption(.ended)
        XCTAssertEqual(captureEnds, [])
        postInterruption(.began)

        XCTAssertEqual(captureEnds, [.interrupted])
    }

    func testAMediaServicesResetEndsCaptureAndTheNextRecordingGetsANewEngine() throws {
        try recorder.start()

        center.post(name: AVAudioSession.mediaServicesWereResetNotification, object: nil)

        XCTAssertEqual(captureEnds, [.interrupted])
        XCTAssertEqual(diagnostics.last, "audioRestart: media services were reset, capture ended")
        _ = try recorder.stop()
        try recorder.start()
        XCTAssertEqual(input.enginesMade, 2)
    }

    func testAMediaServicesResetBetweenRecordingsDropsTheEngineQuietly() throws {
        try recorder.start()
        _ = try recorder.stop()

        center.post(name: AVAudioSession.mediaServicesWereResetNotification, object: nil)

        XCTAssertEqual(input.discards, 1)
        XCTAssertEqual(captureEnds, [])
        XCTAssertEqual(diagnostics.count, 2)
        try recorder.start()
        XCTAssertEqual(input.enginesMade, 2)
    }

    func testGoingToTheBackgroundIsLoggedWithTheLevelSoFarAndCaptureGoesOn() throws {
        try recorder.start()
        input.deliver(seconds: 0.5, level: 0.5)
        clock.advance(by: .milliseconds(4_200))

        isInForeground = false
        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        input.deliver(seconds: 0.5, level: 0.2)

        XCTAssertEqual(diagnostics.last, "background: after 4.2 s listening, peak so far -6.0 dBFS")
        XCTAssertTrue(input.isRunning)
        XCTAssertTrue(session.isActive)
        XCTAssertEqual(captureEnds, [])
        XCTAssertEqual(try recorder.stop().count, 16_000)
    }

    func testNothingIsObservedAfterStop() throws {
        try recorder.start()
        _ = try recorder.stop()

        postInterruption(.began)
        center.post(name: .AVAudioEngineConfigurationChange, object: nil)
        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        XCTAssertEqual(captureEnds, [])
        XCTAssertEqual(input.resumes, 0)
        XCTAssertEqual(diagnostics.count, 2)
    }

    private func runDelayed() {
        let jobs = delayed
        delayed = []
        jobs.forEach { $0.job() }
    }

    private func postInterruption(_ type: AVAudioSession.InterruptionType) {
        center.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: type.rawValue]
        )
    }
}
