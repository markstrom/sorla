import Accelerate
import AVFoundation
import FluidAudio

public enum AudioRecorderError: Error {
    case bufferAllocationFailed
    case noInputDevice
}

public struct AudioBufferSummary: Equatable, Sendable {
    public let spectrum: SIMD8<Float>
    public let peak: Float
    public let time: TimeInterval

    // Buffers merged into one main-actor hop keep the newest spectrum but the loudest peak, so no audio is missed.
    static func coalescing(_ older: AudioBufferSummary, _ newer: AudioBufferSummary) -> AudioBufferSummary {
        AudioBufferSummary(spectrum: newer.spectrum, peak: max(older.peak, newer.peak), time: newer.time)
    }
}

// The microphone side of a recording, so the recorder can be driven without one.
public protocol AudioInput: AnyObject {
    // Returns the input's sample rate; frames delivered after start() are channel 0 at that rate.
    func prepare() throws -> Double
    func start(onFrames: @escaping (UnsafeBufferPointer<Float>) -> Void) throws
    func stop()
}

public final class EngineAudioInput: AudioInput {
    private let engine = AVAudioEngine()
    private var format: AVAudioFormat?

    public init() {}

    public func prepare() throws -> Double {
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioRecorderError.noInputDevice
        }
        self.format = format
        return format.sampleRate
    }

    public func start(onFrames: @escaping (UnsafeBufferPointer<Float>) -> Void) throws {
        guard let format else { throw AudioRecorderError.noInputDevice }
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

    public func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}

public final class AudioRecorder {
    private let input: AudioInput
    private let resample: ([Float], Double) throws -> [Float]
    private var sampleRate: Double = 0
    private var samples: [Float] = []
    private let lock = NSLock()
    private var analyzer: SpectrumAnalyzer?

    public var onBuffer: (@Sendable (AudioBufferSummary) -> Void)?

    public init(
        input: AudioInput = EngineAudioInput(),
        resample: @escaping ([Float], Double) throws -> [Float] = { try AudioRecorder.resample($0, sampleRate: $1) }
    ) {
        self.input = input
        self.resample = resample
    }

    // What the recorder itself still holds; the audio should live only as long as its transcription needs it.
    var heldSampleCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return samples.count
    }

    public func start() throws {
        _ = takeSamples()

        let sampleRate = try input.prepare()
        self.sampleRate = sampleRate
        if analyzer?.sampleRate != sampleRate {
            analyzer = SpectrumAnalyzer(sampleRate: sampleRate)
        }
        let analyzer = self.analyzer

        try input.start { [weak self] frames in
            self?.append(frames, analyzer: analyzer)
        }
    }

    // The recorder lets go of the audio before resampling, so a failed conversion can't leave it behind.
    public func stop() throws -> [Float] {
        input.stop()
        let captured = takeSamples()
        guard !captured.isEmpty else { return [] }
        return try resample(captured, sampleRate)
    }

    // A cancelled recording is never transcribed, so its audio is dropped without resampling.
    public func cancel() {
        input.stop()
        _ = takeSamples()
    }

    private func takeSamples() -> [Float] {
        var captured: [Float] = []
        lock.lock()
        swap(&captured, &samples)
        lock.unlock()
        return captured
    }

    private func append(_ channel0: UnsafeBufferPointer<Float>, analyzer: SpectrumAnalyzer?) {
        lock.lock()
        samples.append(contentsOf: channel0)
        lock.unlock()

        let frameLength = channel0.count
        if let onBuffer, let analyzer, let base = channel0.baseAddress, frameLength > 0 {
            var peak: Float = 0
            vDSP_maxmgv(base, 1, &peak, vDSP_Length(frameLength))
            onBuffer(AudioBufferSummary(
                spectrum: analyzer.analyze(channel0),
                peak: peak,
                time: ProcessInfo.processInfo.systemUptime
            ))
        }
    }

    public static func resample(_ nativeSamples: [Float], sampleRate: Double) throws -> [Float] {
        guard !nativeSamples.isEmpty else { return [] }

        guard
            let monoFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
            let buffer = AVAudioPCMBuffer(
                pcmFormat: monoFormat,
                frameCapacity: AVAudioFrameCount(nativeSamples.count)
            )
        else {
            throw AudioRecorderError.bufferAllocationFailed
        }
        buffer.frameLength = buffer.frameCapacity

        nativeSamples.withUnsafeBufferPointer { pointer in
            buffer.floatChannelData![0].update(from: pointer.baseAddress!, count: nativeSamples.count)
        }

        return try AudioConverter().resampleBuffer(buffer)
    }
}
