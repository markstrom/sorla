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
        case cancelled
    }

    private let minimumHold: TimeInterval
    private var state: State = .idle

    public init(minimumHold: TimeInterval = 0.3) {
        self.minimumHold = minimumHold
    }

    public mutating func handle(_ event: Event) -> Action? {
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
}
