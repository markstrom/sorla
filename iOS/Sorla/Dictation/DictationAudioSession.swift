import AVFoundation

// How the dictation's audio session is set up: `.record` with `.allowBluetoothHFP`, not mixable. A recording
// always starts with Sorla in the foreground (iOS refuses to start audio input from the background, even through
// an AudioRecordingIntent: kAUStartIO failed with 2003329396 on an iPhone 16 Plus, iOS 27.0), so the session
// doesn't have to be mixable. The mixable `.playAndRecord` + `.mixWithOthers` setup tried before delivered only
// zeros in the foreground on the same phone; this is the configuration that captured real speech there.
struct DictationSessionConfiguration: Equatable {
    var category: AVAudioSession.Category
    var mode: AVAudioSession.Mode
    var options: AVAudioSession.CategoryOptions

    static let dictation = DictationSessionConfiguration(
        category: .record,
        mode: .default,
        options: [.allowBluetoothHFP]
    )
}

// What the session looked like when a dictation started; numbers and names only, never audio or text.
struct AudioSessionSnapshot: Equatable {
    var category: AVAudioSession.Category
    var mode: AVAudioSession.Mode
    var options: AVAudioSession.CategoryOptions
    var inputPort: AVAudioSession.Port?
    var sampleRate: Double
    var inputChannels: Int
    // Whether the session reports an input at all, and whether another app's audio was playing: the two things
    // that differ between a start right after Sorla comes forward and one from inside the app.
    var isInputAvailable = true
    var isOtherAudioPlaying = false

    var summary: String {
        let port = inputPort.map { $0.rawValue } ?? "none"
        return "category \(Self.shortName(category.rawValue, prefix: "AVAudioSessionCategory")), "
            + "mode \(Self.shortName(mode.rawValue, prefix: "AVAudioSessionMode")), "
            + "options \(Self.names(of: options)), input \(port), "
            + "\(Int(sampleRate.rounded())) Hz, \(inputChannels) ch, "
            + "input available \(isInputAvailable ? "yes" : "no"), other audio \(isOtherAudioPlaying ? "yes" : "no")"
    }

    private static func shortName(_ raw: String, prefix: String) -> String {
        guard raw.hasPrefix(prefix) else { return raw }
        let name = raw.dropFirst(prefix.count)
        return name.prefix(1).lowercased() + name.dropFirst()
    }

    // interruptSpokenAudioAndMixWithOthers includes the mixWithOthers bit, so it is named first.
    private static let optionNames: [(AVAudioSession.CategoryOptions, String)] = [
        (.interruptSpokenAudioAndMixWithOthers, "interruptSpokenAudioAndMixWithOthers"),
        (.mixWithOthers, "mixWithOthers"),
        (.duckOthers, "duckOthers"),
        (.allowBluetoothHFP, "allowBluetoothHFP"),
        (.allowBluetoothA2DP, "allowBluetoothA2DP"),
        (.allowAirPlay, "allowAirPlay"),
        (.defaultToSpeaker, "defaultToSpeaker"),
        (.overrideMutedMicrophoneInterruption, "overrideMutedMicrophoneInterruption"),
    ]

    static func names(of options: AVAudioSession.CategoryOptions) -> String {
        var rest = options
        var names: [String] = []
        for (option, name) in optionNames where rest.contains(option) {
            names.append(name)
            rest.remove(option)
        }
        if !rest.isEmpty { names.append(String(format: "0x%lx", rest.rawValue)) }
        return names.isEmpty ? "none" : names.joined(separator: "+")
    }
}

// The session calls the recorder makes, so the order (configure, activate, then the engine) is testable.
@MainActor
protocol DictationAudioSession: AnyObject {
    func configure(_ configuration: DictationSessionConfiguration) throws
    func activate() throws
    func deactivate()
    func snapshot() -> AudioSessionSnapshot
}

@MainActor
final class SystemDictationAudioSession: DictationAudioSession {
    nonisolated init() {}

    private var session: AVAudioSession { .sharedInstance() }

    func configure(_ configuration: DictationSessionConfiguration) throws {
        try session.setCategory(configuration.category, mode: configuration.mode, options: configuration.options)
    }

    func activate() throws {
        try session.setActive(true)
    }

    func deactivate() {
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    func snapshot() -> AudioSessionSnapshot {
        AudioSessionSnapshot(
            category: session.category,
            mode: session.mode,
            options: session.categoryOptions,
            inputPort: session.currentRoute.inputs.first?.portType,
            sampleRate: session.sampleRate,
            inputChannels: session.inputNumberOfChannels,
            isInputAvailable: session.isInputAvailable,
            isOtherAudioPlaying: session.isOtherAudioPlaying
        )
    }
}
