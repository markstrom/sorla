// Speech while the microphone is open would be recorded with the user's words, so it waits until the microphone has closed.
public struct AnnouncementGate: Equatable, Sendable {
    private(set) var pending: String?

    public init() {}

    // Returns the text to announce now, or nil when it has to wait; a newer outcome replaces an older one.
    public mutating func request(_ text: String, isMicrophoneOpen: Bool) -> String? {
        guard isMicrophoneOpen else { return text }
        pending = text
        return nil
    }

    public mutating func microphoneClosed() -> String? {
        defer { pending = nil }
        return pending
    }
}
