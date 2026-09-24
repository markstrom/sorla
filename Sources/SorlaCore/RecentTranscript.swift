import Foundation

// Paste Last only recovers a paste that just went wrong, so the text is kept in memory for a few minutes at most.
public struct RecentTranscript: Equatable, Sendable {
    public static let lifetime: TimeInterval = 5 * 60

    private var text: String?
    public private(set) var expiresAt: Date?

    public init() {}

    public mutating func store(_ text: String, at now: Date) {
        self.text = text
        expiresAt = now.addingTimeInterval(Self.lifetime)
    }

    // Checked on every use as well, since a Mac that slept may have missed the one-shot expiry.
    public mutating func text(at now: Date) -> String? {
        if let expiresAt, now >= expiresAt {
            clear()
        }
        return text
    }

    public mutating func clear() {
        text = nil
        expiresAt = nil
    }
}
