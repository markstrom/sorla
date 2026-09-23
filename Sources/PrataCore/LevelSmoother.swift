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
