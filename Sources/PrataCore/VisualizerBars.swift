import CoreGraphics
import Foundation

public enum VisualizerBars {
    private static let perceptualExponent: Float = 0.7
    private static let centerWeightFloor: Float = 0.6
    private static let motionCenter: Float = 0.925
    private static let motionAmplitude: Float = 0.075
    private static let motionFrequency: Float = 2
    private static let phaseStep: Float = 0.9

    public static func heights(
        level: Float,
        count: Int,
        time: TimeInterval,
        minHeight: CGFloat,
        maxHeight: CGFloat,
        reduceMotion: Bool
    ) -> [CGFloat] {
        guard count > 0 else { return [] }
        let boosted = pow(max(level, 0), perceptualExponent)
        let mid = Float(count - 1) / 2

        return (0..<count).map { index in
            let distanceFromCenter = mid > 0 ? abs(Float(index) - mid) / mid : 0
            let centerWeight = centerWeightFloor + (1 - centerWeightFloor) * cos(distanceFromCenter * .pi / 2)
            let motion = reduceMotion
                ? 1
                : motionCenter + motionAmplitude * sin(Float(time) * motionFrequency + Float(index) * phaseStep)
            let magnitude = min(max(boosted * centerWeight * motion, 0), 1)
            return minHeight + CGFloat(magnitude) * (maxHeight - minHeight)
        }
    }
}
