import CoreGraphics
import Foundation

public enum VisualizerBars {
    // Above 1 so differences between bands grow instead of every bar sitting near the same height.
    private static let contrastExponent: Float = 1.35
    private static let wobbleFloor: Float = 0.45
    private static let shimmerPeriod = 1.1
    private static let shimmerWidth = 2.2

    // Bars mirror around a centre bar, so each distance from it gets an equal slice of the 8 bands.
    public static func bandRange(forBar index: Int, barCount: Int) -> Range<Int> {
        precondition(barCount % 2 == 1, "bar count must be odd")
        let half = barCount / 2
        let distance = abs(index - half)
        let lower = distance * 8 / (half + 1)
        let upper = (distance + 1) * 8 / (half + 1)
        return lower..<upper
    }

    public static func magnitudes(bands: SIMD8<Float>, time: TimeInterval, barCount: Int, reduceMotion: Bool) -> [Float] {
        (0..<barCount).map { index in
            let range = bandRange(forBar: index, barCount: barCount)
            let level = pow(clamped(average(bands, range: range)), contrastExponent)
            let motion = reduceMotion ? 1 : wobbleFloor + (1 - wobbleFloor) * wobble(bar: index, time: time)
            return clamped(level * motion)
        }
    }

    // Each bar sways on its own irregular rhythm so the voice's level shows as varied, lifelike heights.
    static func wobble(bar index: Int, time: TimeInterval) -> Float {
        let spread = Double(index) * 0.618_034
        let slow = 5.0 + 3.0 * spread.truncatingRemainder(dividingBy: 1)
        let fast = 8.5 + 4.0 * (spread * 1.7).truncatingRemainder(dividingBy: 1)
        // Reduce the time in Double first; Float(timeIntervalSinceReferenceDate) has ~1 min resolution.
        let a = sin((time * slow).truncatingRemainder(dividingBy: 2 * .pi) + spread * 5.1)
        let b = sin((time * fast).truncatingRemainder(dividingBy: 2 * .pi) + spread * 2.3)
        return clamped(Float(0.5 + 0.3 * a + 0.2 * b))
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
