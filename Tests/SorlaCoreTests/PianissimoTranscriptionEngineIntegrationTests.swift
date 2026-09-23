import XCTest
import FluidAudio
@testable import SorlaCore

final class PianissimoTranscriptionEngineIntegrationTests: XCTestCase {
    func testTranscribesSynthesizedSwedishSpeech() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["SORLA_ASR_INTEGRATION"] == "1",
            "Set SORLA_ASR_INTEGRATION=1 to run (reads the Pianissimo bundle from Application Support)."
        )
        try XCTSkipUnless(
            PianissimoModel.isInstalled,
            "Pianissimo bundle not installed at \(PianissimoModel.directory.path)."
        )

        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sorla-asr-\(UUID().uuidString).aiff")
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-v", "Alva", "-o", audioURL.path, "Den snabba bruna räven hoppar över den lata hunden."]
        try say.run()
        say.waitUntilExit()
        XCTAssertEqual(say.terminationStatus, 0)

        let samples = try AudioConverter().resampleAudioFile(path: audioURL.path)
        let engine = ParakeetTranscriptionEngine()
        try await engine.prepare()

        let start = Date()
        let text = try await engine.transcribe(samples)
        let elapsed = Date().timeIntervalSince(start)
        print("Pianissimo transcribed \(Double(samples.count) / 16000)s of audio in \(elapsed)s: \(text)")

        let lowered = text.lowercased()
        XCTAssertTrue(lowered.contains("räven"), "Unexpected transcript: \(text)")
        XCTAssertTrue(lowered.contains("hunden"), "Unexpected transcript: \(text)")
    }
}
