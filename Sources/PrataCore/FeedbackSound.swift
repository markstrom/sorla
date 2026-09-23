import Foundation

public enum FeedbackSound {
    public static let sampleRate = 48_000
    public static let duration = 0.16
    public static let startFrequency = 520.0
    public static let endFrequency = 880.0
    public static let attack = 0.008
    public static let decayExponent = 1.5
    public static let secondHarmonic = 0.18
    public static let gain = 0.25

    public static func startSamples() -> [Float] {
        let count = Int((duration * Double(sampleRate)).rounded())
        let ratio = endFrequency / startFrequency
        let sweepScale = 2 * Double.pi * startFrequency * duration / log(ratio)
        return (0..<count).map { index in
            let seconds = Double(index) / Double(sampleRate)
            let progress = Double(index) / Double(count)
            // Integral of the exponential sweep f(t) = f0 * ratio^(t/T).
            let phase = sweepScale * (pow(ratio, progress) - 1)
            let envelope = min(1, seconds / attack) * pow(1 - progress, decayExponent)
            let signal = sin(phase) + secondHarmonic * sin(2 * phase)
            return Float(gain * envelope * signal)
        }
    }

    public static func stopSamples() -> [Float] {
        startSamples().reversed()
    }
}

public enum WAVEncoder {
    public static func encode(_ samples: [Float], sampleRate: Int) -> Data {
        let bytesPerSample = 2
        let dataSize = samples.count * bytesPerSample
        var data = Data(capacity: 44 + dataSize)
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + dataSize), to: &data)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16), to: &data)
        append(UInt16(1), to: &data)
        append(UInt16(1), to: &data)
        append(UInt32(sampleRate), to: &data)
        append(UInt32(sampleRate * bytesPerSample), to: &data)
        append(UInt16(bytesPerSample), to: &data)
        append(UInt16(16), to: &data)
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(dataSize), to: &data)
        for sample in samples {
            let clamped = max(-1, min(1, sample))
            append(UInt16(bitPattern: Int16((clamped * Float(Int16.max)).rounded())), to: &data)
        }
        return data
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
}
