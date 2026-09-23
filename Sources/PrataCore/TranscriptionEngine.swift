import FluidAudio

public protocol TranscriptionEngine: Sendable {
    func prepare() async throws
    func transcribe(_ samples: [Float]) async throws -> String
}

public actor ParakeetTranscriptionEngine: TranscriptionEngine {
    private var asrManager: AsrManager?

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

    private func loadedManager() async throws -> AsrManager {
        if let asrManager { return asrManager }
        let models = try await AsrModels.downloadAndLoad(version: .v3)
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        asrManager = manager
        return manager
    }
}
