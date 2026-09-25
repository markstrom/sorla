import Accelerate
import AVFoundation

// The microphone side of the iPhone recorder: the Mac's `AudioInput`, plus a way to carry on after the
// engine's configuration changed mid-recording.
protocol DictationAudioInput: AudioInput {
    // Continues the running recording on a new engine, delivering to the same frames callback.
    // False when that isn't possible (the new input runs at another rate, so the audio can't be joined, or
    // it didn't start); the input is then stopped.
    func restart() -> Bool
}

// A new AVAudioEngine for every recording, made in `prepare()`, which the recorder calls only after the session
// is configured and active: the input format is read after activation and the tap is installed with it. An
// engine made earlier (at launch, before the category allowed input) or one that lived through a media-services
// reset can run and deliver nothing but zeros. Each engine is the Mac's `EngineAudioInput`, unchanged.
final class FreshEngineAudioInput: DictationAudioInput {
    private var engineInput: EngineAudioInput?
    private var sampleRate: Double = 0
    private var onFrames: ((UnsafeBufferPointer<Float>) -> Void)?

    func prepare() throws -> Double {
        engineInput?.stop()
        engineInput = nil
        let input = EngineAudioInput()
        sampleRate = try input.prepare()
        engineInput = input
        return sampleRate
    }

    func start(onFrames: @escaping (UnsafeBufferPointer<Float>) -> Void) throws {
        guard let engineInput else { throw AudioRecorderError.noInputDevice }
        self.onFrames = onFrames
        try engineInput.start(onFrames: onFrames)
    }

    func stop() {
        engineInput?.stop()
        engineInput = nil
        onFrames = nil
    }

    func restart() -> Bool {
        guard let onFrames else { return false }
        engineInput?.stop()
        engineInput = nil
        let input = EngineAudioInput()
        do {
            guard try input.prepare() == sampleRate else { return false }
            try input.start(onFrames: onFrames)
        } catch {
            return false
        }
        engineInput = input
        return true
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
