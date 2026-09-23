import XCTest
@testable import SorlaCore

final class VisualizerBarsTests: XCTestCase {
    private let minHeight: CGFloat = 3
    private let maxHeight: CGFloat = 26

    func testFifteenBarCountProducesFifteenHeights() {
        let heights = VisualizerBars.heights(
            bands: SIMD8(repeating: 0.5), time: 0, barCount: 15,
            minHeight: minHeight, maxHeight: maxHeight, reduceMotion: false
        )
        XCTAssertEqual(heights.count, 15)
    }

    func testFiveBarCountProducesFiveHeights() {
        let heights = VisualizerBars.heights(
            bands: SIMD8(repeating: 0.5), time: 0, barCount: 5,
            minHeight: minHeight, maxHeight: maxHeight, reduceMotion: false
        )
        XCTAssertEqual(heights.count, 5)
    }

    func testBandRangeMappingIsMirroredAroundTheCentreForFifteenBars() {
        let ranges = (0..<15).map { VisualizerBars.bandRange(forBar: $0, barCount: 15) }
        XCTAssertEqual(ranges, [7..<8, 6..<7, 5..<6, 4..<5, 3..<4, 2..<3, 1..<2, 0..<1, 1..<2, 2..<3, 3..<4, 4..<5, 5..<6, 6..<7, 7..<8])
    }

    // 8 bands split three ways for 5 bars: centre gets [0,2), the next ring [2,5), the edges [5,8).
    func testBandRangeMappingSplitsEightBandsThreeWaysForFiveBars() {
        let ranges = (0..<5).map { VisualizerBars.bandRange(forBar: $0, barCount: 5) }
        XCTAssertEqual(ranges, [5..<8, 2..<5, 0..<2, 2..<5, 5..<8])
    }

    func testBandRangeEdgesAreSymmetricForFiveBars() {
        XCTAssertEqual(
            VisualizerBars.bandRange(forBar: 0, barCount: 5),
            VisualizerBars.bandRange(forBar: 4, barCount: 5)
        )
        XCTAssertEqual(
            VisualizerBars.bandRange(forBar: 1, barCount: 5),
            VisualizerBars.bandRange(forBar: 3, barCount: 5)
        )
    }

    func testCentreBarFollowsTheLowestBandAndEdgesTheHighestForFifteenBars() {
        var bands = SIMD8<Float>(repeating: 0)
        bands[0] = 1
        let lowOnly = VisualizerBars.magnitudes(bands: bands, time: 0, barCount: 15, reduceMotion: true)
        XCTAssertGreaterThan(lowOnly[7], 0.9)
        XCTAssertEqual(lowOnly[0], 0)
        XCTAssertEqual(lowOnly[14], 0)

        bands = SIMD8(repeating: 0)
        bands[7] = 1
        let highOnly = VisualizerBars.magnitudes(bands: bands, time: 0, barCount: 15, reduceMotion: true)
        XCTAssertGreaterThan(highOnly[0], 0.9)
        XCTAssertGreaterThan(highOnly[14], 0.9)
        XCTAssertEqual(highOnly[7], 0)
    }

    func testCentreBarAveragesLowBandsAndEdgesAverageHighBandsForFiveBars() {
        var bands = SIMD8<Float>(repeating: 0)
        bands[0] = 1
        bands[1] = 1
        let lowOnly = VisualizerBars.magnitudes(bands: bands, time: 0, barCount: 5, reduceMotion: true)
        XCTAssertGreaterThan(lowOnly[2], 0.9)
        XCTAssertEqual(lowOnly[0], 0)
        XCTAssertEqual(lowOnly[4], 0)

        bands = SIMD8(repeating: 0)
        bands[5] = 1
        bands[6] = 1
        bands[7] = 1
        let highOnly = VisualizerBars.magnitudes(bands: bands, time: 0, barCount: 5, reduceMotion: true)
        XCTAssertGreaterThan(highOnly[0], 0.9)
        XCTAssertGreaterThan(highOnly[4], 0.9)
        XCTAssertEqual(highOnly[0], highOnly[4])
        XCTAssertEqual(highOnly[2], 0)
    }

    func testAllHeightsAreWithinMinAndMax() {
        let spectra: [SIMD8<Float>] = [
            SIMD8(repeating: 0), SIMD8(repeating: 1), SIMD8(repeating: 5), SIMD8(repeating: -1),
            SIMD8(0, 0.1, 0.2, 0.4, 0.6, 0.8, 0.9, 1),
        ]
        for bands in spectra {
            for barCount in [5, 15] {
                for time: TimeInterval in [0, 1.23, 7.5] {
                    for reduceMotion in [false, true] {
                        let heights = VisualizerBars.heights(
                            bands: bands, time: time, barCount: barCount,
                            minHeight: minHeight, maxHeight: maxHeight, reduceMotion: reduceMotion
                        )
                        for height in heights {
                            XCTAssertGreaterThanOrEqual(height, minHeight)
                            XCTAssertLessThanOrEqual(height, maxHeight)
                        }
                    }
                }
            }
        }
    }

    func testSilenceIsAllMinHeight() {
        for barCount in [5, 15] {
            let heights = VisualizerBars.heights(
                bands: SIMD8(repeating: 0), time: 3.14, barCount: barCount,
                minHeight: minHeight, maxHeight: maxHeight, reduceMotion: false
            )
            XCTAssertEqual(heights, Array(repeating: minHeight, count: barCount))
        }
    }

    func testReduceMotionIsIndependentOfTime() {
        let bands = SIMD8<Float>(0.9, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2)
        for barCount in [5, 15] {
            let atZero = VisualizerBars.heights(
                bands: bands, time: 0, barCount: barCount, minHeight: minHeight, maxHeight: maxHeight, reduceMotion: true
            )
            let atLater = VisualizerBars.heights(
                bands: bands, time: 42, barCount: barCount, minHeight: minHeight, maxHeight: maxHeight, reduceMotion: true
            )
            XCTAssertEqual(atZero, atLater)
        }
    }

    func testMotionCanVaryOverTimeWhenNotReduced() {
        let bands = SIMD8<Float>(repeating: 0.6)
        let atZero = VisualizerBars.heights(
            bands: bands, time: 0, barCount: 15, minHeight: minHeight, maxHeight: maxHeight, reduceMotion: false
        )
        let atLater = VisualizerBars.heights(
            bands: bands, time: 0.4, barCount: 15, minHeight: minHeight, maxHeight: maxHeight, reduceMotion: false
        )
        XCTAssertNotEqual(atZero, atLater)
    }

    func testShimmerStaysWithinZeroToOneAndSweepsOverTime() {
        for barCount in [5, 15] {
            let early = VisualizerBars.shimmer(time: 0.1, barCount: barCount, reduceMotion: false)
            let later = VisualizerBars.shimmer(time: 0.6, barCount: barCount, reduceMotion: false)
            XCTAssertEqual(early.count, barCount)
            for value in early + later {
                XCTAssertGreaterThanOrEqual(value, 0)
                XCTAssertLessThanOrEqual(value, 1)
            }
        }
        let early = VisualizerBars.shimmer(time: 0.1, barCount: 15, reduceMotion: false)
        let later = VisualizerBars.shimmer(time: 0.6, barCount: 15, reduceMotion: false)
        let earlyPeak = early.indices.max { early[$0] < early[$1] }!
        let laterPeak = later.indices.max { later[$0] < later[$1] }!
        XCTAssertGreaterThan(laterPeak, earlyPeak)
    }

    func testShimmerIsStaticUnderReduceMotion() {
        for barCount in [5, 15] {
            let atZero = VisualizerBars.shimmer(time: 0, barCount: barCount, reduceMotion: true)
            let atLater = VisualizerBars.shimmer(time: 13.7, barCount: barCount, reduceMotion: true)
            XCTAssertEqual(atZero, atLater)
            XCTAssertEqual(atZero, Array(repeating: 0, count: barCount))
        }
    }
}
