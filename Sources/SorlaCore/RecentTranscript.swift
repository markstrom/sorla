import Foundation

// Paste Last only recovers a paste that just went wrong, so the text is kept in memory for a few minutes at most.
public struct RecentTranscript: Equatable, Sendable {
    public static let lifetime: TimeInterval = 5 * 60

    private var text: String?
    // False while the text has reached no app, as when another app came forward (#85) or Accessibility was off:
    // then it exists only here, and a relaunch would lose it.
    public private(set) var isPasted = false
    public private(set) var expiresAt: Date?
    // Bumped by forget(), so a transcription that was in flight when the Mac locked is dropped too.
    public private(set) var generation = 0

    public init() {}

    public mutating func store(_ text: String, at now: Date) {
        self.text = text
        isPasted = false
        expiresAt = now.addingTimeInterval(Self.lifetime)
    }

    // Pasted, or left on the clipboard: either way it outlives a relaunch. Only for the text kept now.
    public mutating func markPasted(_ pasted: String) {
        if text == pasted { isPasted = true }
    }

    public mutating func hasUnpastedText(at now: Date) -> Bool {
        text(at: now) != nil && !isPasted
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
        isPasted = false
        expiresAt = nil
    }

    public mutating func forget() {
        clear()
        generation += 1
    }

    // A transcription begun before the last forget() may neither be pasted nor kept.
    public func accepts(from generation: Int) -> Bool {
        generation == self.generation
    }
}
