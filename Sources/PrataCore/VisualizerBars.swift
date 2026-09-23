import CoreGraphics
import Foundation

public enum VisualizerBars {
    public static let barCount = 15
    private static let perceptualExponent: Float = 0.7
    private static let motionCenter = 0.925
    private static let motionAmplitude = 0.075
    private static let motionFrequency = 2.0
    private static let phaseStep = 0.9
    private static let shimmerPeriod = 1.1
    private static let shimmerWidth = 2.2

    public static func band(forBar index: Int) -> Int {
        min(abs(index - barCount / 2), 7)
    }

    public static func magnitudes(bands: SIMD8<Float>, time: TimeInterval, reduceMotion: Bool) -> [Float] {
        // Reduce the time in Double first; Float(timeIntervalSinceReferenceDate) has ~1 min resolution.
        let phase = reduceMotion ? 0 : (time * motionFrequency).truncatingRemainder(dividingBy: 2 * .pi)
        return (0..<barCount).map { index in
            let band = band(forBar: index)
            let boosted = pow(clamped(bands[band]), perceptualExponent)
            let motion = reduceMotion ? 1 : Float(motionCenter + motionAmplitude * sin(phase + Double(band) * phaseStep))
            return clamped(boosted * motion)
        }
    }

    public static func height(forMagnitude magnitude: Float, minHeight: CGFloat, maxHeight: CGFloat) -> CGFloat {
        minHeight + CGFloat(clamped(magnitude)) * (maxHeight - minHeight)
    }

    public static func heights(
        bands: SIMD8<Float>,
        time: TimeInterval,
        minHeight: CGFloat,
        maxHeight: CGFloat,
        reduceMotion: Bool
    ) -> [CGFloat] {
        magnitudes(bands: bands, time: time, reduceMotion: reduceMotion).map {
            height(forMagnitude: $0, minHeight: minHeight, maxHeight: maxHeight)
        }
    }

    public static func shimmer(time: TimeInterval, reduceMotion: Bool) -> [Float] {
        guard !reduceMotion else { return Array(repeating: 0, count: barCount) }
        let progress = time.truncatingRemainder(dividingBy: shimmerPeriod) / shimmerPeriod
        let position = progress * (Double(barCount) + 2 * shimmerWidth) - shimmerWidth
        return (0..<barCount).map { index in
            let distance = (Double(index) - position) / shimmerWidth
            return clamped(Float(exp(-distance * distance)))
        }
    }

    private static func clamped(_ value: Float) -> Float {
        value > 0 ? min(value, 1) : 0
    }
}
