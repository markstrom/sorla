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

    override func setUp() async throws {
        calls = CallLog()
        session = FakeAudioSession(calls: calls)
        input = FakeAudioInput(calls: calls)
        center = NotificationCenter()
        clock = ManualClock()
        diagnostics = []
        captureEnds = []
        let clock = self.clock!
        recorder = LiveDictationRecorder(
            session: session,
            input: input,
            resample: { samples, _ in samples },
            center: center,
            now: { clock.now },
            onMain: { job in MainActor.assumeIsolated(job) }
        )
        recorder.onDiagnostic = { [weak self] in self?.diagnostics.append($0) }
        recorder.onCaptureEnded = { [weak self] in self?.captureEnds.append($0) }
    }

    // MARK: Session

    func testTheDictationSessionIsMixableSoItCanBeActivatedFromTheBackground() {
        let configuration = DictationSessionConfiguration.dictation
        XCTAssertEqual(configuration.category, .playAndRecord)
        XCTAssertEqual(configuration.mode, .default)
        XCTAssertTrue(configuration.options.contains(.mixWithOthers))
        XCTAssertTrue(configuration.options.contains(.allowBluetoothHFP))
    }

    func testStartConfiguresAndActivatesTheSessionBeforeMakingTheEngine() throws {
        try recorder.start()

        XCTAssertEqual(calls.entries, ["configure", "activate", "prepareInput", "startInput"])
        XCTAssertEqual(session.configurations, [.dictation])
        XCTAssertTrue(session.isActive)
    }

    func testStartLogsTheSessionSetup() throws {
        try recorder.start()

        XCTAssertEqual(diagnostics, [
            "session: category playAndRecord, mode default, options mixWithOthers+allowBluetoothHFP, input MicrophoneBuiltIn, 48000 Hz, 1 ch",
        ])
    }

    func testARefusedActivationNeverOpensTheMicrophoneButStillLogsTheSession() {
        session.activationError = NSError(domain: NSOSStatusErrorDomain, code: 560_557_684)

        XCTAssertThrowsError(try recorder.start())

        XCTAssertEqual(input.prepares, 0)
        XCTAssertFalse(input.isRunning)
        XCTAssertEqual(calls.entries, ["configure", "activate", "deactivate"])
        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertTrue(diagnostics[0].hasPrefix("session: "))
    }

    func testAnInputThatFailsToStartDeactivatesTheSession() {
        input.prepareError = AudioRecorderError.noInputDevice

        XCTAssertThrowsError(try recorder.start())

        XCTAssertFalse(session.isActive)
        XCTAssertEqual(diagnostics.count, 1)
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
            inputPort: nil, sampleRate: 44_100, inputChannels: 0
        )
        XCTAssertEqual(
            snapshot.summary,
            "category record, mode measurement, options duckOthers+0x40000000, input none, 44100 Hz, 0 ch"
        )
        XCTAssertEqual(AudioSessionSnapshot.names(of: []), "none")
    }

    // MARK: A dead input

    func testASilentFirstSecondStartsOverOnANewEngineAndDropsTheSilence() throws {
        try recorder.start()

        input.deliver(seconds: 1, level: 0)

        XCTAssertEqual(input.prepares, 2)
        XCTAssertTrue(input.isRunning)
        XCTAssertEqual(diagnostics.last, "audioRestart: first second silent, started over on a new engine")
        input.deliver(seconds: 0.5, level: 0.3)
        XCTAssertEqual(try recorder.stop(), Array(repeating: 0.3, count: 8_000))
    }

    func testAQuietButRealFirstSecondIsLeftAlone() throws {
        try recorder.start()

        input.deliver(seconds: 1, level: 0.001)

        XCTAssertEqual(input.prepares, 1)
        XCTAssertEqual(try recorder.stop().count, 16_000)
    }

    func testAnInputThatStaysSilentIsStartedOverOnlyAFewTimes() throws {
        try recorder.start()

        for _ in 0..<6 {
            input.deliver(seconds: 1, level: 0)
        }

        XCTAssertEqual(input.prepares, 1 + LiveDictationRecorder.maximumRestarts)
        // What is left is silence, which the coordinator reports as `failed.silentInput`.
        let samples = try recorder.stop()
        XCTAssertEqual(SpeechCheck.assess(samples), .silentInput)
    }

    func testEveryRecordingGetsANewEngine() throws {
        try recorder.start()
        _ = try recorder.stop()
        try recorder.start()

        XCTAssertEqual(input.prepares, 2)
    }

    // MARK: Configuration changes, interruptions, background

    func testAConfigurationChangeAfterSpeechCarriesOnAndKeepsTheAudio() throws {
        try recorder.start()
        input.deliver(seconds: 0.5, level: 0.3)

        center.post(name: .AVAudioEngineConfigurationChange, object: nil)
        input.deliver(seconds: 0.5, level: 0.2)

        XCTAssertEqual(input.restarts, 1)
        XCTAssertEqual(captureEnds, [])
        XCTAssertEqual(diagnostics.last, "audioRestart: configuration change, continued on a new engine")
        XCTAssertEqual(try recorder.stop().count, 16_000)
    }

    func testAConfigurationChangeThatCantCarryOnEndsCaptureAndKeepsTheAudio() throws {
        input.restartSucceeds = false
        try recorder.start()
        input.deliver(seconds: 0.5, level: 0.3)

        center.post(name: .AVAudioEngineConfigurationChange, object: nil)

        XCTAssertEqual(captureEnds, [.routeChanged])
        XCTAssertEqual(try recorder.stop().count, 8_000)
    }

    func testAConfigurationChangeBeforeAnythingWasHeardStartsOver() throws {
        try recorder.start()

        center.post(name: .AVAudioEngineConfigurationChange, object: nil)

        XCTAssertEqual(input.prepares, 2)
        XCTAssertEqual(input.restarts, 0)
        XCTAssertEqual(captureEnds, [])
    }

    func testAnInterruptionEndsCapture() throws {
        try recorder.start()

        postInterruption(.ended)
        XCTAssertEqual(captureEnds, [])
        postInterruption(.began)

        XCTAssertEqual(captureEnds, [.interrupted])
    }

    func testAMediaServicesResetEndsCapture() throws {
        try recorder.start()

        center.post(name: AVAudioSession.mediaServicesWereResetNotification, object: nil)

        XCTAssertEqual(captureEnds, [.interrupted])
        XCTAssertEqual(diagnostics.last, "audioRestart: media services were reset")
    }

    func testGoingToTheBackgroundIsLoggedWithTheLevelSoFar() throws {
        try recorder.start()
        input.deliver(seconds: 0.5, level: 0.5)
        clock.advance(by: .milliseconds(4_200))

        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        XCTAssertEqual(diagnostics.last, "background: after 4.2 s listening, peak so far -6.0 dBFS")
    }

    func testNothingIsObservedAfterStop() throws {
        try recorder.start()
        _ = try recorder.stop()

        postInterruption(.began)
        center.post(name: .AVAudioEngineConfigurationChange, object: nil)
        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        XCTAssertEqual(captureEnds, [])
        XCTAssertEqual(input.prepares, 1)
        XCTAssertEqual(diagnostics.count, 1)
    }

    private func postInterruption(_ type: AVAudioSession.InterruptionType) {
        center.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: type.rawValue]
        )
    }
}
