import XCTest
import FluidAudio
@testable import PrataCore

final class ParakeetTranscriptionEngineTests: XCTestCase {
    func testTranscribesSynthesizedEnglishSpeech() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["PRATA_ASR_INTEGRATION"] == "1",
            "Set PRATA_ASR_INTEGRATION=1 to run (downloads the Parakeet model)."
        )

        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("prata-asr-\(UUID().uuidString).aiff")
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-v", "Samantha", "-o", audioURL.path, "The quick brown fox jumps over the lazy dog."]
        try say.run()
        say.waitUntilExit()
        XCTAssertEqual(say.terminationStatus, 0)

        let samples = try AudioConverter().resampleAudioFile(path: audioURL.path)
        let engine = ParakeetTranscriptionEngine()
        try await engine.prepare()

        let start = Date()
        let text = try await engine.transcribe(samples)
        let elapsed = Date().timeIntervalSince(start)
        print("Parakeet transcribed \(Double(samples.count) / 16000)s of audio in \(elapsed)s: \(text)")

        let lowered = text.lowercased()
        XCTAssertTrue(lowered.contains("fox"), "Unexpected transcript: \(text)")
        XCTAssertTrue(lowered.contains("lazy dog"), "Unexpected transcript: \(text)")
    }
}
