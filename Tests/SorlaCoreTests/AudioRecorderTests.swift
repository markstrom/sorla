import XCTest
import AVFoundation
@testable import SorlaCore

final class AudioRecorderTests: XCTestCase {
    func testResampleConvertsOneSecondAt48kHzTo16kSamples() throws {
        let sampleRate = 48000.0
        let sourceSamples: [Float] = (0..<Int(sampleRate)).map { i in
            Float(sin(2.0 * Double.pi * 440.0 * Double(i) / sampleRate))
        }

        let resampled = try AudioRecorder.resample(sourceSamples, sampleRate: sampleRate)

        let expectedCount = 16000.0
        XCTAssertEqual(Double(resampled.count), expectedCount, accuracy: expectedCount * 0.05)
    }

    func testResamplePreservesSignalEnergy() throws {
        let sampleRate = 44100.0
        let sourceSamples: [Float] = (0..<Int(sampleRate)).map { i in
            Float(0.5 * sin(2.0 * Double.pi * 440.0 * Double(i) / sampleRate))
        }

        let resampled = try AudioRecorder.resample(sourceSamples, sampleRate: sampleRate)

        let rms = sqrt(resampled.map { $0 * $0 }.reduce(0, +) / Float(resampled.count))
        XCTAssertEqual(rms, 0.5 / sqrt(2), accuracy: 0.05)
    }

    func testResampleOfEmptyInputReturnsEmptyOutput() throws {
        let resampled = try AudioRecorder.resample([], sampleRate: 48000)
        XCTAssertTrue(resampled.isEmpty)
    }
}

final class AudioRecorderBufferTests: XCTestCase {
    private let input = FakeAudioInput()
    private let resampler = FakeResampler()

    private func recordingRecorder() throws -> AudioRecorder {
        let recorder = AudioRecorder(input: input, resampler: resampler)
        try recorder.start()
        input.feed(count: 1_024)
        XCTAssertEqual(recorder.heldSampleCount, 1_024)
        return recorder
    }

    func testStopHandsTheAudioOverAndKeepsNone() throws {
        let recorder = try recordingRecorder()

        let samples = try recorder.stop()

        XCTAssertEqual(samples.count, 1_024)
        XCTAssertEqual(recorder.heldSampleCount, 0)
        XCTAssertFalse(input.isRunning)
    }

    func testCancelDropsTheAudioWithoutResampling() throws {
        let recorder = try recordingRecorder()

        recorder.cancel()

        XCTAssertEqual(recorder.heldSampleCount, 0)
        XCTAssertEqual(resampler.calls, 0)
        XCTAssertFalse(input.isRunning)
    }

    func testAFailedResampleStillLetsGoOfTheAudio() throws {
        let recorder = try recordingRecorder()
        resampler.error = AudioRecorderError.bufferAllocationFailed

        XCTAssertThrowsError(try recorder.stop())

        XCTAssertEqual(recorder.heldSampleCount, 0)
        XCTAssertEqual(resampler.calls, 1)
    }

    func testFramesAfterStopAreNotKept() throws {
        let recorder = try recordingRecorder()
        _ = try recorder.stop()

        input.feed(count: 1_024)

        XCTAssertEqual(recorder.heldSampleCount, 0)
    }
}
