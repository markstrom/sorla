import FluidAudio
import Foundation

// A dictation that ends without pasted text gets a brief cue, so it never just disappears.
public enum DictationCue: Equatable, Sendable {
    case microphoneMuted
    case nothingHeard
    case noText
    case textOnClipboard

    public var symbolName: String {
        switch self {
        case .microphoneMuted: return "mic.slash"
        case .nothingHeard: return "waveform.slash"
        case .noText: return "minus"
        case .textOnClipboard: return "doc.on.clipboard"
        }
    }

    // Without a Paste Last shortcut the text can still be pasted with ⌘V, since it is on the clipboard.
    public func announcement(pasteShortcut: String?) -> String {
        switch self {
        case .microphoneMuted:
            return String(localized: "Microphone seems to be muted", bundle: Localization.bundle)
        case .nothingHeard:
            return String(localized: "Nothing heard", bundle: Localization.bundle)
        case .noText:
            return String(localized: "No text", bundle: Localization.bundle)
        case .textOnClipboard:
            let shortcut = pasteShortcut ?? "⌘V"
            return String(localized: "Your text is on the clipboard — press \(shortcut)", bundle: Localization.bundle)
        }
    }

    // Only outcomes the user has to act on also get a notification.
    public func issue(pasteShortcut: String?) -> SorlaIssue? {
        switch self {
        case .microphoneMuted: return .microphoneMuted
        case .textOnClipboard: return .textOnClipboard(pasteShortcut: pasteShortcut ?? "⌘V")
        case .nothingHeard, .noText: return nil
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
    public static func assess(sampleCount: Int, peak: Float, deviceSeemsMuted: Bool = false) -> RecordingCheck {
        guard sampleCount > 0 else { return .empty }
        let seconds = Double(sampleCount) / Double(sampleRate)
        if MicrophoneMuteDetector.isDigitalSilence(peak: peak),
           deviceSeemsMuted || seconds >= MicrophoneMuteDetector.silenceDuration {
            return .digitalSilence
        }
        return sampleCount < minimumSampleCount ? .tooShort : .transcribable
    }
}

// A real room is never digitally silent, so sustained exact zeros mean the input is muted or turned all the way down.
public struct MicrophoneMuteDetector: Equatable, Sendable {
    public static let silencePeak: Float = 1e-6
    public static let silenceDuration: TimeInterval = 0.5

    public private(set) var isMuted = false
    private var silentSince: TimeInterval?
    private var hasHeardAudio = false

    public init(startedAt: TimeInterval) {
        silentSince = startedAt
    }

    // The device's own mute or zero volume counts at once, unless the take has already had audio.
    @discardableResult
    public mutating func applyDeviceState(_ state: InputDeviceState) -> Bool {
        guard state.seemsMuted, !hasHeardAudio, !isMuted else { return false }
        isMuted = true
        return true
    }

    public static func isDigitalSilence(peak: Float) -> Bool {
        peak < silencePeak
    }

    // Returns whether the muted state changed. Noise gates send exact zeros between words, so once a take has had audio it stays unmuted.
    @discardableResult
    public mutating func observe(peak: Float, at time: TimeInterval) -> Bool {
        let wasMuted = isMuted
        if Self.isDigitalSilence(peak: peak) {
            guard !hasHeardAudio else { return false }
            let since = silentSince ?? time
            silentSince = since
            if time - since >= Self.silenceDuration {
                isMuted = true
            }
        } else {
            hasHeardAudio = true
            silentSince = nil
            isMuted = false
        }
        return isMuted != wasMuted
    }
}
