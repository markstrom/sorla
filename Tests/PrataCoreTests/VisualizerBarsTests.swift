import XCTest
@testable import PrataCore

final class VisualizerBarsTests: XCTestCase {
    private let minHeight: CGFloat = 3
    private let maxHeight: CGFloat = 20

    func testAllHeightsAreWithinMinAndMax() {
        for level: Float in [0, 0.1, 0.5, 0.94, 1] {
            for time: TimeInterval in [0, 1.23, 7.5] {
                let heights = VisualizerBars.heights(
                    level: level, count: 15, time: time,
                    minHeight: minHeight, maxHeight: maxHeight, reduceMotion: false
                )
                for height in heights {
                    XCTAssertGreaterThanOrEqual(height, minHeight)
                    XCTAssertLessThanOrEqual(height, maxHeight)
                }
            }
        }
    }

    func testSilenceIsAllMinHeight() {
        let heights = VisualizerBars.heights(
            level: 0, count: 15, time: 3.14,
            minHeight: minHeight, maxHeight: maxHeight, reduceMotion: false
        )
        XCTAssertEqual(heights, Array(repeating: minHeight, count: 15))
    }

    func testCenterBarIsAtLeastAsTallAsEdgeBars() {
        let heights = VisualizerBars.heights(
            level: 0.8, count: 15, time: 2.0,
            minHeight: minHeight, maxHeight: maxHeight, reduceMotion: false
        )
        let center = heights[heights.count / 2]

        XCTAssertGreaterThanOrEqual(center, heights.first!)
        XCTAssertGreaterThanOrEqual(center, heights.last!)
    }

    func testReduceMotionIsIndependentOfTime() {
        let atZero = VisualizerBars.heights(
            level: 0.6, count: 15, time: 0,
            minHeight: minHeight, maxHeight: maxHeight, reduceMotion: true
        )
        let atLater = VisualizerBars.heights(
            level: 0.6, count: 15, time: 42,
            minHeight: minHeight, maxHeight: maxHeight, reduceMotion: true
        )

        XCTAssertEqual(atZero, atLater)
    }

    func testMotionCanVaryOverTimeWhenNotReduced() {
        let atZero = VisualizerBars.heights(
            level: 0.6, count: 15, time: 0,
            minHeight: minHeight, maxHeight: maxHeight, reduceMotion: false
        )
        let atLater = VisualizerBars.heights(
            level: 0.6, count: 15, time: 0.4,
            minHeight: minHeight, maxHeight: maxHeight, reduceMotion: false
        )

        XCTAssertNotEqual(atZero, atLater)
    }

    func testCountIsRespected() {
        for count in [9, 11, 15, 21] {
            let heights = VisualizerBars.heights(
                level: 0.5, count: count, time: 0,
                minHeight: minHeight, maxHeight: maxHeight, reduceMotion: false
            )
            XCTAssertEqual(heights.count, count)
        }
    }
}
