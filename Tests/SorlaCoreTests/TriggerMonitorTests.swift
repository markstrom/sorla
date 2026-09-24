import XCTest
@testable import SorlaCore

@MainActor
final class TriggerMonitorTests: XCTestCase {
    private var starts = 0
    private var finishes = 0
    private var cancels = 0

    private func makeMonitor(mode: RecordingMode) -> TriggerMonitor {
        TriggerMonitor(
            mode: mode,
            onStart: { [unowned self] in
                self.starts += 1
                return true
            },
            onFinish: { [unowned self] in self.finishes += 1 },
            onCancel: { [unowned self] in self.cancels += 1 }
        )
    }

    func testAKeyStartedDictationStartsOnPressInPushToTalk() {
        let monitor = makeMonitor(mode: .pushToTalk)
        monitor.handle(.triggerDown(at: 0))
        monitor.handle(.triggerUp(at: 1))
        XCTAssertEqual([starts, finishes, cancels], [1, 1, 0])
    }

    func testAMenuStartedDictationIsFinishedOnReleaseNotOnPress() {
        let monitor = makeMonitor(mode: .pushToTalk)
        monitor.recordingDidStartElsewhere()

        monitor.handle(.triggerDown(at: 0))
        XCTAssertEqual([starts, finishes, cancels], [0, 0, 0])
        monitor.handle(.triggerUp(at: 1))
        XCTAssertEqual([starts, finishes, cancels], [0, 1, 0])
    }

    func testAShortcutDoesNotEndAMenuStartedDictation() {
        let monitor = makeMonitor(mode: .pushToTalk)
        monitor.recordingDidStartElsewhere()

        monitor.handle(.triggerDown(at: 0))
        monitor.handle(.otherKeyDown)
        monitor.handle(.triggerUp(at: 1))

        XCTAssertEqual([starts, finishes, cancels], [0, 0, 0])
    }

    func testAMenuStartedDictationIsCancelledLikeAKeyOneWhenSettingsTakesTheKeys() {
        let monitor = makeMonitor(mode: .toggle)
        monitor.recordingDidStartElsewhere()
        monitor.isSuspended = true
        XCTAssertEqual(cancels, 1)
    }

    // A toggle dictation stopped from the menu or at the limit: the next tap must start, not stop.
    func testAfterADictationEndsElsewhereTheNextTapStartsANewOne() {
        let monitor = makeMonitor(mode: .toggle)
        monitor.handle(.triggerDown(at: 0))
        monitor.handle(.triggerUp(at: 0.1))
        XCTAssertEqual(starts, 1)

        monitor.recordingDidEndElsewhere()
        monitor.handle(.triggerDown(at: 5))
        monitor.handle(.triggerUp(at: 5.1))

        XCTAssertEqual([starts, finishes, cancels], [2, 0, 0])
    }

    func testADictationThatEndedElsewhereIsNotCancelledAgain() {
        let monitor = makeMonitor(mode: .toggle)
        monitor.recordingDidStartElsewhere()
        monitor.recordingDidEndElsewhere()
        monitor.isSuspended = true
        XCTAssertEqual(cancels, 0)
    }
}
