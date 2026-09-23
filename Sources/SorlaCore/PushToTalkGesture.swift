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
    }

    private let minimumHold: TimeInterval
    private let mode: RecordingMode
    private var state: State = .idle

    public static let defaultMinimumHold: TimeInterval = 0.3

    public init(minimumHold: TimeInterval = defaultMinimumHold, mode: RecordingMode = .pushToTalk) {
        self.minimumHold = minimumHold
        self.mode = mode
    }

    public mutating func handle(_ event: Event) -> Action? {
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

    public mutating func reset() {
        state = .idle
    }
}
