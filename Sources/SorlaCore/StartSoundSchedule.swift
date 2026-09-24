import Foundation

// A cancel cue only follows a start the user heard, or would have heard with sounds off, so an earlier cancel stays quiet.
@MainActor
public final class StartSoundSchedule {
    private let sleep: @MainActor (Duration) async -> Void
    private var task: Task<Void, Never>?
    private var hasStartSounded = false

    public init(sleep: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.sleep = sleep
    }

    public var isPending: Bool { task != nil }

    // `play` decides for itself whether a sound is heard; the moment counts either way.
    public func schedule(after delay: TimeInterval, play: @escaping @MainActor () -> Void) {
        task?.cancel()
        hasStartSounded = delay <= 0
        let sleep = self.sleep
        task = Task { @MainActor [weak self] in
            if delay > 0 { await sleep(.seconds(delay)) }
            guard let self, !Task.isCancelled else { return }
            self.task = nil
            self.hasStartSounded = true
            play()
        }
    }

    // Ends the schedule and says whether the start had sounded.
    @discardableResult
    public func stop() -> Bool {
        task?.cancel()
        task = nil
        defer { hasStartSounded = false }
        return hasStartSounded
    }
}
