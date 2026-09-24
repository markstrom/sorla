import XCTest
@testable import SorlaCore

final class DictationCueTests: XCTestCase {
    func testEachCueHasItsOwnSymbol() {
        let cues: [DictationCue] = [.microphoneMuted, .nothingHeard, .noText, .textOnClipboard]
        XCTAssertEqual(cues.map(\.symbolName), ["mic.slash", "waveform.slash", "minus", "doc.on.clipboard"])
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

    func testOnlyCuesTheUserMustActOnBecomeNotifications() {
        XCTAssertEqual(DictationCue.microphoneMuted.issue(pasteShortcut: nil), .microphoneMuted)
        XCTAssertEqual(DictationCue.textOnClipboard.issue(pasteShortcut: "⌃⌥V"), .textOnClipboard(pasteShortcut: "⌃⌥V"))
        XCTAssertNil(DictationCue.nothingHeard.issue(pasteShortcut: nil))
        XCTAssertNil(DictationCue.noText.issue(pasteShortcut: nil))
    }

    func testNotificationWording() {
        XCTAssertEqual(
            SorlaIssue.microphoneMuted.notificationBody,
            "The microphone seems to be muted. Check System Settings › Sound › Input."
        )
        XCTAssertEqual(SorlaIssue.textOnClipboard(pasteShortcut: "⌃⌥V").notificationBody, "Your text is on the clipboard — press ⌃⌥V")
        XCTAssertNil(SorlaIssue.microphoneMuted.menuTitle)
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
}

final class MicrophoneMuteDetectorTests: XCTestCase {
    func testHalfASecondOfSilenceMeansMuted() {
        var detector = MicrophoneMuteDetector(startedAt: 10)
        XCTAssertFalse(detector.observe(peak: 0, at: 10.1))
        XCTAssertFalse(detector.observe(peak: 0, at: 10.45))
        XCTAssertFalse(detector.isMuted)

        XCTAssertTrue(detector.observe(peak: 0, at: 10.5))
        XCTAssertTrue(detector.isMuted)
        XCTAssertFalse(detector.observe(peak: 0, at: 10.7))
    }

    func testRealAudioRecoversAndRestartsTheSilenceClock() {
        var detector = MicrophoneMuteDetector(startedAt: 0)
        detector.observe(peak: 0, at: 0.6)
        XCTAssertTrue(detector.isMuted)

        XCTAssertTrue(detector.observe(peak: 0.01, at: 0.7))
        XCTAssertFalse(detector.isMuted)

        detector.observe(peak: 0, at: 0.8)
        detector.observe(peak: 0, at: 1.2)
        XCTAssertFalse(detector.isMuted)
        detector.observe(peak: 0, at: 1.3)
        XCTAssertTrue(detector.isMuted)
    }

    func testQuietAudioIsNotSilence() {
        var detector = MicrophoneMuteDetector(startedAt: 0)
        detector.observe(peak: 0.00002, at: 1)
        detector.observe(peak: 0.00002, at: 2)
        XCTAssertFalse(detector.isMuted)
    }

    func testADeviceThatReportsMutedIsMutedFromTheStart() {
        var detector = MicrophoneMuteDetector(startedAt: 0, deviceSeemsMuted: true)
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
