import Foundation

public struct PushToTalkGesture {
    public enum Event: Equatable {
        case triggerDown(at: TimeInterval)
        case triggerUp(at: TimeInterval)
        case otherKeyDown
    }

    public enum Action: Equatable {
        case start
        case finish
        case cancel
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
        switch state {
        case .external, .externalHeld, .externalHeldDirty:
            return handleExternal(event)
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

    private mutating func handlePushToTalk(_ event: Event) -> Action? {
        switch (state, event) {
        case (.idle, .triggerDown(let at)):
            state = .holding(since: at)
            return .start

        case (.holding(let since), .triggerUp(let at)):
            state = .idle
            return (at - since) >= minimumHold ? .finish : .cancel

        case (.holding, .otherKeyDown):
            state = .cancelled
            return .cancel

        case (.cancelled, .triggerUp):
            state = .idle
            return nil

        default:
            return nil
        }
    }

    // A clean tap (down+up, no otherKeyDown between) toggles idle->recording or recording->finished/cancelled.
    private mutating func handleToggle(_ event: Event) -> Action? {
        switch (state, event) {
        case (.idle, .triggerDown(let at)):
            state = .holding(since: at)
            return nil

        case (.holding(let since), .triggerUp):
            state = .recording(startedAt: since)
            return .start

        case (.holding, .otherKeyDown):
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
            return (at - startedAt) >= minimumHold ? .finish : .cancel

        case (.recordingHeld(let startedAt), .otherKeyDown):
            state = .recordingHeldDirty(startedAt: startedAt)
            return nil

        case (.recordingHeldDirty(let startedAt), .triggerUp):
            state = .recording(startedAt: startedAt)
            return nil

        default:
            return nil
        }
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

        case (.externalHeld, .otherKeyDown):
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
