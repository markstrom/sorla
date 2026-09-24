// Everything a dictation may still have in flight, including work the indicator no longer shows.
public struct DictationActivity: Equatable, Sendable {
    public var isRecording: Bool
    public var isCapturingTail: Bool
    public var isTranscribing: Bool
    public var pendingDeliveries: Int
    public var isPasteLastInFlight: Bool
    public var isRestoringClipboard: Bool

    public init(
        isRecording: Bool = false,
        isCapturingTail: Bool = false,
        isTranscribing: Bool = false,
        pendingDeliveries: Int = 0,
        isPasteLastInFlight: Bool = false,
        isRestoringClipboard: Bool = false
    ) {
        self.isRecording = isRecording
        self.isCapturingTail = isCapturingTail
        self.isTranscribing = isTranscribing
        self.pendingDeliveries = pendingDeliveries
        self.isPasteLastInFlight = isPasteLastInFlight
        self.isRestoringClipboard = isRestoringClipboard
    }

    public static let quiet = DictationActivity()

    // Only then can Sorla quit or be replaced without losing words or the user's clipboard.
    public var isQuiet: Bool {
        self == .quiet
    }
}
