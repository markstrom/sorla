import FluidAudio
import Foundation

// A dictation that ends without pasted text gets a brief cue, so it never just disappears.
public enum DictationCue: Equatable, Sendable {
    case microphoneMuted
    case nothingHeard
    case noText
    case textOnClipboard
    // A blocked paste whose text Sorla kept for Paste Last; the clipboard is as the user left it (#72).
    case textKept
    case releaseKeys
    // Paste Last asked for with nothing kept: it expired, was forgotten at a lock, or nothing was dictated yet.
    case nothingToPaste
    case cancelled
    // Sorla was replaced on disk: pressed when it can reopen itself nothing is recorded, and a paste is dropped (#72).
    case restartNeeded
    case waitingForModel(String)
    case failed(String)

    // Only a failed start or finish has a cue; the model's own failures stay in the menu.
    public init?(issue: SorlaIssue) {
        switch issue {
        case .microphoneAccessNeeded:
            self = .failed(issue.menuTitle)
        case .noInputDevice:
            self = .failed(String(localized: "No microphone found", bundle: Localization.bundle))
        case .transcriptionFailed:
            self = .failed(String(localized: "Couldn't transcribe the recording", bundle: Localization.bundle))
        case .appReplaced:
            self = .restartNeeded
        // Whether the text was kept decides it; see blockedPaste(isTextKept:).
        case .accessibilityAccessNeeded, .microphoneMuted, .textOnClipboard, .modelNotLoaded, .modelDownloadFailed, .modelUpdateFailed:
            return nil
        }
    }

    // A blocked paste never touches the clipboard, so the text is either kept for Paste Last or gone (#72).
    public static func blockedPaste(isTextKept: Bool) -> DictationCue {
        isTextKept ? .textKept : .failed(String(localized: "Couldn't paste — the text wasn't saved", bundle: Localization.bundle))
    }

    public var symbolName: String {
        switch self {
        case .microphoneMuted: return "mic.slash"
        case .nothingHeard: return "waveform.slash"
        case .noText: return "minus"
        case .textOnClipboard: return "doc.on.clipboard"
        case .textKept: return "doc.text"
        case .releaseKeys: return "keyboard"
        case .nothingToPaste: return "clipboard"
        case .cancelled: return "xmark"
        case .restartNeeded: return "arrow.clockwise"
        case .waitingForModel: return "hourglass"
        case .failed: return "exclamationmark.triangle"
        }
    }

    // Without a way to Paste Last the text can still be pasted with ⌘V, since it is on the clipboard.
    public func announcement(pasteLast: PasteLastRoute?) -> String {
        switch self {
        case .microphoneMuted:
            return String(localized: "Microphone seems to be muted", bundle: Localization.bundle)
        case .nothingHeard:
            return String(localized: "Nothing heard", bundle: Localization.bundle)
        case .noText:
            return String(localized: "No text", bundle: Localization.bundle)
        case .textOnClipboard:
            guard pasteLast != .menu else {
                return String(localized: "Your text is on the clipboard — choose Paste Last Transcription in Sorla's menu (VO-M twice)", bundle: Localization.bundle)
            }
            let shortcut = pasteLast?.keys ?? "⌘V"
            return String(localized: "Your text is on the clipboard — press \(shortcut)", bundle: Localization.bundle)
        case .textKept:
            return String(localized: "Couldn't paste — Sorla has kept your text", bundle: Localization.bundle)
        case .releaseKeys:
            switch pasteLast {
            case .menu:
                return String(localized: "Let go of the keys and choose Paste Last Transcription in Sorla's menu (VO-M twice)", bundle: Localization.bundle)
            case .shortcut(let shortcut):
                return String(localized: "Let go of the keys and press \(shortcut) again", bundle: Localization.bundle)
            case nil:
                return String(localized: "Let go of the keys and try again", bundle: Localization.bundle)
            }
        // Names no way to paste, so it reads the same with VoiceOver.
        case .nothingToPaste:
            return String(localized: "Nothing to paste", bundle: Localization.bundle)
        case .cancelled:
            return String(localized: "Recording cancelled", bundle: Localization.bundle)
        case .restartNeeded:
            return String(localized: "Sorla has been updated and needs to restart", bundle: Localization.bundle)
        case .waitingForModel(let message), .failed(let message):
            return message
        }
    }

    // Only outcomes the user has to act on also leave an explanation in the menu.
    public func issue(pasteLast: PasteLastRoute?) -> SorlaIssue? {
        switch self {
        case .microphoneMuted: return .microphoneMuted
        case .textOnClipboard: return .textOnClipboard(pasteLast: pasteLast)
        case .textKept, .nothingHeard, .noText, .releaseKeys, .nothingToPaste, .cancelled, .restartNeeded, .waitingForModel, .failed: return nil
        }
    }
}

public enum RecordingCheck: Equatable, Sendable {
    case empty
    case tooShort
    case digitalSilence
    case transcribable

    static let sampleRate = 16_000
    static let minimumSampleCount = ASRConstants.minimumRequiredSamples(forSampleRate: sampleRate)

    // The first buffers of a starting input can be zeros, so a short silent take isn't blamed on a muted microphone.
    public static func assess(
        sampleCount: Int,
        peak: Float,
        deviceSeemsMuted: Bool = false,
        minimumSilence: TimeInterval = MicrophoneMuteDetector.silenceDuration
    ) -> RecordingCheck {
        guard sampleCount > 0 else { return .empty }
        let seconds = Double(sampleCount) / Double(sampleRate)
        if MicrophoneMuteDetector.isDigitalSilence(peak: peak),
           deviceSeemsMuted || seconds >= minimumSilence {
            return .digitalSilence
        }
        return sampleCount < minimumSampleCount ? .tooShort : .transcribable
    }
}

// A real room is never digitally silent, so sustained exact zeros mean the input is muted or turned all the way down.
public struct MicrophoneMuteDetector: Equatable, Sendable {
    public static let silencePeak: Float = 1e-6
    public static let silenceDuration: TimeInterval = 0.5
    // A Bluetooth (HFP) route can deliver zeros for a while after it starts.
    public static let routeStartupGrace: TimeInterval = 1.0

    public private(set) var isMuted = false
    private var firstBufferAt: TimeInterval?
    private var hasHeardAudio = false
    private var isKnownWiredRoute = false

    public init() {}

    // Until the device is known not to be Bluetooth, the silence has to outlast its startup.
    public var requiredSilence: TimeInterval {
        isKnownWiredRoute ? Self.silenceDuration : Self.silenceDuration + Self.routeStartupGrace
    }

    // The device's own mute or zero volume counts at once, unless the take has already had audio.
    @discardableResult
    public mutating func applyDeviceState(_ state: InputDeviceState) -> Bool {
        isKnownWiredRoute = state.isBluetooth == false
        guard state.seemsMuted, !hasHeardAudio, !isMuted else { return false }
        isMuted = true
        return true
    }

    public static func isDigitalSilence(peak: Float) -> Bool {
        peak < silencePeak
    }

    // Returns whether the muted state changed. The clock starts at the first buffer, not at the key press.
    // Noise gates send exact zeros between words, so once a take has had audio it stays unmuted.
    @discardableResult
    public mutating func observe(peak: Float, at time: TimeInterval) -> Bool {
        let wasMuted = isMuted
        let firstBufferAt = self.firstBufferAt ?? time
        self.firstBufferAt = firstBufferAt
        if Self.isDigitalSilence(peak: peak) {
            guard !hasHeardAudio else { return false }
            if time - firstBufferAt >= requiredSilence {
                isMuted = true
            }
        } else {
            hasHeardAudio = true
            isMuted = false
        }
        return isMuted != wasMuted
    }
}
