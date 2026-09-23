import XCTest
@testable import SorlaCore

final class FeedbackSoundTests: XCTestCase {
    private let start = FeedbackSound.startSamples()
    private let stop = FeedbackSound.stopSamples()

    func testLengthIsDurationTimesSampleRate() {
        XCTAssertEqual(start.count, Int((0.46 * 48_000).rounded()))
        XCTAssertEqual(stop.count, start.count)
    }

    func testBothAreNormalizedToTheSamePeak() {
        XCTAssertEqual(start.map(abs).max() ?? 0, 0.25, accuracy: 0.0001)
        XCTAssertEqual(stop.map(abs).max() ?? 0, 0.25, accuracy: 0.0001)
    }

    func testStartsAndEndsNearZeroSoThereIsNoClick() {
        for samples in [start, stop] {
            XCTAssertEqual(samples.first ?? 1, 0, accuracy: 0.001)
            XCTAssertEqual(samples.last ?? 1, 0, accuracy: 0.001)
            XCTAssertLessThan(samples.prefix(8).map(abs).max() ?? 1, 0.02)
        }
    }

    func testStartPlaysTheLowNoteThenTheHighNote() {
        XCTAssertLessThan(zeroCrossings(start, from: 0.01, to: 0.07), zeroCrossings(start, from: 0.09, to: 0.15))
    }

    func testStopPlaysTheSameNotesInReverseOrder() {
        XCTAssertGreaterThan(zeroCrossings(stop, from: 0.01, to: 0.07), zeroCrossings(stop, from: 0.09, to: 0.15))
        XCTAssertEqual(
            Double(zeroCrossings(stop, from: 0.01, to: 0.07)),
            Double(zeroCrossings(start, from: 0.09, to: 0.15)),
            accuracy: 2
        )
    }

    func testHasAQuietEcho() {
        let direct = energy(start, from: 0.0, to: 0.06)
        let echo = energy(start, from: 0.19, to: 0.25)
        XCTAssertGreaterThan(echo, 0)
        XCTAssertLessThan(echo, direct * 0.3)
    }

    private func range(_ from: Double, _ to: Double) -> Range<Int> {
        Int(from * 48_000)..<Int(to * 48_000)
    }

    private func zeroCrossings(_ samples: [Float], from: Double, to: Double) -> Int {
        let slice = samples[range(from, to)]
        return zip(slice, slice.dropFirst()).filter { ($0 < 0) != ($1 < 0) }.count
    }

    private func energy(_ samples: [Float], from: Double, to: Double) -> Float {
        samples[range(from, to)].reduce(0) { $0 + $1 * $1 }
    }
}
