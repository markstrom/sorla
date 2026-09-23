public enum DictationPhase: Equatable, Sendable {
    case idle
    case recording
    case transcribing
}

public struct DictationPhaseTracker {
    public private(set) var phase: DictationPhase = .idle
    private var ownerID = 0

    public init() {}

    public mutating func beginRecording() -> Int {
        ownerID += 1
        phase = .recording
        return ownerID
    }

    @discardableResult
    public mutating func release(_ id: Int) -> Bool {
        transition(id, from: .recording, to: .transcribing)
    }

    @discardableResult
    public mutating func cancel(_ id: Int) -> Bool {
        transition(id, from: .recording, to: .idle)
    }

    @discardableResult
    public mutating func finish(_ id: Int) -> Bool {
        transition(id, from: .transcribing, to: .idle)
    }

    private mutating func transition(_ id: Int, from expected: DictationPhase, to next: DictationPhase) -> Bool {
        guard id == ownerID, phase == expected else { return false }
        phase = next
        return true
    }
}
