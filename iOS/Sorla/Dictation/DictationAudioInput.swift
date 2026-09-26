import Accelerate
import AVFoundation

// What an input did when asked to carry on after its engine stopped itself on a configuration change.
enum InputResumption: Equatable {
    case continued
    // The input now runs at another rate, so the audio can't be joined; the input is stopped.
    case rateChanged
    // The input is stopped; the reason is a system error or name, never audio.
    case failed(String)
}

// The microphone side of the iPhone recorder: the Mac's `AudioInput`, plus what a long-lived engine needs.
protocol DictationAudioInput: AudioInput {
    // Engine and formats as of the last prepare or resume (numbers only), for the diagnostic.engine row.
    var preparation: String { get }
    // Carries on after the engine stopped itself on a configuration change, delivering to the same frames callback.
    func resume() -> InputResumption
    // Forgets the engine (it doesn't survive a media-services reset); the next prepare makes a new one.
    func discardEngine()
}

// One AVAudioEngine for the life of the process, made by the first `prepare()`, which the recorder calls only
// once the session is configured for input and active. The engine used to be made at launch, while the category
// was still the default playback-only one, and the first recording after launch then delivered only zeros while
// later ones on the same engine worked. The format is read again on every prepare, so a route that changed
// between recordings gets the right tap. The engine is only reset on a real configuration change.
final class SharedEngineAudioInput: DictationAudioInput {
    private var engine: AVAudioEngine?
    private var format: AVAudioFormat?
    private var onFrames: ((UnsafeBufferPointer<Float>) -> Void)?
    private var recordings = 0
    private(set) var preparation = "no engine"

    func prepare() throws -> Double {
        let isNew = engine == nil
        let engine = self.engine ?? AVAudioEngine()
        self.engine = engine
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        let format = input.inputFormat(forBus: 0)
        recordings = isNew ? 1 : recordings + 1
        preparation = "engine \(isNew ? "new" : "reused, recording \(recordings)"), "
            + "input \(Self.describe(format)), node output \(Self.describe(input.outputFormat(forBus: 0)))"
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioRecorderError.noInputDevice
        }
        self.format = format
        return format.sampleRate
    }

    func start(onFrames: @escaping (UnsafeBufferPointer<Float>) -> Void) throws {
        guard let engine, let format else { throw AudioRecorderError.noInputDevice }
        try run(engine, format: format, onFrames: onFrames)
        self.onFrames = onFrames
    }

    func stop() {
        onFrames = nil
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    func resume() -> InputResumption {
        guard let engine, let format, let onFrames else { return .failed("not recording") }
        stop()
        engine.reset()
        let current = engine.inputNode.inputFormat(forBus: 0)
        preparation = "engine reset, input \(Self.describe(current))"
        guard current.channelCount > 0 else { return .failed("no input") }
        guard current.sampleRate == format.sampleRate else { return .rateChanged }
        do {
            try run(engine, format: current, onFrames: onFrames)
        } catch {
            return .failed(String(describing: error))
        }
        self.format = current
        self.onFrames = onFrames
        return .continued
    }

    func discardEngine() {
        stop()
        engine = nil
        format = nil
        preparation = "no engine"
    }

    private func run(
        _ engine: AVAudioEngine, format: AVAudioFormat, onFrames: @escaping (UnsafeBufferPointer<Float>) -> Void
    ) throws {
        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(SpectrumAnalyzer.frameCount), format: format) { buffer, _ in
            guard let channelData = buffer.floatChannelData else { return }
            onFrames(UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength)))
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
    }

    private static func describe(_ format: AVAudioFormat) -> String {
        let layout = format.isInterleaved ? "interleaved" : "deinterleaved"
        return "\(Int(format.sampleRate.rounded())) Hz \(format.channelCount) ch \(format.commonFormat.name) \(layout)"
    }
}

private extension AVAudioCommonFormat {
    var name: String {
        switch self {
        case .pcmFormatFloat32: return "float32"
        case .pcmFormatFloat64: return "float64"
        case .pcmFormatInt16: return "int16"
        case .pcmFormatInt32: return "int32"
        case .otherFormat: return "other"
        @unknown default: return "unknown"
        }
    }
}

// Watches the level of what the microphone delivers, from the audio thread. A real microphone is never below
// -90 dBFS for a whole silence window; if the start of an input is, the input is dead and `add` says so, once.
// It also says, once, when the first sound arrives, so a restart that recovered can be timed.
final class InputMeter: @unchecked Sendable {
    enum Event: Equatable {
        // The whole silence window arrived and all of it was below -90 dBFS.
        case silentStart
        // The first frame at or above -90 dBFS.
        case firstSound
    }

    private let lock = NSLock()
    private var sampleRate: Double = 0
    private var window: Double = 1
    private var frameCount = 0
    private var peakSoFar: Float = 0
    private var reported = false

    // How many seconds of silence count as a dead input; set on the main actor before the input is prepared, and
    // taken over by the next reset.
    var silenceWindow: Double = 1

    func reset(sampleRate: Double) {
        lock.lock()
        defer { lock.unlock() }
        self.sampleRate = sampleRate
        window = silenceWindow
        frameCount = 0
        peakSoFar = 0
        reported = false
    }

    var peak: Float {
        lock.lock()
        defer { lock.unlock() }
        return peakSoFar
    }

    var seconds: Double {
        lock.lock()
        defer { lock.unlock() }
        return sampleRate > 0 ? Double(frameCount) / sampleRate : 0
    }

    // Whether the input as it stands now started silent, checked again on the main actor since a reported event
    // may belong to an input that has been started over since.
    var isSilentStart: Bool {
        lock.lock()
        defer { lock.unlock() }
        return sampleRate > 0 && Double(frameCount) >= window * sampleRate && peakSoFar < SpeechCheck.silentInputPeak
    }

    // Returns an event at most once per reset: the input either starts silent or it has sound.
    func add(_ frames: UnsafeBufferPointer<Float>) -> Event? {
        var framePeak: Float = 0
        if let base = frames.baseAddress, frames.count > 0 {
            vDSP_maxmgv(base, 1, &framePeak, vDSP_Length(frames.count))
        }
        lock.lock()
        defer { lock.unlock() }
        frameCount += frames.count
        peakSoFar = max(peakSoFar, framePeak)
        guard !reported, sampleRate > 0 else { return nil }
        if peakSoFar >= SpeechCheck.silentInputPeak {
            reported = true
            return .firstSound
        }
        guard Double(frameCount) >= window * sampleRate else { return nil }
        reported = true
        return .silentStart
    }
}

// Passes an input through to the Mac's `AudioRecorder` while metering every frame it delivers.
final class MeteredAudioInput: AudioInput {
    private let input: DictationAudioInput
    private let meter: InputMeter
    private let onEvent: (InputMeter.Event) -> Void

    init(_ input: DictationAudioInput, meter: InputMeter, onEvent: @escaping (InputMeter.Event) -> Void) {
        self.input = input
        self.meter = meter
        self.onEvent = onEvent
    }

    func prepare() throws -> Double {
        let sampleRate = try input.prepare()
        meter.reset(sampleRate: sampleRate)
        return sampleRate
    }

    func start(onFrames: @escaping (UnsafeBufferPointer<Float>) -> Void) throws {
        let meter = self.meter
        let onEvent = self.onEvent
        try input.start { frames in
            onFrames(frames)
            if let event = meter.add(frames) { onEvent(event) }
        }
    }

    func stop() {
        input.stop()
    }
}
