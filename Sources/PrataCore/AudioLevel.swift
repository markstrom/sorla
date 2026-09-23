import Foundation

public enum AudioLevel {
    private static let minimumDecibels: Float = -50
    private static let maximumDecibels: Float = 0

    public static func rms(_ samples: UnsafeBufferPointer<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for sample in samples {
            sum += sample * sample
        }
        return (sum / Float(samples.count)).squareRoot()
    }

    public static func normalized(rms: Float) -> Float {
        guard rms > 0 else { return 0 }
        let decibels = 20 * log10(rms)
        let clamped = min(max(decibels, minimumDecibels), maximumDecibels)
        return (clamped - minimumDecibels) / (maximumDecibels - minimumDecibels)
    }
}
