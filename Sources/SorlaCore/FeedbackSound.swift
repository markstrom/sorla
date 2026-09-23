import Foundation

public enum FeedbackSound {
    public static let sampleRate = 48_000
    public static let duration = 0.46
    public static let lowNote = 220.0
    public static let highNote = 329.63
    public static let noteDuration = 0.16
    public static let noteSpacing = 0.075
    public static let attack = 0.008
    public static let decayTime = 0.045
    public static let pitchBend = 0.03
    public static let pitchBendTime = 0.012
    public static let secondHarmonic = 0.08
    public static let echoDelay = 0.19
    public static let echoGain = 0.13
    public static let fadeOut = 0.01
    public static let peak: Float = 0.25

    public static func startSamples() -> [Float] {
        sequence([lowNote, highNote])
    }

    public static func stopSamples() -> [Float] {
        sequence([highNote, lowNote])
    }

    static func sequence(_ frequencies: [Double]) -> [Float] {
        let count = Int((duration * Double(sampleRate)).rounded())
        var dry = [Double](repeating: 0, count: count)
        for (position, frequency) in frequencies.enumerated() {
            let offset = Int((Double(position) * noteSpacing * Double(sampleRate)).rounded())
            for (index, value) in note(frequency).enumerated() where offset + index < count {
                dry[offset + index] += value
            }
        }

        let echoOffset = Int((echoDelay * Double(sampleRate)).rounded())
        let fadeCount = Int((fadeOut * Double(sampleRate)).rounded())
        var mixed = dry
        for index in echoOffset..<count {
            mixed[index] += dry[index - echoOffset] * echoGain
        }
        for index in 0..<fadeCount {
            mixed[count - 1 - index] *= Double(index) / Double(fadeCount)
        }

        let loudest = mixed.map(abs).max() ?? 1
        let scale = loudest > 0 ? Double(peak) / loudest : 0
        return mixed.map { Float($0 * scale) }
    }

    private static func note(_ frequency: Double) -> [Double] {
        let count = Int((noteDuration * Double(sampleRate)).rounded())
        var phase = 0.0
        return (0..<count).map { index in
            let seconds = Double(index) / Double(sampleRate)
            // A small downward settle at the onset gives the soft "drop" character.
            phase += 2 * Double.pi * frequency * (1 + pitchBend * exp(-seconds / pitchBendTime)) / Double(sampleRate)
            let envelope = min(1, seconds / attack) * exp(-seconds / decayTime)
            return envelope * (sin(phase) + secondHarmonic * sin(2 * phase))
        }
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
