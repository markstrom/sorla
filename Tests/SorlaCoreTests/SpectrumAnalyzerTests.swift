import XCTest
@testable import SorlaCore

final class SpectrumAnalyzerTests: XCTestCase {
    private func sine(frequency: Double, amplitude: Float = 0.01, sampleRate: Double, count: Int = 1024) -> [Float] {
        (0..<count).map { i in amplitude * Float(sin(2 * Double.pi * frequency * Double(i) / sampleRate)) }
    }

    private func loudestBand(_ bands: SIMD8<Float>) -> Int {
        (0..<8).max { bands[$0] < bands[$1] }!
    }

    func testSineLandsInTheBandContainingItsFrequency() {
        let cases: [(frequency: Double, band: Int)] = [(100, 0), (200, 1), (500, 3), (1000, 4), (3000, 6), (6000, 7)]
        for sampleRate in [48_000.0, 44_100.0] {
            let analyzer = SpectrumAnalyzer(sampleRate: sampleRate)
            for (frequency, band) in cases {
                let samples = sine(frequency: frequency, sampleRate: sampleRate)
                let bands = samples.withUnsafeBufferPointer { analyzer.analyze($0) }
                XCTAssertEqual(loudestBand(bands), band, "\(frequency) Hz at \(sampleRate) Hz: \(bands)")
                XCTAssertGreaterThan(bands[band], 0.3, "\(frequency) Hz at \(sampleRate) Hz")
            }
        }
    }

    func testSilenceIsAllZero() {
        let analyzer = SpectrumAnalyzer(sampleRate: 48_000)
        let silence = [Float](repeating: 0, count: 1024)
        let bands = silence.withUnsafeBufferPointer { analyzer.analyze($0) }
        XCTAssertEqual(bands, SIMD8(repeating: 0))
    }

    func testOutputIsAlwaysWithinZeroToOne() {
        let analyzer = SpectrumAnalyzer(sampleRate: 48_000)
        var generator = SystemRandomNumberGenerator()
        let inputs: [[Float]] = [
            sine(frequency: 440, amplitude: 1, sampleRate: 48_000),
            (0..<1024).map { _ in Float.random(in: -1...1, using: &generator) },
            (0..<1024).map { $0 % 2 == 0 ? 4 : -4 },
            [Float](repeating: 1, count: 1024),
            sine(frequency: 1000, sampleRate: 48_000, count: 300),
            sine(frequency: 1000, sampleRate: 48_000, count: 4800),
        ]
        for input in inputs {
            let bands = input.withUnsafeBufferPointer { analyzer.analyze($0) }
            for index in 0..<8 {
                XCTAssertGreaterThanOrEqual(bands[index], 0)
                XCTAssertLessThanOrEqual(bands[index], 1)
            }
        }
    }

    func testBandsAboveNyquistStayZeroAtLowSampleRates() {
        let analyzer = SpectrumAnalyzer(sampleRate: 8_000)
        let samples = sine(frequency: 1000, sampleRate: 8_000)
        let bands = samples.withUnsafeBufferPointer { analyzer.analyze($0) }
        XCTAssertEqual(loudestBand(bands), 4)
        XCTAssertEqual(bands[7], 0)
    }
}
