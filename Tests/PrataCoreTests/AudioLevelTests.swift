import XCTest
@testable import PrataCore

final class AudioLevelTests: XCTestCase {
    func testSilenceIsZero() {
        let samples: [Float] = Array(repeating: 0, count: 1024)
        let rms = samples.withUnsafeBufferPointer { AudioLevel.rms($0) }

        XCTAssertEqual(rms, 0)
        XCTAssertEqual(AudioLevel.normalized(rms: rms), 0)
    }

    func testFullScaleSineIsApproximatelyPoint94() {
        let sampleRate = 16000.0
        let samples: [Float] = (0..<1024).map { i in
            Float(sin(2.0 * Double.pi * 440.0 * Double(i) / sampleRate))
        }
        let rms = samples.withUnsafeBufferPointer { AudioLevel.rms($0) }

        XCTAssertEqual(rms, 0.707, accuracy: 0.01)
        XCTAssertEqual(AudioLevel.normalized(rms: rms), 0.94, accuracy: 0.01)
    }

    func testMinus50dBAndBelowClampsToZero() {
        XCTAssertEqual(AudioLevel.normalized(rms: 0.00316), 0, accuracy: 0.001)
        XCTAssertEqual(AudioLevel.normalized(rms: 0.001), 0)
    }

    func testAboveZeroDBClampsToOne() {
        XCTAssertEqual(AudioLevel.normalized(rms: 2.0), 1)
        XCTAssertEqual(AudioLevel.normalized(rms: 1.0), 1)
    }

    func testRMSOfKnownSquareWave() {
        let samples: [Float] = [1, -1, 1, -1]
        let rms = samples.withUnsafeBufferPointer { AudioLevel.rms($0) }

        XCTAssertEqual(rms, 1.0, accuracy: 0.0001)
    }

    func testRMSOfEmptyBufferIsZero() {
        let samples: [Float] = []
        let rms = samples.withUnsafeBufferPointer { AudioLevel.rms($0) }

        XCTAssertEqual(rms, 0)
    }
}
