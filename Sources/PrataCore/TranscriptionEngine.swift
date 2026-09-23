import FluidAudio

public protocol TranscriptionEngine: Sendable {
    func prepare() async throws
    func transcribe(_ samples: [Float]) async throws -> String
}

public actor ParakeetTranscriptionEngine: TranscriptionEngine {
    private var loadTask: Task<AsrManager, Error>?

    public init() {}

    public func prepare() async throws {
        _ = try await loadedManager()
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
        let task = Task<AsrManager, Error> {
            let models = try await AsrModels.downloadAndLoad(version: .v3)
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
