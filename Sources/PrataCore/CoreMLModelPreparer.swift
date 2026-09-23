import CoreML
import Foundation

public struct CoreMLModelPreparer: ModelPreparer {
    public init() {}

    public func compile(package: URL, into destination: URL) async throws {
        let compiled = try await MLModel.compileModel(at: package)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: compiled, to: destination)
    }

    // Loads the staged model exactly as dictation will and transcribes one second of silence.
    public func selfTest(modelDirectory: URL) async throws {
        let engine = ParakeetTranscriptionEngine(directory: modelDirectory)
        do {
            _ = try await engine.transcribe(Array(repeating: Float(0), count: 16_000))
        } catch {
            await engine.unload()
            throw error
        }
        await engine.unload()
    }
}
