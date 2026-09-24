public enum DictationPhase: Equatable, Sendable {
    case idle
    case recording
    case transcribing
}

// An older dictation can still be transcribing while a newer one records, so each in-flight ID is tracked.
public struct DictationPhaseTracker {
    private var lastID = 0
    private var recordingID: Int?
    private var transcribingIDs: Set<Int> = []

    public init() {}

    public var phase: DictationPhase {
        if recordingID != nil { return .recording }
        return transcribingIDs.isEmpty ? .idle : .transcribing
    }

    public mutating func beginRecording() -> Int {
        lastID += 1
        recordingID = lastID
        return lastID
    }

    // Each transition returns whether the phase changed, so observers only hear real changes.
    @discardableResult
    public mutating func release(_ id: Int) -> Bool {
        let before = phase
        guard recordingID == id else { return false }
        recordingID = nil
        transcribingIDs.insert(id)
        return phase != before
    }

    @discardableResult
    public mutating func cancel(_ id: Int) -> Bool {
        let before = phase
        guard recordingID == id else { return false }
        recordingID = nil
        return phase != before
    }

    @discardableResult
    public mutating func finish(_ id: Int) -> Bool {
        let before = phase
        guard transcribingIDs.remove(id) != nil else { return false }
        return phase != before
    }
}
