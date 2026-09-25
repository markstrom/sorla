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
    private var recorder: LiveDictationRecorder!
    private var diagnostics: [String] = []
    private var captureEnds: [CaptureEnd] = []

    override func setUp() async throws {
        calls = CallLog()
        session = FakeAudioSession(calls: calls)
        input = FakeAudioInput(calls: calls)
        center = NotificationCenter()
        diagnostics = []
        captureEnds = []
        recorder = LiveDictationRecorder(
            session: session,
            input: input,
            resample: { samples, _ in samples },
            center: center
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

    func testAnInterruptionEndsCapture() throws {
        try recorder.start()

        postInterruption(.ended)
        XCTAssertEqual(captureEnds, [])
        postInterruption(.began)

        XCTAssertEqual(captureEnds, [.interrupted])
    }

    private func postInterruption(_ type: AVAudioSession.InterruptionType) {
        center.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: type.rawValue]
        )
    }
}
