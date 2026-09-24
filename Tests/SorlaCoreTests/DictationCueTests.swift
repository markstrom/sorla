import XCTest
@testable import SorlaCore

final class DictationCueTests: XCTestCase {
    func testEachCueHasItsOwnSymbol() {
        let cues: [DictationCue] = [.microphoneMuted, .nothingHeard, .noText, .textOnClipboard, .waitingForModel(""), .failed("")]
        XCTAssertEqual(cues.map(\.symbolName), ["mic.slash", "waveform.slash", "minus", "doc.on.clipboard", "hourglass", "exclamationmark.triangle"])
    }

    func testAnnouncementsAreShort() {
        XCTAssertEqual(DictationCue.microphoneMuted.announcement(pasteShortcut: nil), "Microphone seems to be muted")
        XCTAssertEqual(DictationCue.nothingHeard.announcement(pasteShortcut: nil), "Nothing heard")
        XCTAssertEqual(DictationCue.noText.announcement(pasteShortcut: nil), "No text")
    }

    func testTheClipboardCueNamesThePasteLastShortcutOrFallsBackToCommandV() {
        XCTAssertEqual(DictationCue.textOnClipboard.announcement(pasteShortcut: "⌃⌥V"), "Your text is on the clipboard — press ⌃⌥V")
        XCTAssertEqual(DictationCue.textOnClipboard.announcement(pasteShortcut: nil), "Your text is on the clipboard — press ⌘V")
    }

    func testOnlyCuesTheUserMustActOnLeaveAMenuExplanation() {
        XCTAssertEqual(DictationCue.microphoneMuted.issue(pasteShortcut: nil), .microphoneMuted)
        XCTAssertEqual(DictationCue.textOnClipboard.issue(pasteShortcut: "⌃⌥V"), .textOnClipboard(pasteShortcut: "⌃⌥V"))
        XCTAssertEqual(DictationCue.textOnClipboard.issue(pasteShortcut: nil), .textOnClipboard(pasteShortcut: "⌘V"))
        XCTAssertNil(DictationCue.nothingHeard.issue(pasteShortcut: nil))
        XCTAssertNil(DictationCue.noText.issue(pasteShortcut: nil))
        XCTAssertNil(DictationCue.waitingForModel("x").issue(pasteShortcut: nil))
        XCTAssertNil(DictationCue.failed("x").issue(pasteShortcut: nil))
    }

    func testMenuWording() {
        XCTAssertEqual(SorlaIssue.microphoneMuted.menuTitle, "Microphone seems to be muted — check Sound › Input")
        XCTAssertEqual(SorlaIssue.textOnClipboard(pasteShortcut: "⌃⌥V").menuTitle, "Text is on the clipboard — press ⌃⌥V")
    }

    func testFailedStartsAndFinishesShowAWarningCue() {
        XCTAssertEqual(DictationCue(issue: .microphoneAccessNeeded), .failed("Microphone access needed"))
        XCTAssertEqual(DictationCue(issue: .noInputDevice), .failed("No microphone found"))
        XCTAssertEqual(DictationCue(issue: .transcriptionFailed), .failed("Couldn't transcribe the recording"))
        XCTAssertEqual(DictationCue(issue: .noInputDevice)?.symbolName, "exclamationmark.triangle")
    }

    func testMissingAccessibilityShowsTheClipboardCue() {
        XCTAssertEqual(DictationCue(issue: .accessibilityAccessNeeded), .textOnClipboard)
    }

    // These have their own cue, or aren't the result of a dictation, so the menu row is enough.
    func testModelProblemsAndOwnCuesGetNoIssueCue() {
        let issues: [SorlaIssue] = [.modelNotLoaded, .modelDownloadFailed, .modelUpdateFailed, .microphoneMuted, .textOnClipboard(pasteShortcut: "⌘V")]
        for issue in issues {
            XCTAssertNil(DictationCue(issue: issue), "\(issue)")
        }
    }

    func testTheCueAnnouncesItsOwnMessage() {
        XCTAssertEqual(DictationCue.waitingForModel("Wait").announcement(pasteShortcut: nil), "Wait")
        XCTAssertEqual(DictationCue.failed("Broken").announcement(pasteShortcut: "⌃⌥V"), "Broken")
    }
}

final class RecordingCheckTests: XCTestCase {
    private let second = 16_000

    func testNoSamplesIsEmpty() {
        XCTAssertEqual(RecordingCheck.assess(sampleCount: 0, peak: 0), .empty)
    }

    func testATakeShorterThanTheModelAcceptsIsTooShort() {
        XCTAssertEqual(RecordingCheck.assess(sampleCount: second / 5, peak: 0.2), .tooShort)
    }

    func testHalfASecondOfExactZerosIsDigitalSilence() {
        XCTAssertEqual(RecordingCheck.assess(sampleCount: second / 2, peak: 0), .digitalSilence)
        XCTAssertEqual(RecordingCheck.assess(sampleCount: 3 * second, peak: 5e-7), .digitalSilence)
    }

    func testAShortSilentTakeIsOnlyBlamedOnTheMicrophoneWhenTheDeviceSaysItIsMuted() {
        XCTAssertEqual(RecordingCheck.assess(sampleCount: second / 5, peak: 0), .tooShort)
        XCTAssertEqual(RecordingCheck.assess(sampleCount: second / 5, peak: 0, deviceSeemsMuted: true), .digitalSilence)
    }

    func testAQuietButRealRoomIsTranscribed() {
        XCTAssertEqual(RecordingCheck.assess(sampleCount: 2 * second, peak: 0.0005), .transcribable)
    }

    func testASilentTakeShorterThanTheRoutesGraceIsNotBlamedOnTheMicrophone() {
        XCTAssertEqual(RecordingCheck.assess(sampleCount: second, peak: 0, minimumSilence: 1.5), .transcribable)
        XCTAssertEqual(RecordingCheck.assess(sampleCount: 2 * second, peak: 0, minimumSilence: 1.5), .digitalSilence)
    }
}

final class MicrophoneMuteDetectorTests: XCTestCase {
    private let wired = InputDeviceState(isMuted: false, volume: 1, isBluetooth: false)

    private func wiredDetector() -> MicrophoneMuteDetector {
        var detector = MicrophoneMuteDetector()
        detector.applyDeviceState(wired)
        return detector
    }

    func testHalfASecondOfSilenceFromTheFirstBufferMeansMutedOnAWiredInput() {
        var detector = wiredDetector()
        XCTAssertFalse(detector.observe(peak: 0, at: 10))
        XCTAssertFalse(detector.observe(peak: 0, at: 10.45))
        XCTAssertFalse(detector.isMuted)

        XCTAssertTrue(detector.observe(peak: 0, at: 10.5))
        XCTAssertTrue(detector.isMuted)
        XCTAssertFalse(detector.observe(peak: 0, at: 10.7))
    }

    // A Bluetooth route that is still starting delivers zeros; so may any route until its type is known.
    func testBluetoothOrAnUnknownRouteGetsAStartupGrace() {
        for state in [InputDeviceState(isBluetooth: true), nil] {
            var detector = MicrophoneMuteDetector()
            if let state { detector.applyDeviceState(state) }
            detector.observe(peak: 0, at: 0)
            detector.observe(peak: 0, at: 1.2)
            XCTAssertFalse(detector.isMuted)
            detector.observe(peak: 0, at: 1.5)
            XCTAssertTrue(detector.isMuted)
        }
        XCTAssertEqual(MicrophoneMuteDetector().requiredSilence, 1.5)
        XCTAssertEqual(wiredDetector().requiredSilence, 0.5)
    }

    func testRealAudioUnmutes() {
        var detector = wiredDetector()
        detector.observe(peak: 0, at: 0)
        detector.observe(peak: 0, at: 0.6)
        XCTAssertTrue(detector.isMuted)

        XCTAssertTrue(detector.observe(peak: 0.01, at: 0.7))
        XCTAssertFalse(detector.isMuted)
    }

    // Krisp, Zoom and Teams virtual mics and gated USB mics send exact zeros between words.
    func testANoiseGateBetweenWordsNeverMutesATakeThatHadAudio() {
        var detector = MicrophoneMuteDetector()
        detector.observe(peak: 0.2, at: 0.1)
        for step in 1...30 {
            XCTAssertFalse(detector.observe(peak: 0, at: 0.1 + Double(step) * 0.1))
        }
        XCTAssertFalse(detector.isMuted)
    }

    func testCoalescedBuffersKeepTheLoudestPeakAndTheNewestSpectrum() {
        let loud = AudioBufferSummary(spectrum: SIMD8(repeating: 0.1), peak: 0.3, time: 1)
        let silent = AudioBufferSummary(spectrum: SIMD8(repeating: 0), peak: 0, time: 2)
        XCTAssertEqual(
            AudioBufferSummary.coalescing(loud, silent),
            AudioBufferSummary(spectrum: SIMD8(repeating: 0), peak: 0.3, time: 2)
        )
    }

    func testAnUnknownDeviceStateChangesNothing() {
        var detector = MicrophoneMuteDetector()
        XCTAssertFalse(detector.applyDeviceState(InputDeviceState()))
        XCTAssertFalse(detector.isMuted)
    }

    // The device state is read off the main actor and can arrive after the first words.
    func testADeviceStateArrivingAfterAudioDoesNotMute() {
        var detector = MicrophoneMuteDetector()
        detector.observe(peak: 0.2, at: 0.05)
        XCTAssertFalse(detector.applyDeviceState(InputDeviceState(volume: 0)))
        XCTAssertFalse(detector.isMuted)
    }

    func testQuietAudioIsNotSilence() {
        var detector = MicrophoneMuteDetector()
        detector.observe(peak: 0.00002, at: 1)
        detector.observe(peak: 0.00002, at: 2)
        XCTAssertFalse(detector.isMuted)
    }

    func testADeviceThatReportsMutedIsMutedFromTheStart() {
        var detector = MicrophoneMuteDetector()
        XCTAssertTrue(detector.applyDeviceState(InputDeviceState(isMuted: true)))
        XCTAssertTrue(detector.isMuted)

        XCTAssertTrue(detector.observe(peak: 0.05, at: 0.1))
        XCTAssertFalse(detector.isMuted)
    }
}

final class InputDeviceStateTests: XCTestCase {
    func testUnknownPropertiesAreNeverMuted() {
        XCTAssertFalse(InputDeviceState().seemsMuted)
        XCTAssertFalse(InputDeviceState(isMuted: false, volume: 0.7).seemsMuted)
    }

    func testReportedMuteOrZeroVolumeIsMuted() {
        XCTAssertTrue(InputDeviceState(isMuted: true).seemsMuted)
        XCTAssertTrue(InputDeviceState(volume: 0).seemsMuted)
        XCTAssertTrue(InputDeviceState(isMuted: false, volume: 0).seemsMuted)
    }

    func testTheMainElementWinsOverChannels() {
        XCTAssertEqual(InputDeviceState.combinedMute(main: false, channels: [true, true]), false)
        XCTAssertEqual(InputDeviceState.combinedVolume(main: 0.5, channels: [0, 0]), 0.5)
    }

    func testChannelsAreMutedOnlyWhenEveryReportedChannelIs() {
        XCTAssertEqual(InputDeviceState.combinedMute(main: nil, channels: [true, nil, true]), true)
        XCTAssertEqual(InputDeviceState.combinedMute(main: nil, channels: [true, false]), false)
        XCTAssertNil(InputDeviceState.combinedMute(main: nil, channels: [nil, nil]))
        XCTAssertNil(InputDeviceState.combinedMute(main: nil, channels: []))
    }

    func testChannelVolumeIsZeroOnlyWhenEveryReportedChannelIs() {
        XCTAssertEqual(InputDeviceState.combinedVolume(main: nil, channels: [0, 0.4]), 0.4)
        XCTAssertEqual(InputDeviceState.combinedVolume(main: nil, channels: [0, nil]), 0)
        XCTAssertNil(InputDeviceState.combinedVolume(main: nil, channels: [nil]))
    }
}
