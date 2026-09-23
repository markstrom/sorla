import FluidAudio
import Foundation
import os

public protocol TranscriptionEngine: Sendable {
    func prepare() async throws
    func transcribe(_ samples: [Float]) async throws -> String
    func unload() async
}

// Named for the Parakeet TDT architecture: Pianissimo is a Swedish checkpoint converted to that same architecture.
public actor ParakeetTranscriptionEngine: TranscriptionEngine {
    private let directory: URL
    private var loadTask: Task<AsrManager, Error>?
    private let logger = Logger(subsystem: "com.sorla.app", category: "TranscriptionEngine")

    public init(directory: URL = PianissimoModel.directory) {
        self.directory = directory
    }

    public func prepare() async throws {
        _ = try await loadedManager()
        do {
            _ = try await transcribe(Array(repeating: Float(0), count: 16_000))
        } catch {
            logger.error("warm-up transcription failed: \(String(describing: error), privacy: .public)")
        }
    }

    public func transcribe(_ samples: [Float]) async throws -> String {
        let manager = try await loadedManager()
        let decoderLayers = await manager.decoderLayerCount
        var decoderState = try TdtDecoderState(decoderLayers: decoderLayers)
        let result = try await manager.transcribe(samples, decoderState: &decoderState)
        return result.text
    }

    // Drops the loaded models so the next prepare or transcribe reads the directory afresh.
    public func unload() async {
        guard let task = loadTask else { return }
        loadTask = nil
        if let manager = try? await task.value {
            await manager.cleanup()
        }
    }

    // Reentrant actor: overlapping callers must await the same in-flight load, not each start their own.
    private func loadedManager() async throws -> AsrManager {
        if let loadTask { return try await loadTask.value }
        let directory = self.directory
        let task = Task<AsrManager, Error> {
            let models = try AsrModels.loadLocal(from: directory, version: .v3)
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            return manager
        }
        loadTask = task
        do {
            return try await task.value
        } catch {
            loadTask = nil
            throw error
        }
    }
}
