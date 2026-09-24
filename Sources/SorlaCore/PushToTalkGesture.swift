import Foundation

public struct PushToTalkGesture {
    public enum Event: Equatable {
        case triggerDown(at: TimeInterval)
        case triggerUp(at: TimeInterval)
        case otherKeyDown(at: TimeInterval)
        case click(at: TimeInterval)
        case escape
    }

    public enum Action: Equatable {
        case start
        case finish
        // A dictation the user could see or hear was called off, so Sorla says so.
        case cancel
        // The press never became a dictation (too short, or a ⌘-shortcut), so it goes quietly.
        case discard
    }

    private enum State {
        case idle
        case holding(since: TimeInterval)
        case heldDirty
        case cancelled
        case recording(startedAt: TimeInterval)
        case recordingHeld(startedAt: TimeInterval)
        case recordingHeldDirty(startedAt: TimeInterval)
        case external
        case externalHeld
        case externalHeldDirty
    }

    private let minimumHold: TimeInterval
    private let mode: RecordingMode
    private var state: State = .idle

    public static let defaultMinimumHold: TimeInterval = 0.3

    public init(minimumHold: TimeInterval = defaultMinimumHold, mode: RecordingMode = .pushToTalk) {
        self.minimumHold = minimumHold
        self.mode = mode
    }

    // A press is in progress, so a lost release would leave the gesture stuck.
    public var isWaitingForRelease: Bool {
        switch state {
        case .holding, .heldDirty, .cancelled, .recordingHeld, .recordingHeldDirty, .externalHeld, .externalHeldDirty: return true
        case .idle, .recording, .external: return false
        }
    }

    public mutating func handle(_ event: Event) -> Action? {
        if event == .escape {
            return handleEscape()
        }
        switch state {
        case .external, .externalHeld, .externalHeldDirty:
            return handleExternal(event)
        case .cancelled:
            if case .triggerUp = event { state = .idle }
            return nil
        default:
            break
        }
        switch mode {
        case .pushToTalk:
            return handlePushToTalk(event)
        case .toggle:
            return handleToggle(event)
        }
    }

    // Esc calls off whatever is recording, however it was started; a held key must still be let go first.
    private mutating func handleEscape() -> Action? {
        switch state {
        case .holding where mode == .pushToTalk, .recordingHeld, .recordingHeldDirty, .externalHeld, .externalHeldDirty:
            state = .cancelled
            return .cancel
        case .recording, .external:
            state = .idle
            return .cancel
        case .holding:
            state = .heldDirty
            return nil
        case .idle, .heldDirty, .cancelled:
            return nil
        }
    }

    private mutating func handlePushToTalk(_ event: Event) -> Action? {
        switch (state, event) {
        case (.idle, .triggerDown(let at)):
            state = .holding(since: at)
            return .start

        case (.holding(let since), .triggerUp(let at)):
            state = .idle
            return isPastMinimumHold(since: since, at: at) ? .finish : .discard

        // A key with the trigger held is a ⌘-shortcut, not speech.
        case (.holding(let since), .otherKeyDown(let at)):
            state = .cancelled
            return isPastMinimumHold(since: since, at: at) ? .cancel : .discard

        // Past the minimum hold a click is a stray one (or opens the menu to stop), not a ⌘-click.
        case (.holding(let since), .click(let at)):
            guard !isPastMinimumHold(since: since, at: at) else { return nil }
            state = .cancelled
            return .discard

        default:
            return nil
        }
    }

    // A clean tap (down+up, no key or click between) toggles idle->recording or recording->finished/cancelled.
    private mutating func handleToggle(_ event: Event) -> Action? {
        switch (state, event) {
        case (.idle, .triggerDown(let at)):
            state = .holding(since: at)
            return nil

        case (.holding(let since), .triggerUp):
            state = .recording(startedAt: since)
            return .start

        case (.holding, .otherKeyDown), (.holding, .click):
            state = .heldDirty
            return nil

        case (.heldDirty, .triggerUp):
            state = .idle
            return nil

        case (.recording(let startedAt), .triggerDown):
            state = .recordingHeld(startedAt: startedAt)
            return nil

        case (.recordingHeld(let startedAt), .triggerUp(let at)):
            state = .idle
            return isPastMinimumHold(since: startedAt, at: at) ? .finish : .cancel

        case (.recordingHeld(let startedAt), .otherKeyDown), (.recordingHeld(let startedAt), .click):
            state = .recordingHeldDirty(startedAt: startedAt)
            return nil

        case (.recordingHeldDirty(let startedAt), .triggerUp):
            state = .recording(startedAt: startedAt)
            return nil

        default:
            return nil
        }
    }

    private func isPastMinimumHold(since: TimeInterval, at: TimeInterval) -> Bool {
        (at - since) >= minimumHold
    }

    // A dictation started from the menu wasn't started by the key, so only a clean press and release stops it.
    public mutating func recordingStartedElsewhere() {
        state = .external
    }

    // Any key or click while the trigger is down means a ⌘-shortcut, which must not end the dictation.
    private mutating func handleExternal(_ event: Event) -> Action? {
        switch (state, event) {
        case (.external, .triggerDown):
            state = .externalHeld
            return nil

        case (.externalHeld, .otherKeyDown), (.externalHeld, .click):
            state = .externalHeldDirty
            return nil

        case (.externalHeld, .triggerUp):
            state = .idle
            return .finish

        case (.externalHeldDirty, .triggerUp):
            state = .external
            return nil

        default:
            return nil
        }
    }

    public mutating func reset() {
        state = .idle
    }
}
