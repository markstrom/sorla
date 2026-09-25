import FluidAudio

// A trimmed-down copy of the Mac's RecordingCheck (Sources/SorlaCore/DictationCue.swift), which can't be
// compiled here without the Mac cue and menu types. To be shared properly in #67.
enum SpeechCheck: Equatable {
    case nothingToTranscribe
    // Long enough to hold speech, but the microphone delivered (effectively) nothing: a dead or silenced input,
    // which is a failure to report, not a quiet user.
    case silentInput
    case transcribable

    static let sampleRate = 16_000
    static let minimumSampleCount = ASRConstants.minimumRequiredSamples(forSampleRate: sampleRate)
    // -90 dBFS. A real room through a real microphone never stays below this; exact zeros, or a residue of
    // conversion noise below it, mean a muted, silenced or unavailable input.
    static let silentInputPeak: Float = 3.1622776e-5

    static func assess(_ samples: [Float]) -> SpeechCheck {
        guard samples.count >= minimumSampleCount else { return .nothingToTranscribe }
        let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
        return peak < silentInputPeak ? .silentInput : .transcribable
    }
}
