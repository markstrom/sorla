import Foundation

// A forgotten toggle recording would keep the microphone open, so a dictation stops by itself after five minutes.
public struct RecordingLimit: Equatable, Sendable {
    public static let standard = RecordingLimit(maximum: 5 * 60, warningLead: 10)

    public let maximum: TimeInterval
    public let warningLead: TimeInterval

    public enum Step: Equatable, Sendable {
        case warn(after: TimeInterval)
        case stop(after: TimeInterval)
    }

    public init(maximum: TimeInterval, warningLead: TimeInterval) {
        self.maximum = maximum
        self.warningLead = warningLead
    }

    // What a recording that has run for `elapsed` seconds does next, and how long until then.
    public func nextStep(elapsed: TimeInterval) -> Step {
        let warningAt = max(0, maximum - warningLead)
        if elapsed < warningAt {
            return .warn(after: warningAt - elapsed)
        }
        return .stop(after: max(0, maximum - elapsed))
    }
}
