import ActivityKit
import Foundation

// Compiled into both the app and the Live Activity extension; it carries no audio and no text.
struct DictationActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: DictationActivityPhase
        var startedAt: Date
    }
}

enum DictationActivityPhase: String, Codable, Hashable {
    case listening
    // Capture ended by itself (time limit, call, route change); the next trigger transcribes what was heard.
    case captured
    case transcribing

    var title: String {
        switch self {
        case .listening: return "Listening"
        case .captured: return "Stopped — trigger again to transcribe"
        case .transcribing: return "Transcribing"
        }
    }

    var symbolName: String {
        switch self {
        case .listening: return "mic.fill"
        case .captured: return "pause.circle"
        case .transcribing: return "text.bubble"
        }
    }

    var isCancellable: Bool { self != .transcribing }
}
