import FluidAudio
import os

public protocol TranscriptionEngine: Sendable {
    func prepare() async throws
    func transcribe(_ samples: [Float]) async throws -> String
}

public actor ParakeetTranscriptionEngine: TranscriptionEngine {
    private var loadTask: Task<AsrManager, Error>?
    private let model: SpeechModel
    private let logger = Logger(subsystem: "com.prata.app", category: "TranscriptionEngine")

    public init(model: SpeechModel = .parakeet) {
        self.model = model
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

    // Reentrant actor: overlapping callers must await the same in-flight load, not each start their own.
    private func loadedManager() async throws -> AsrManager {
        if let loadTask { return try await loadTask.value }
        let model = self.model
        let task = Task<AsrManager, Error> {
            let models: AsrModels
            switch model {
            case .parakeet:
                models = try await AsrModels.downloadAndLoad(version: .v3)
            case .pianissimo:
                models = try AsrModels.loadLocal(from: model.directory, version: .v3)
            }
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
