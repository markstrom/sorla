import AVFoundation
import FluidAudio

public enum AudioRecorderError: Error {
    case bufferAllocationFailed
}

public final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var sampleRate: Double = 0
    private var samples: [Float] = []
    private let lock = NSLock()

    public init() {}

    public func start() throws {
        lock.lock()
        samples.removeAll()
        lock.unlock()

        let input = engine.inputNode
        input.removeTap(onBus: 0)
        let format = input.inputFormat(forBus: 0)
        sampleRate = format.sampleRate

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
    }

    public func stop() throws -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        lock.lock()
        let captured = samples
        lock.unlock()

        guard !captured.isEmpty else { return [] }
        return try Self.resample(captured, sampleRate: sampleRate)
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        let channel0 = UnsafeBufferPointer(start: channelData[0], count: frameLength)

        lock.lock()
        samples.append(contentsOf: channel0)
        lock.unlock()
    }

    static func resample(_ nativeSamples: [Float], sampleRate: Double) throws -> [Float] {
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
