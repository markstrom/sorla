// What stands between a Paste Last request and its ⌘V.
public enum PasteLastPreparation: Equatable, Sendable {
    case ready
    // The shortcut's keys were never let go, so nothing is pasted and the user is asked to press it again.
    case keysStillHeld
    case abandoned
}

// The shortcut's own modifiers are still down when it fires, and a ⌘V posted then would reach the app as ⌃⌥⌘V.
public enum ModifierRelease {
    public static let timeout: Duration = .seconds(1)
    public static let pollInterval: Duration = .milliseconds(20)

    // Cancelling the waiting task (a lock, a new dictation) abandons the paste.
    @MainActor
    public static func wait(
        isHeld: @MainActor () -> Bool,
        timeout: Duration = timeout,
        now: @MainActor () -> ContinuousClock.Instant = { .now },
        sleep: @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) async -> PasteLastPreparation {
        let deadline = now() + timeout
        while isHeld() {
            guard !Task.isCancelled else { return .abandoned }
            guard now() < deadline else { return .keysStillHeld }
            await sleep(pollInterval)
        }
        return Task.isCancelled ? .abandoned : .ready
    }
}
