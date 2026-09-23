import XCTest
@testable import PrataCore

final class VisualizerBarsTests: XCTestCase {
    private let minHeight: CGFloat = 3
    private let maxHeight: CGFloat = 26

    func testBarCountIsFifteen() {
        XCTAssertEqual(VisualizerBars.barCount, 15)
        let heights = VisualizerBars.heights(
            bands: SIMD8(repeating: 0.5), time: 0,
            minHeight: minHeight, maxHeight: maxHeight, reduceMotion: false
        )
        XCTAssertEqual(heights.count, 15)
    }

    func testBandMappingIsMirroredAroundTheCentre() {
        let bands = (0..<VisualizerBars.barCount).map(VisualizerBars.band(forBar:))
        XCTAssertEqual(bands, [7, 6, 5, 4, 3, 2, 1, 0, 1, 2, 3, 4, 5, 6, 7])
    }

    func testCentreBarFollowsTheLowestBandAndEdgesTheHighest() {
        var bands = SIMD8<Float>(repeating: 0)
        bands[0] = 1
        let lowOnly = VisualizerBars.magnitudes(bands: bands, time: 0, reduceMotion: true)
        XCTAssertGreaterThan(lowOnly[7], 0.9)
        XCTAssertEqual(lowOnly[0], 0)
        XCTAssertEqual(lowOnly[14], 0)

        bands = SIMD8(repeating: 0)
        bands[7] = 1
        let highOnly = VisualizerBars.magnitudes(bands: bands, time: 0, reduceMotion: true)
        XCTAssertGreaterThan(highOnly[0], 0.9)
        XCTAssertGreaterThan(highOnly[14], 0.9)
        XCTAssertEqual(highOnly[7], 0)
    }

    func testAllHeightsAreWithinMinAndMax() {
        let spectra: [SIMD8<Float>] = [
            SIMD8(repeating: 0), SIMD8(repeating: 1), SIMD8(repeating: 5), SIMD8(repeating: -1),
            SIMD8(0, 0.1, 0.2, 0.4, 0.6, 0.8, 0.9, 1),
        ]
        for bands in spectra {
            for time: TimeInterval in [0, 1.23, 7.5] {
                for reduceMotion in [false, true] {
                    let heights = VisualizerBars.heights(
                        bands: bands, time: time,
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

    func testSilenceIsAllMinHeight() {
        let heights = VisualizerBars.heights(
            bands: SIMD8(repeating: 0), time: 3.14,
            minHeight: minHeight, maxHeight: maxHeight, reduceMotion: false
        )
        XCTAssertEqual(heights, Array(repeating: minHeight, count: 15))
    }

    func testReduceMotionIsIndependentOfTime() {
        let bands = SIMD8<Float>(0.9, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2)
        let atZero = VisualizerBars.heights(
            bands: bands, time: 0, minHeight: minHeight, maxHeight: maxHeight, reduceMotion: true
        )
        let atLater = VisualizerBars.heights(
            bands: bands, time: 42, minHeight: minHeight, maxHeight: maxHeight, reduceMotion: true
        )
        XCTAssertEqual(atZero, atLater)
    }

    func testMotionCanVaryOverTimeWhenNotReduced() {
        let bands = SIMD8<Float>(repeating: 0.6)
        let atZero = VisualizerBars.heights(
            bands: bands, time: 0, minHeight: minHeight, maxHeight: maxHeight, reduceMotion: false
        )
        let atLater = VisualizerBars.heights(
            bands: bands, time: 0.4, minHeight: minHeight, maxHeight: maxHeight, reduceMotion: false
        )
        XCTAssertNotEqual(atZero, atLater)
    }

    func testShimmerStaysWithinZeroToOneAndSweepsOverTime() {
        let early = VisualizerBars.shimmer(time: 0.1, reduceMotion: false)
        let later = VisualizerBars.shimmer(time: 0.6, reduceMotion: false)
        XCTAssertEqual(early.count, 15)
        for value in early + later {
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThanOrEqual(value, 1)
        }
        let earlyPeak = early.indices.max { early[$0] < early[$1] }!
        let laterPeak = later.indices.max { later[$0] < later[$1] }!
        XCTAssertGreaterThan(laterPeak, earlyPeak)
    }

    func testShimmerIsStaticUnderReduceMotion() {
        let atZero = VisualizerBars.shimmer(time: 0, reduceMotion: true)
        let atLater = VisualizerBars.shimmer(time: 13.7, reduceMotion: true)
        XCTAssertEqual(atZero, atLater)
        XCTAssertEqual(atZero, Array(repeating: 0, count: 15))
    }
}
