public struct LevelSmoother {
    public private(set) var value: Float
    private let attackCoefficient: Float
    private let releaseCoefficient: Float

    public init(attack: Float = 0.6, release: Float = 0.15, initialValue: Float = 0) {
        self.attackCoefficient = attack
        self.releaseCoefficient = release
        self.value = Self.clamped(initialValue)
    }

    @discardableResult
    public mutating func update(target: Float) -> Float {
        let clampedTarget = Self.clamped(target)
        let coefficient = clampedTarget > value ? attackCoefficient : releaseCoefficient
        value = Self.clamped(value + (clampedTarget - value) * coefficient)
        return value
    }

    private static func clamped(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }
}

public struct BandSmoother {
    private static let attack: Float = 0.3
    private static let release: Float = 0.08
    // Pulling every band part-way toward the mean keeps the shape but stops bars twitching independently.
    private static let coupling: Float = 0.15
    private var smoothers = Array(repeating: LevelSmoother(attack: attack, release: release), count: 8)

    public init() {}

    public mutating func update(target: SIMD8<Float>) -> SIMD8<Float> {
        let mean = target.sum() / 8
        var result = SIMD8<Float>(repeating: 0)
        for band in 0..<8 {
            let blended = target[band] * (1 - Self.coupling) + mean * Self.coupling
            result[band] = smoothers[band].update(target: blended)
        }
        return result
    }
}
