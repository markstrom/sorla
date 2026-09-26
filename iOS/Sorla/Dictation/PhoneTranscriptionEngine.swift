import CoreML
import FluidAudio
import Foundation

// On the iPhone every component runs on the CPU. Measured on an iPhone 16 Plus (iOS 27.0, Release, #65): the encoder
// loads in about 4 s on the CPU against 10–55 s on the Neural Engine (which compiles it again in every process, and
// even again in the same process), and turns 10 s of speech into text in 0.49–0.58 s against 0.49–0.88 s. A cold
// load then fits inside the ~27 s a background stop gets. GPU is not an option: iOS refuses GPU work in the background.
enum PhoneModelConfiguration {
    static let computeUnits: MLComputeUnits = .cpuOnly

    static func make() -> MLModelConfiguration {
        let configuration = AsrModels.defaultConfiguration()
        configuration.computeUnits = computeUnits
        return configuration
    }
}

// The Mac's ParakeetTranscriptionEngine with the phone's compute units; it merges into the shared engine with #67.
actor PhoneTranscriptionEngine: TranscriptionEngine {
    private let directory: URL
    private var loadTask: Task<AsrManager, Error>?

    init(directory: URL = PianissimoModel.directory) {
        self.directory = directory
    }

    func prepare() async throws {
        _ = try await loadedManager()
        // Warm-up; a failure here shows up again, and is reported, on the real transcription.
        _ = try? await transcribe(Array(repeating: Float(0), count: 16_000))
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        let manager = try await loadedManager()
        var decoderState = try TdtDecoderState(decoderLayers: await manager.decoderLayerCount)
        return try await manager.transcribe(samples, decoderState: &decoderState).text
    }

    func unload() async {
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
            let models = try AsrModels.loadLocal(from: directory, version: .v3, configuration: PhoneModelConfiguration.make())
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
