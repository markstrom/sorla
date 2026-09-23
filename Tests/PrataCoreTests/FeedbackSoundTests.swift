import XCTest
@testable import PrataCore

final class FeedbackSoundTests: XCTestCase {
    private let start = FeedbackSound.startSamples()
    private let stop = FeedbackSound.stopSamples()

    func testLengthIsDurationTimesSampleRate() {
        XCTAssertEqual(start.count, Int((0.16 * 48_000).rounded()))
        XCTAssertEqual(stop.count, start.count)
    }

    func testPeakStaysWithinGainTimesHarmonicHeadroom() {
        let peak = start.map(abs).max() ?? 0
        XCTAssertLessThanOrEqual(peak, 0.25 * 1.18)
        XCTAssertGreaterThan(peak, 0.1)
    }

    func testStopIsExactlyStartReversed() {
        XCTAssertEqual(stop, Array(start.reversed()))
    }

    func testStartsAndEndsNearZeroSoThereIsNoClick() {
        XCTAssertEqual(start.first ?? 1, 0, accuracy: 0.001)
        XCTAssertEqual(start.last ?? 1, 0, accuracy: 0.001)
        XCTAssertLessThan(start.prefix(8).map(abs).max() ?? 1, 0.02)
        XCTAssertLessThan(start.suffix(8).map(abs).max() ?? 1, 0.02)
    }

    func testStartRisesInPitch() {
        let third = start.count / 3
        let first = zeroCrossings(start.prefix(third))
        let last = zeroCrossings(start.suffix(third))
        XCTAssertGreaterThan(last, first)
    }

    func testStopFallsInPitch() {
        let third = stop.count / 3
        XCTAssertGreaterThan(zeroCrossings(stop.prefix(third)), zeroCrossings(stop.suffix(third)))
    }

    private func zeroCrossings<S: Collection>(_ samples: S) -> Int where S.Element == Float {
        zip(samples, samples.dropFirst()).filter { ($0 < 0) != ($1 < 0) }.count
    }
}
