import Foundation

// A known problem that blocks an explicit dictation or paste and needs the user to do something about it (#72).
public enum RecoveryProblem: Hashable, Sendable {
    case microphoneAccess
    case accessibility
    case model(ModelProblem)
    case microphoneStart
    case restartRequired

    public var surface: RecoverySurface {
        switch self {
        case .microphoneAccess, .accessibility, .model: return .setup
        case .microphoneStart: return .microphoneStart
        case .restartRequired: return .restart
        }
    }

    // Only a start that failed has a recovery; a muted or silent microphone keeps its indicator and stays quiet.
    public init?(startFailure issue: SorlaIssue) {
        switch issue {
        case .microphoneAccessNeeded: self = .microphoneAccess
        case .noInputDevice: self = .microphoneStart
        default: return nil
        }
    }

    // Everything that is wrong right now, so a dismissed problem that has gone away can be explained again when it comes back.
    public static func current(
        isMicrophoneAccessDenied: Bool,
        isAccessibilityTrusted: Bool,
        model: ModelProblem?,
        didMicrophoneFailToStart: Bool,
        isAppReplaced: Bool
    ) -> Set<RecoveryProblem> {
        var problems: Set<RecoveryProblem> = []
        if isMicrophoneAccessDenied { problems.insert(.microphoneAccess) }
        if !isAccessibilityTrusted { problems.insert(.accessibility) }
        if let model { problems.insert(.model(model)) }
        if didMicrophoneFailToStart { problems.insert(.microphoneStart) }
        if isAppReplaced { problems.insert(.restartRequired) }
        return problems
    }
}

// A model on its way is waited for; only one that needs the user's help is a problem.
public enum ModelProblem: Hashable, Sendable {
    case missing
    case downloadFailed
    case insufficientDiskSpace
    case loadFailed
}

// Where a problem is explained: the Welcome window's checklist, or a dialog of its own.
public enum RecoverySurface: Hashable, Sendable {
    case setup
    case microphoneStart
    case restart
}

// Why a dictation didn't start: the brief cue, and the problem behind it when the user can fix it.
public struct DictationRefusal: Equatable, Sendable {
    public let cue: DictationCue
    public let problem: RecoveryProblem?

    public init(cue: DictationCue, problem: RecoveryProblem? = nil) {
        self.cue = cue
        self.problem = problem
    }
}

// A paste macOS would have dropped: the text was left on the clipboard instead, until something else is copied.
public struct BlockedPaste: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        case accessibility
        case appReplaced
    }

    public let reason: Reason
    // The clipboard's change count once the text was put there; nil while Sorla keeps the text to itself.
    public let clipboardChangeCount: Int?
    // Which kept transcript it is, so a newer dictation isn't taken for it; nil when nothing was kept.
    public let transcriptRevision: Int?

    public init(reason: Reason, clipboardChangeCount: Int?, transcriptRevision: Int? = nil) {
        self.reason = reason
        self.clipboardChangeCount = clipboardChangeCount
        self.transcriptRevision = transcriptRevision
    }

    public var problem: RecoveryProblem {
        reason == .accessibility ? .accessibility : .restartRequired
    }

    // Only then may a window say the text is on the clipboard.
    public func isOnClipboard(changeCount: Int) -> Bool {
        changeCount == clipboardChangeCount
    }

    // Sorla still holds this very text for Paste Last.
    public func isKept(currentRevision: Int?) -> Bool {
        transcriptRevision != nil && transcriptRevision == currentRevision
    }

    // After the user chose Copy Text.
    public func copied(clipboardChangeCount: Int) -> BlockedPaste {
        BlockedPaste(reason: reason, clipboardChangeCount: clipboardChangeCount, transcriptRevision: transcriptRevision)
    }
}

// A push-to-talk press may still become a ⌘-shortcut, so its refusal is only reported once the release makes it a dictation.
public struct HeldRefusal: Equatable, Sendable {
    private enum Held: Equatable, Sendable {
        case gate
        case startFailure(DictationRefusal)
    }

    private var held: Held?

    public init() {}

    public var isHeld: Bool { held != nil }

    // Refused before the microphone was tried (a restart or the model); rechecked on release.
    public mutating func holdGateRefusal() {
        held = .gate
    }

    // The microphone itself failed; nothing to recheck.
    public mutating func holdStartFailure(_ refusal: DictationRefusal) {
        held = .startFailure(refusal)
    }

    // Let go as a dictation. A blocker that cleared while the key was down is not reported.
    public mutating func release(currentGateRefusal: DictationRefusal?) -> DictationRefusal? {
        defer { held = nil }
        switch held {
        case nil: return nil
        case .gate: return currentGateRefusal
        case .startFailure(let refusal): return currentGateRefusal ?? refusal
        }
    }

    // A ⌘-shortcut, a too-short press or a cancel: nothing is said and no window opens.
    public mutating func discard() {
        held = nil
    }
}

// Which recovery window a blocked attempt opens: one at a time, never over a dictation in flight,
// and after "Not now" not again for the same problem during this run (#72).
public struct RecoveryPrompts: Equatable, Sendable {
    public enum Decision: Equatable, Sendable {
        case none
        // A dictation is still in flight, and the window would take its focus, so it waits until that is done.
        case waitForIdle
        case present(RecoverySurface)
        // Already open: brought forward and updated rather than opened twice.
        case refresh(RecoverySurface)

        public var opensWindow: Bool {
            if case .present = self { return true }
            return false
        }
    }

    public private(set) var dismissed: Set<RecoveryProblem> = []
    public private(set) var pending: RecoveryProblem?
    // Each open surface, and whether it opened for a blocked attempt rather than at launch or from the menu.
    private var open: [RecoverySurface: Bool] = [:]

    public init() {}

    public func isOpen(_ surface: RecoverySurface) -> Bool {
        open[surface] != nil
    }

    // A problem that went away and comes back is explained again.
    public mutating func forgetResolved(current: Set<RecoveryProblem>) {
        dismissed.formIntersection(current)
    }

    // `current` is every problem there is right now, including `problem`.
    public mutating func attemptBlocked(by problem: RecoveryProblem, current: Set<RecoveryProblem>, isDictationBusy: Bool) -> Decision {
        forgetResolved(current: current.union([problem]))
        guard !dismissed.contains(problem) else { return .none }
        guard !isDictationBusy else {
            pending = problem
            return .waitForIdle
        }
        pending = nil
        if open[problem.surface] != nil {
            open[problem.surface] = true
            return .refresh(problem.surface)
        }
        guard open.isEmpty else { return .none }
        open[problem.surface] = true
        return .present(problem.surface)
    }

    // A problem solved while it waited has nothing left to explain.
    public mutating func dictationBecameIdle(current: Set<RecoveryProblem>) -> Decision {
        guard let problem = pending else { return .none }
        pending = nil
        guard current.contains(problem) else { return .none }
        return attemptBlocked(by: problem, current: current, isDictationBusy: false)
    }

    // Opened at launch, from the menu or after a failed restart: closing it isn't an answer to a blocked attempt.
    public mutating func opened(_ surface: RecoverySurface) {
        if open[surface] == nil { open[surface] = false }
    }

    // "Not now", Esc or the close button leave the problems it showed alone for the rest of this run; its own action doesn't.
    public mutating func closed(_ surface: RecoverySurface, current: Set<RecoveryProblem>, byAction: Bool = false) {
        guard let isRecovery = open.removeValue(forKey: surface), isRecovery, !byAction else { return }
        dismissed.formUnion(current.filter { $0.surface == surface })
    }
}

// The two small dialogs; the setup problems share the Welcome window's checklist instead.
public struct RecoveryDialog: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case openSoundSettings
        case restart
        case quit
    }

    public let title: String
    public let message: String
    public let action: Action
    public let actionTitle: String

    // A key pressed just as the dialog appears was meant for the app the user was in, so Return waits this long.
    public static let defaultButtonDelay: Duration = .milliseconds(800)

    public static var notNow: String { String(localized: "Not now", bundle: Localization.bundle) }

    // Says what Sorla needs without guessing at why the input failed.
    public static var microphoneStart: RecoveryDialog {
        RecoveryDialog(
            title: String(localized: "Sorla couldn't start the microphone", bundle: Localization.bundle),
            message: String(localized: "Sorla needs a microphone that is connected and selected as the sound input. Check Input in Sound settings, then try again.", bundle: Localization.bundle),
            action: .openSoundSettings,
            actionTitle: String(localized: "Open Sound Settings", bundle: Localization.bundle)
        )
    }

    // The clipboard is only mentioned while the text really is there.
    public static func restart(canRestart: Bool, isTextOnClipboard: Bool) -> RecoveryDialog {
        var message = String(localized: "Sorla was updated while it was running, and macOS doesn't accept pastes from the old copy.", bundle: Localization.bundle)
        if isTextOnClipboard {
            message += " " + WelcomeChecklist.textOnClipboardInWindow
        }
        guard canRestart else {
            message += " " + String(localized: "Sorla can't reopen itself from where it is running, so quit it and open it again from Applications.", bundle: Localization.bundle)
            return RecoveryDialog(
                title: String(localized: "Sorla needs to restart", bundle: Localization.bundle),
                message: message,
                action: .quit,
                actionTitle: String(localized: "Quit Sorla", bundle: Localization.bundle)
            )
        }
        message += " " + String(localized: "Restarting opens the new version.", bundle: Localization.bundle)
        return RecoveryDialog(
            title: String(localized: "Sorla needs to restart", bundle: Localization.bundle),
            message: message,
            action: .restart,
            actionTitle: String(localized: "Restart Sorla", bundle: Localization.bundle)
        )
    }
}

// Restarts once nothing is recording, transcribing, pasting or putting back the clipboard, so no words are lost (#72).
@MainActor
public final class QuietRestart {
    public static let pollInterval: Duration = .milliseconds(250)

    private let activity: @MainActor () -> DictationActivity
    private let sleep: @MainActor (Duration) async -> Void
    // Returns false when the relaunch couldn't be set up.
    private let restart: @MainActor () -> Bool
    private var waiting: Task<Void, Never>?

    public init(
        activity: @escaping @MainActor () -> DictationActivity,
        sleep: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        restart: @escaping @MainActor () -> Bool
    ) {
        self.activity = activity
        self.sleep = sleep
        self.restart = restart
    }

    public var isPending: Bool { waiting != nil }

    // A second request while one waits is the same restart; returns the wait so tests can follow it.
    @discardableResult
    public func request(onFailure: @escaping @MainActor () -> Void) -> Task<Void, Never>? {
        guard waiting == nil else { return nil }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            while !self.activity().isQuiet {
                await self.sleep(Self.pollInterval)
            }
            self.waiting = nil
            if !self.restart() { onFailure() }
        }
        waiting = task
        return task
    }
}
