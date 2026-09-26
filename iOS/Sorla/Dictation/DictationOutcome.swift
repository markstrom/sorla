import Foundation

// What one trigger of the toggle did. Only `.transcribed` with text may reach the clipboard.
enum DictationOutcome: Equatable, Sendable {
    case started
    case transcribed(String)
    case nothingHeard
    case cancelled
    // A trigger while a transcription is still running; the running one keeps its result.
    case busy
    case failed(DictationFailure)

    var textToCopy: String? {
        guard case .transcribed(let text) = self, !text.isEmpty else { return nil }
        return text
    }

    // Stable, text-free name for logs and the Shortcut's outcome.
    var kind: String {
        switch self {
        case .started: return "started"
        case .transcribed: return "transcribed"
        case .nothingHeard: return "nothingHeard"
        case .cancelled: return "cancelled"
        case .busy: return "busy"
        case .failed(let failure): return "failed.\(failure.rawValue)"
        }
    }

    var message: String {
        switch self {
        case .started: return "Listening. Trigger again to stop."
        case .transcribed: return "Transcribed and ready to paste."
        case .nothingHeard: return "Nothing heard. The clipboard is unchanged."
        case .cancelled: return "Dictation cancelled. The clipboard is unchanged."
        case .busy: return "Still transcribing the previous dictation."
        case .failed(let failure): return failure.message
        }
    }
}

enum DictationFailure: String, Equatable, Sendable, CaseIterable {
    case microphoneNotAuthorized
    case modelMissing
    case liveActivityUnavailable
    case audioStartFailed
    // Starting needs Sorla in the foreground, and iOS didn't let it come forward (or the person declined).
    case foregroundUnavailable
    // The microphone ran but delivered only silence (below -90 dBFS), so there was nothing to transcribe.
    case silentInput
    // The process that was recording is gone (terminated by the system or force-quit).
    case sessionLost
    case transcriptionFailed
    case timedOut
    case backgroundTimeExpired

    var message: String {
        switch self {
        case .microphoneNotAuthorized: return "Open Sorla and allow the microphone."
        case .modelMissing: return "Open Sorla and install the speech model."
        case .liveActivityUnavailable: return "Turn on Live Activities for Sorla in Settings."
        case .audioStartFailed: return "The microphone couldn't start."
        case .foregroundUnavailable: return "Sorla has to open to start listening. Unlock the iPhone and try again."
        case .silentInput: return "The microphone delivered no sound."
        case .sessionLost: return "The last recording was interrupted. Trigger again to start a new one."
        case .transcriptionFailed: return "The recording couldn't be transcribed."
        case .timedOut: return "Transcription took too long and was stopped."
        case .backgroundTimeExpired: return "iOS stopped the transcription in the background."
        }
    }
}

// Why capture ended before the user stopped it. The audio so far is kept for the next trigger.
enum CaptureEnd: String, Equatable, Sendable {
    case limitReached
    case interrupted
    case routeChanged
}

enum DictationPhase: Equatable, Sendable {
    case idle
    case listening
    case captured(CaptureEnd)
    case transcribing
}
