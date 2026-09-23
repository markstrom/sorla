import FluidAudio
import XCTest
@testable import SorlaCore

final class ParakeetTranscriptionEngineTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("sorla-engine-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // A dictation during the first download must not leave the "model missing" failure behind.
    func testAFailedLoadIsNotCached() async throws {
        let engine = ParakeetTranscriptionEngine(directory: directory)
        await assertLoadFails(engine) { error in
            guard case AsrModelsError.modelNotFound = error else { return XCTFail("unexpected \(error)") }
        }

        try Data("{}".utf8).write(to: directory.appendingPathComponent("parakeet_vocab.json"))

        await assertLoadFails(engine) { error in
            guard case AsrModelsError.loadingFailed = error else { return XCTFail("stale failure reused: \(error)") }
        }
    }

    private func assertLoadFails(_ engine: ParakeetTranscriptionEngine, _ check: (Error) -> Void) async {
        do {
            _ = try await engine.transcribe([0])
            XCTFail("expected the load to fail")
        } catch {
            check(error)
        }
    }
}
