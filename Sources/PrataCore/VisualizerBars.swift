import CoreGraphics
import Foundation

public enum VisualizerBars {
    private static let perceptualExponent: Float = 0.85
    private static let motionCenter = 0.97
    private static let motionAmplitude = 0.03
    private static let motionFrequency = 2.0
    private static let phaseStep = 0.9
    private static let shimmerPeriod = 1.1
    private static let shimmerWidth = 2.2

    // Distance d (0...barCount/2) from the centre maps to the band range [d*8/(half+1), (d+1)*8/(half+1)).
    // For barCount 15, half+1 == 8, so every bar gets exactly one band, matching the original mapping.
    public static func bandRange(forBar index: Int, barCount: Int) -> Range<Int> {
        let half = barCount / 2
        let distance = abs(index - half)
        let lower = distance * 8 / (half + 1)
        let upper = (distance + 1) * 8 / (half + 1)
        return lower..<upper
    }

    public static func magnitudes(bands: SIMD8<Float>, time: TimeInterval, barCount: Int, reduceMotion: Bool) -> [Float] {
        let half = barCount / 2
        // Reduce the time in Double first; Float(timeIntervalSinceReferenceDate) has ~1 min resolution.
        let phase = reduceMotion ? 0 : (time * motionFrequency).truncatingRemainder(dividingBy: 2 * .pi)
        return (0..<barCount).map { index in
            let distance = abs(index - half)
            let range = bandRange(forBar: index, barCount: barCount)
            let averaged = average(bands, range: range)
            let boosted = pow(clamped(averaged), perceptualExponent)
            let motion = reduceMotion ? 1 : Float(motionCenter + motionAmplitude * sin(phase + Double(distance) * phaseStep))
            return clamped(boosted * motion)
        }
    }

    public static func height(forMagnitude magnitude: Float, minHeight: CGFloat, maxHeight: CGFloat) -> CGFloat {
        minHeight + CGFloat(clamped(magnitude)) * (maxHeight - minHeight)
    }

    public static func heights(
        bands: SIMD8<Float>,
        time: TimeInterval,
        barCount: Int,
        minHeight: CGFloat,
        maxHeight: CGFloat,
        reduceMotion: Bool
    ) -> [CGFloat] {
        magnitudes(bands: bands, time: time, barCount: barCount, reduceMotion: reduceMotion).map {
            height(forMagnitude: $0, minHeight: minHeight, maxHeight: maxHeight)
        }
    }

    public static func shimmer(time: TimeInterval, barCount: Int, reduceMotion: Bool) -> [Float] {
        guard !reduceMotion else { return Array(repeating: 0, count: barCount) }
        let progress = time.truncatingRemainder(dividingBy: shimmerPeriod) / shimmerPeriod
        let position = progress * (Double(barCount) + 2 * shimmerWidth) - shimmerWidth
        return (0..<barCount).map { index in
            let distance = (Double(index) - position) / shimmerWidth
            return clamped(Float(exp(-distance * distance)))
        }
    }

    private static func average(_ bands: SIMD8<Float>, range: Range<Int>) -> Float {
        var sum: Float = 0
        for band in range { sum += bands[band] }
        return sum / Float(range.count)
    }

    private static func clamped(_ value: Float) -> Float {
        value > 0 ? min(value, 1) : 0
    }
}
