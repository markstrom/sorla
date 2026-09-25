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

    // The dimmed bars only warn those who can see them; a warning spoken earlier would be recorded (#63).
    public static var stopAnnouncement: String {
        String(localized: "Recording stopped at the five-minute limit", bundle: Localization.bundle)
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

// One task per recording, stopped when the recording ends, so nothing runs while idle.
@MainActor
public final class RecordingLimitWatch {
    private let limit: RecordingLimit
    private let now: @MainActor () -> ContinuousClock.Instant
    private let sleep: @MainActor (Duration) async -> Void
    private var task: Task<Void, Never>?

    public init(
        limit: RecordingLimit = .standard,
        now: @escaping @MainActor () -> ContinuousClock.Instant = { .now },
        sleep: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.limit = limit
        self.now = now
        self.sleep = sleep
    }

    public var isWatching: Bool { task != nil }

    public func start(onWarning: @escaping @MainActor () -> Void, onLimit: @escaping @MainActor () -> Void) {
        stop()
        let limit = self.limit
        let now = self.now
        let sleep = self.sleep
        let start = now()
        task = Task { @MainActor [weak self] in
            var hasWarned = false
            while !Task.isCancelled {
                switch limit.nextStep(elapsed: (now() - start) / .seconds(1)) {
                case .warn(let delay):
                    await sleep(.seconds(delay))
                    guard !Task.isCancelled, !hasWarned else { continue }
                    hasWarned = true
                    onWarning()
                case .stop(let delay):
                    await sleep(.seconds(delay))
                    guard !Task.isCancelled else { return }
                    self?.task = nil
                    onLimit()
                    return
                }
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }
}
