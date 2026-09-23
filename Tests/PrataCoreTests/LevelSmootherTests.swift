import XCTest
@testable import PrataCore

final class LevelSmootherTests: XCTestCase {
    func testRisingReachesTargetFasterThanFalling() {
        var rising = LevelSmoother(initialValue: 0)
        var falling = LevelSmoother(initialValue: 1)

        var risingValue: Float = 0
        var fallingValue: Float = 1
        for _ in 0..<3 {
            risingValue = rising.update(target: 1)
            fallingValue = falling.update(target: 0)
        }

        XCTAssertGreaterThan(risingValue, 1 - fallingValue)
    }

    func testStaysWithinZeroToOneForOutOfRangeTargets() {
        var smoother = LevelSmoother()
        for target: Float in [-5, -1, 0, 0.5, 1, 2, 10] {
            let value = smoother.update(target: target)
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThanOrEqual(value, 1)
        }
    }

    func testConvergesToSteadyTarget() {
        var smoother = LevelSmoother()
        var value: Float = 0
        for _ in 0..<100 {
            value = smoother.update(target: 0.6)
        }
        XCTAssertEqual(value, 0.6, accuracy: 0.01)
    }

    func testInitialValueIsClamped() {
        let smoother = LevelSmoother(initialValue: 5)
        XCTAssertEqual(smoother.value, 1)
    }

    func testBandSmootherMovesCalmlyButKeepsTheShape() {
        var smoother = BandSmoother()
        var target = SIMD8<Float>(repeating: 0)
        target[2] = 1
        let first = smoother.update(target: target)
        XCTAssertGreaterThan(first[2], 0)
        XCTAssertLessThan(first[2], 0.25)
        XCTAssertGreaterThan(first[2], first[0])

        var value = first
        for _ in 0..<200 {
            value = smoother.update(target: SIMD8(repeating: 0.4))
        }
        for band in 0..<8 {
            XCTAssertEqual(value[band], 0.4, accuracy: 0.01)
        }
    }
}
