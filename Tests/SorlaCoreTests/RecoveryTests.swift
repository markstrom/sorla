import XCTest
@testable import SorlaCore

// When a blocked dictation or paste opens a recovery window, and what that window says (#72).
final class RecoveryPromptsTests: XCTestCase {
    private var prompts = RecoveryPrompts()

    private func attempt(_ problem: RecoveryProblem, current: Set<RecoveryProblem>? = nil, busy: Bool = false) -> RecoveryPrompts.Decision {
        prompts.attemptBlocked(by: problem, current: current ?? [problem], isDictationBusy: busy)
    }

    func testABlockedAttemptOpensTheWindowForItsProblem() {
        XCTAssertEqual(attempt(.accessibility), .present(.setup))
        prompts = RecoveryPrompts()
        XCTAssertEqual(attempt(.model(.insufficientDiskSpace)), .present(.setup))
        prompts = RecoveryPrompts()
        XCTAssertEqual(attempt(.microphoneStart), .present(.microphoneStart))
        prompts = RecoveryPrompts()
        XCTAssertEqual(attempt(.restartRequired), .present(.restart))
    }

    func testNotNowKeepsTheSameProblemFromReopeningOnEveryAttempt() {
        XCTAssertEqual(attempt(.restartRequired), .present(.restart))
        prompts.closed(.restart, current: [.restartRequired])

        XCTAssertEqual(attempt(.restartRequired), .none)
        XCTAssertEqual(attempt(.restartRequired), .none)
    }

    // Everything the checklist showed was seen, so none of it opens the window again.
    func testNotNowOnTheChecklistCoversEveryRowItShowed() {
        let current: Set<RecoveryProblem> = [.accessibility, .microphoneAccess]
        XCTAssertEqual(attempt(.accessibility, current: current), .present(.setup))
        prompts.closed(.setup, current: current)

        XCTAssertEqual(attempt(.microphoneAccess, current: current), .none)
        XCTAssertEqual(attempt(.accessibility, current: current), .none)
    }

    func testTheWindowsOwnActionIsNotANotNow() {
        XCTAssertEqual(attempt(.microphoneStart), .present(.microphoneStart))
        prompts.closed(.microphoneStart, current: [.microphoneStart], byAction: true)

        XCTAssertEqual(attempt(.microphoneStart), .present(.microphoneStart))
    }

    func testADifferentBlockerIsExplainedAfterNotNow() {
        XCTAssertEqual(attempt(.accessibility), .present(.setup))
        prompts.closed(.setup, current: [.accessibility])

        XCTAssertEqual(attempt(.model(.loadFailed), current: [.accessibility, .model(.loadFailed)]), .present(.setup))
        prompts.closed(.setup, current: [.accessibility, .model(.loadFailed)])
        XCTAssertEqual(attempt(.microphoneStart, current: [.accessibility, .microphoneStart]), .present(.microphoneStart))
    }

    func testAProblemThatWasSolvedAndCameBackIsExplainedAgain() {
        XCTAssertEqual(attempt(.microphoneStart), .present(.microphoneStart))
        prompts.closed(.microphoneStart, current: [.microphoneStart])
        XCTAssertEqual(attempt(.microphoneStart), .none)

        prompts.forgetResolved(current: [])
        XCTAssertEqual(attempt(.microphoneStart), .present(.microphoneStart))
    }

    // A download that failed, was retried and failed again is back after being gone.
    func testAnAttemptAlsoNoticesWhatHasBeenSolved() {
        XCTAssertEqual(attempt(.model(.downloadFailed)), .present(.setup))
        prompts.closed(.setup, current: [.model(.downloadFailed)])

        XCTAssertEqual(attempt(.restartRequired), .present(.restart))
        prompts.closed(.restart, current: [.restartRequired], byAction: true)
        XCTAssertEqual(attempt(.model(.downloadFailed)), .present(.setup))
    }

    func testOnlyOneRecoveryWindowAtATime() {
        XCTAssertEqual(attempt(.microphoneStart), .present(.microphoneStart))
        XCTAssertEqual(attempt(.restartRequired, current: [.microphoneStart, .restartRequired]), .none)
        XCTAssertEqual(attempt(.accessibility, current: [.microphoneStart, .accessibility]), .none)

        // Not shown isn't dismissed: once the first window has closed, the next attempt explains it.
        prompts.closed(.microphoneStart, current: [.microphoneStart, .restartRequired])
        XCTAssertEqual(attempt(.restartRequired), .present(.restart))
    }

    func testAnOpenWindowIsUpdatedRatherThanOpenedTwice() {
        XCTAssertEqual(attempt(.model(.missing)), .present(.setup))
        XCTAssertEqual(attempt(.accessibility, current: [.model(.missing), .accessibility]), .refresh(.setup))
        XCTAssertEqual(attempt(.restartRequired), .none)
    }

    // The launch window is the same checklist, so it is reused; closing it only counts once an attempt has used it.
    func testTheLaunchWindowIsReusedAndOnlyARecoveryCloseIsANotNow() {
        prompts.opened(.setup)
        prompts.closed(.setup, current: [.accessibility])
        XCTAssertEqual(attempt(.accessibility), .present(.setup))

        prompts = RecoveryPrompts()
        prompts.opened(.setup)
        XCTAssertEqual(attempt(.accessibility), .refresh(.setup))
        prompts.closed(.setup, current: [.accessibility])
        XCTAssertEqual(attempt(.accessibility), .none)
    }

    func testAWindowWaitsForTheDictationInFlight() {
        XCTAssertEqual(attempt(.accessibility, busy: true), .waitForIdle)
        XCTAssertEqual(prompts.pending, .accessibility)

        XCTAssertEqual(prompts.dictationBecameIdle(current: [.accessibility]), .present(.setup))
        XCTAssertNil(prompts.pending)
        XCTAssertEqual(prompts.dictationBecameIdle(current: [.accessibility]), .none)
    }

    func testAProblemSolvedWhileWaitingOpensNothing() {
        XCTAssertEqual(attempt(.accessibility, busy: true), .waitForIdle)
        XCTAssertEqual(prompts.dictationBecameIdle(current: []), .none)
        XCTAssertFalse(prompts.isOpen(.setup))
    }

    func testADismissedProblemDoesNotWaitEither() {
        XCTAssertEqual(attempt(.restartRequired), .present(.restart))
        prompts.closed(.restart, current: [.restartRequired])

        XCTAssertEqual(attempt(.restartRequired, busy: true), .none)
        XCTAssertNil(prompts.pending)
    }

    func testOnlyAnImmediateWindowOpensOne() {
        XCTAssertTrue(RecoveryPrompts.Decision.present(.setup).opensWindow)
        XCTAssertFalse(RecoveryPrompts.Decision.refresh(.setup).opensWindow)
        XCTAssertFalse(RecoveryPrompts.Decision.waitForIdle.opensWindow)
        XCTAssertFalse(RecoveryPrompts.Decision.none.opensWindow)
    }
}

final class RecoveryProblemTests: XCTestCase {
    func testEachProblemHasOneSurface() {
        XCTAssertEqual(RecoveryProblem.microphoneAccess.surface, .setup)
        XCTAssertEqual(RecoveryProblem.accessibility.surface, .setup)
        XCTAssertEqual(RecoveryProblem.model(.loadFailed).surface, .setup)
        XCTAssertEqual(RecoveryProblem.microphoneStart.surface, .microphoneStart)
        XCTAssertEqual(RecoveryProblem.restartRequired.surface, .restart)
    }

    // A muted or silent microphone keeps its crossed-out indicator and never opens a dialog.
    func testOnlyAFailedStartIsAProblem() {
        XCTAssertEqual(RecoveryProblem(startFailure: .noInputDevice), .microphoneStart)
        XCTAssertEqual(RecoveryProblem(startFailure: .microphoneAccessNeeded), .microphoneAccess)
        XCTAssertNil(RecoveryProblem(startFailure: .microphoneMuted))
        XCTAssertNil(RecoveryProblem(startFailure: .transcriptionFailed))
        XCTAssertNil(RecoveryProblem(startFailure: .textOnClipboard(pasteShortcut: "⌘V")))
    }

    func testTheCurrentProblems() {
        XCTAssertEqual(
            RecoveryProblem.current(isMicrophoneAccessDenied: false, isAccessibilityTrusted: true, model: nil, didMicrophoneFailToStart: false, isAppReplaced: false),
            []
        )
        XCTAssertEqual(
            RecoveryProblem.current(isMicrophoneAccessDenied: true, isAccessibilityTrusted: false, model: .missing, didMicrophoneFailToStart: true, isAppReplaced: true),
            [.microphoneAccess, .accessibility, .model(.missing), .microphoneStart, .restartRequired]
        )
    }

    func testABlockedPasteIsOnTheClipboardUntilSomethingElseIsCopied() {
        let blocked = BlockedPaste(reason: .accessibility, clipboardChangeCount: 7)
        XCTAssertTrue(blocked.isOnClipboard(changeCount: 7))
        XCTAssertFalse(blocked.isOnClipboard(changeCount: 8))
        XCTAssertEqual(blocked.problem, .accessibility)
        XCTAssertEqual(BlockedPaste(reason: .appReplaced, clipboardChangeCount: 1).problem, .restartRequired)
    }
}

// A push-to-talk press is refused on the key-down but only reported once the release makes it a dictation.
final class HeldRefusalTests: XCTestCase {
    private var gesture = PushToTalkGesture(mode: .pushToTalk)
    private var held = HeldRefusal()
    private let restart = DictationRefusal(cue: .restartNeeded, problem: .restartRequired)
    private var reported: [DictationRefusal] = []

    // What AppDelegate does with each gesture action while a restart is needed.
    private func handle(_ event: PushToTalkGesture.Event, blocker: DictationRefusal?) {
        switch gesture.handle(event) {
        case .start:
            held.holdGateRefusal()
        case .finish:
            XCTAssertTrue(held.isHeld)
            if let refusal = held.release(currentGateRefusal: blocker) { reported.append(refusal) }
        case .cancel, .discard:
            held.discard()
        case nil:
            break
        }
    }

    func testAHeldDictationIsReportedOnRelease() {
        handle(.triggerDown(at: 0), blocker: restart)
        XCTAssertEqual(reported, [])
        handle(.triggerUp(at: 1), blocker: restart)
        XCTAssertEqual(reported, [restart])
        XCTAssertFalse(held.isHeld)
    }

    func testACommandShortcutIsNeverReported() {
        handle(.triggerDown(at: 0), blocker: restart)
        handle(.otherKeyDown(at: 0.1), blocker: restart)
        handle(.triggerUp(at: 0.2), blocker: restart)

        handle(.triggerDown(at: 1), blocker: restart)
        handle(.otherKeyDown(at: 2), blocker: restart)
        handle(.triggerUp(at: 2.5), blocker: restart)
        XCTAssertEqual(reported, [])
        XCTAssertFalse(held.isHeld)
    }

    func testATooShortPressIsNeverReported() {
        handle(.triggerDown(at: 0), blocker: restart)
        handle(.triggerUp(at: 0.1), blocker: restart)
        XCTAssertEqual(reported, [])
        XCTAssertFalse(held.isHeld)
    }

    func testACancelledPressIsNeverReported() {
        handle(.triggerDown(at: 0), blocker: restart)
        handle(.escape, blocker: restart)
        handle(.triggerUp(at: 1), blocker: restart)
        XCTAssertEqual(reported, [])
    }

    func testABlockerThatClearedWhileHeldIsNotReported() {
        held.holdGateRefusal()
        XCTAssertNil(held.release(currentGateRefusal: nil))
    }

    func testAMicrophoneThatFailedToStartStandsOnRelease() {
        let failure = DictationRefusal(cue: .failed("No microphone found"), problem: .microphoneStart)
        held.holdStartFailure(failure)
        XCTAssertEqual(held.release(currentGateRefusal: nil), failure)
        held.holdStartFailure(failure)
        XCTAssertEqual(held.release(currentGateRefusal: restart), restart)
        XCTAssertNil(held.release(currentGateRefusal: restart))
    }
}

final class RecoveryDialogTests: XCTestCase {
    func testTheMicrophoneDialogSaysWhatIsNeededWithoutADiagnosis() {
        let dialog = RecoveryDialog.microphoneStart
        XCTAssertEqual(dialog.title, "Sorla couldn't start the microphone")
        XCTAssertEqual(dialog.message, "Sorla needs a microphone that is connected and selected as the sound input. Check Input in Sound settings, then try again.")
        XCTAssertEqual(dialog.action, .openSoundSettings)
        XCTAssertEqual(dialog.actionTitle, "Open Sound Settings")
        XCTAssertEqual(RecoveryDialog.notNow, "Not now")
    }

    func testTheRestartDialogExplainsWhyPastingStopped() {
        let dialog = RecoveryDialog.restart(canRestart: true, isTextOnClipboard: false)
        XCTAssertEqual(dialog.title, "Sorla needs to restart")
        XCTAssertEqual(dialog.message, "Sorla was updated while it was running, and macOS doesn't accept pastes from the old copy. Restarting opens the new version.")
        XCTAssertEqual(dialog.action, .restart)
        XCTAssertEqual(dialog.actionTitle, "Restart Sorla")
    }

    func testTheRestartDialogMentionsTheClipboardOnlyWhenTheTextIsThere() {
        XCTAssertEqual(
            RecoveryDialog.restart(canRestart: true, isTextOnClipboard: true).message,
            "Sorla was updated while it was running, and macOS doesn't accept pastes from the old copy. Your text is on the clipboard — close this window and press ⌘V where you were typing. Restarting opens the new version."
        )
    }

    // A copy that can't reopen itself is told the truth: quit, and open it from Applications.
    func testACopyThatCantReopenItselfOffersQuit() {
        let dialog = RecoveryDialog.restart(canRestart: false, isTextOnClipboard: false)
        XCTAssertEqual(dialog.action, .quit)
        XCTAssertEqual(dialog.actionTitle, "Quit Sorla")
        XCTAssertEqual(dialog.message, "Sorla was updated while it was running, and macOS doesn't accept pastes from the old copy. Sorla can't reopen itself from where it is running, so quit it and open it again from Applications.")
    }
}

// A restart the user asked for never cuts a recording, transcription, paste or clipboard restore short.
@MainActor
final class QuietRestartTests: XCTestCase {
    private final class Activity {
        var value = DictationActivity.quiet
    }

    private let clock = TestClock()
    private let activity = Activity()
    private var restarts = 0
    private var failures = 0
    private var restartSucceeds = true

    private func makeRestart() -> QuietRestart {
        let clock = self.clock
        let activity = self.activity
        return QuietRestart(
            activity: { activity.value },
            sleep: { await clock.sleep(for: $0) },
            restart: { [unowned self] in
                restarts += 1
                return restartSucceeds
            }
        )
    }

    func testAQuietSorlaRestartsAtOnce() async {
        let restart = makeRestart()
        await restart.request(onFailure: { [unowned self] in failures += 1 })?.value
        XCTAssertEqual(restarts, 1)
        XCTAssertEqual(failures, 0)
        XCTAssertFalse(restart.isPending)
        XCTAssertEqual(clock.sleeps, [])
    }

    func testARestartWaitsForEverythingInFlight() async {
        activity.value = DictationActivity(isTranscribing: true, pendingDeliveries: 1)
        let restart = makeRestart()
        let waiting = restart.request(onFailure: {})
        await clock.waitForSleeps(1)
        XCTAssertEqual(restarts, 0)
        XCTAssertTrue(restart.isPending)

        activity.value = DictationActivity(isRestoringClipboard: true)
        await clock.advance(by: QuietRestart.pollInterval)
        await clock.waitForSleeps(2)
        XCTAssertEqual(restarts, 0)

        activity.value = .quiet
        await clock.advance(by: QuietRestart.pollInterval)
        await waiting?.value
        XCTAssertEqual(restarts, 1)
        XCTAssertFalse(restart.isPending)
    }

    func testAnotherRequestWhileWaitingIsTheSameRestart() async {
        activity.value = DictationActivity(isRecording: true)
        let restart = makeRestart()
        let waiting = restart.request(onFailure: {})
        XCTAssertNil(restart.request(onFailure: {}))
        await clock.waitForSleeps(1)

        activity.value = .quiet
        await clock.advance(by: QuietRestart.pollInterval)
        await waiting?.value
        XCTAssertEqual(restarts, 1)
    }

    func testARelaunchThatCantStartIsReported() async {
        restartSucceeds = false
        let restart = makeRestart()
        await restart.request(onFailure: { [unowned self] in failures += 1 })?.value
        XCTAssertEqual(restarts, 1)
        XCTAssertEqual(failures, 1)
        XCTAssertFalse(restart.isPending)
    }
}
