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
// -90 dBFS for a whole second; if the first second is, the input is dead and `add` says so, once.
final class InputMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var sampleRate: Double = 0
    private var frameCount = 0
    private var peakSoFar: Float = 0
    private var reportedSilentStart = false

    func reset(sampleRate: Double) {
        lock.lock()
        defer { lock.unlock() }
        self.sampleRate = sampleRate
        frameCount = 0
        peakSoFar = 0
        reportedSilentStart = false
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

    // Returns true exactly once per reset: when a full second has arrived and all of it was silent.
    func add(_ frames: UnsafeBufferPointer<Float>) -> Bool {
        var framePeak: Float = 0
        if let base = frames.baseAddress, frames.count > 0 {
            vDSP_maxmgv(base, 1, &framePeak, vDSP_Length(frames.count))
        }
        lock.lock()
        defer { lock.unlock() }
        frameCount += frames.count
        peakSoFar = max(peakSoFar, framePeak)
        guard !reportedSilentStart, sampleRate > 0, Double(frameCount) >= sampleRate,
              peakSoFar < SpeechCheck.silentInputPeak
        else { return false }
        reportedSilentStart = true
        return true
    }
}

// Passes an input through to the Mac's `AudioRecorder` while metering every frame it delivers.
final class MeteredAudioInput: AudioInput {
    private let input: DictationAudioInput
    private let meter: InputMeter
    private let onSilentStart: () -> Void

    init(_ input: DictationAudioInput, meter: InputMeter, onSilentStart: @escaping () -> Void) {
        self.input = input
        self.meter = meter
        self.onSilentStart = onSilentStart
    }

    func prepare() throws -> Double {
        let sampleRate = try input.prepare()
        meter.reset(sampleRate: sampleRate)
        return sampleRate
    }

    func start(onFrames: @escaping (UnsafeBufferPointer<Float>) -> Void) throws {
        let meter = self.meter
        let onSilentStart = self.onSilentStart
        try input.start { frames in
            onFrames(frames)
            if meter.add(frames) { onSilentStart() }
        }
    }

    func stop() {
        input.stop()
    }
}
