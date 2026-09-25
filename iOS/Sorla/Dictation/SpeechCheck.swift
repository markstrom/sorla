import FluidAudio

// A trimmed-down copy of the Mac's RecordingCheck (Sources/SorlaCore/DictationCue.swift), which can't be
// compiled here without the Mac cue and menu types. To be shared properly in #67.
enum SpeechCheck: Equatable {
    case nothingToTranscribe
    case transcribable

    static let sampleRate = 16_000
    static let minimumSampleCount = ASRConstants.minimumRequiredSamples(forSampleRate: sampleRate)
    // A real room is never digitally silent; exact zeros mean a muted or unavailable input.
    static let silencePeak: Float = 1e-6

    static func assess(_ samples: [Float]) -> SpeechCheck {
        guard samples.count >= minimumSampleCount else { return .nothingToTranscribe }
        let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
        return peak < silencePeak ? .nothingToTranscribe : .transcribable
    }
}
