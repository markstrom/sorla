import AVFoundation
import CoreML
import FluidAudio
import Foundation
import UIKit

// Hands-free device probes for #65/#66, started by launch arguments (e.g. from `devicectl device process launch`).
// Each writes a numbers-only Markdown report to Documents/Reports; the load and microphone probes then exit, so the
// next launch is a fresh process. Never audio, never transcript text.
//
//   -SorlaLoadProbe all|ane|gpu|cpu|ane-fast|ane-async   load, first inference, 10 s + 30 s clips, cleanup, reload
//   -SorlaIdleProbe YES                                 load (default units) and stay loaded, logging memory every 5 s
//   -SorlaMicProbe <seconds> [-SorlaMicProbeLoad YES]   one capture through LiveDictationRecorder, with or without a
//                                                       concurrent model load, then per-0.5 s levels
enum DeviceProbes {
    @MainActor
    static func runIfRequested() async -> Bool {
        let defaults = UserDefaults.standard
        if let variant = defaults.string(forKey: "SorlaLoadProbe") {
            await LoadProbe.run(variant: variant)
            exit(0)
        }
        if defaults.bool(forKey: "SorlaIdleProbe") {
            await IdleProbe.run()
            return true
        }
        let micSeconds = defaults.double(forKey: "SorlaMicProbe")
        if micSeconds > 0 {
            // As the foreground-start path: wait until the app is active.
            for _ in 0..<100 where UIApplication.shared.applicationState != .active {
                try? await Task.sleep(for: .milliseconds(50))
            }
            await MicProbe.run(seconds: micSeconds, loadConcurrently: defaults.bool(forKey: "SorlaMicProbeLoad"))
            exit(0)
        }
        return false
    }

    static func uptime() -> String { String(format: "%.2f s", DeviceConditions.processUptime() ?? -1) }
}

// The Core ML / ANE compiled-program cache Core ML keeps in the app's caches folder.
enum CoreMLCache {
    struct Stats {
        var files: Int
        var bytes: Int64
        var newest: Date?
        var summary: String {
            let newestText = newest.map { ISO8601DateFormatter().string(from: $0) } ?? "none"
            return "\(files) files, \(ByteFormat.megabytes(bytes)) MB, newest \(newestText)"
        }
    }

    static var folder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.sorla.ios", isDirectory: true)
    }

    static func stats() -> Stats {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        var stats = Stats(files: 0, bytes: 0, newest: nil)
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else { return stats }
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            stats.files += 1
            stats.bytes += Int64(values.fileSize ?? 0)
            if let date = values.contentModificationDate, date > (stats.newest ?? .distantPast) { stats.newest = date }
        }
        return stats
    }
}

// Loads each component itself (FluidAudio's `loadLocal` builds a fresh configuration per component and keeps only
// the compute units), so the configuration under test really reaches Core ML and each component is timed.
enum ProbeModelLoader {
    struct Variant {
        var name: String
        var units: MLComputeUnits
        var fastPrediction = false
        var asyncLoad = false
    }

    static func variant(named name: String) -> Variant {
        switch name {
        case "all": return Variant(name: name, units: .all)
        case "gpu": return Variant(name: name, units: .cpuAndGPU)
        case "cpu": return Variant(name: name, units: .cpuOnly)
        case "ane-fast": return Variant(name: name, units: .cpuAndNeuralEngine, fastPrediction: true)
        case "ane-async": return Variant(name: name, units: .cpuAndNeuralEngine, asyncLoad: true)
        default: return Variant(name: "ane", units: .cpuAndNeuralEngine)
        }
    }

    static func configuration(_ variant: Variant, units: MLComputeUnits) -> MLModelConfiguration {
        let config = MLModelConfiguration()
        config.computeUnits = units
        config.allowLowPrecisionAccumulationOnGPU = true
        if variant.fastPrediction {
            var hints = MLOptimizationHints()
            hints.specializationStrategy = .fastPrediction
            config.optimizationHints = hints
        }
        return config
    }

    // Returns the models and each component's load time in seconds.
    static func load(_ variant: Variant, from directory: URL) async throws -> (AsrModels, [(String, Double)]) {
        var timings: [(String, Double)] = []
        func component(_ file: String, units: MLComputeUnits) async throws -> MLModel {
            let url = directory.appendingPathComponent(file)
            let config = configuration(variant, units: units)
            let start = ContinuousClock.now
            let model: MLModel
            if variant.asyncLoad {
                model = try await MLModel.load(contentsOf: url, configuration: config)
            } else {
                model = try await Task.detached(priority: .userInitiated) {
                    try MLModel(contentsOf: url, configuration: config)
                }.value
            }
            timings.append((file, (ContinuousClock.now - start) / .seconds(1)))
            return model
        }
        let preprocessor = try await component("Preprocessor.mlmodelc", units: .cpuOnly)
        let encoder = try await component("Encoder.mlmodelc", units: variant.units)
        let decoder = try await component("Decoder.mlmodelc", units: variant.units)
        let joint = try await component("JointDecisionv3.mlmodelc", units: variant.units)
        let models = AsrModels(
            encoder: encoder,
            preprocessor: preprocessor,
            decoder: decoder,
            joint: joint,
            configuration: configuration(variant, units: variant.units),
            vocabulary: try vocabulary(at: directory.appendingPathComponent("parakeet_vocab.json")),
            version: .v3
        )
        return (models, timings)
    }

    static func vocabulary(at url: URL) throws -> [Int: String] {
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        var vocabulary: [Int: String] = [:]
        if let array = json as? [String] {
            for (index, token) in array.enumerated() { vocabulary[index] = token }
        } else if let dict = json as? [String: String] {
            for (key, value) in dict { if let id = Int(key) { vocabulary[id] = value } }
        }
        return vocabulary
    }
}

@MainActor
enum LoadProbe {
    static func run(variant name: String) async {
        let variant = ProbeModelLoader.variant(named: name)
        var lines = ["### Load probe — \(variant.name)", ""]
        func add(_ line: String) { lines.append(line) }
        add("| Measure | Value |")
        add("|---|---|")
        add("| Process uptime at start | \(DeviceProbes.uptime()) |")
        add("| Thermal / Low Power | \(DeviceConditions.describe(ProcessInfo.processInfo.thermalState)) / \(ProcessInfo.processInfo.isLowPowerModeEnabled) |")
        add("| Core ML cache before | \(CoreMLCache.stats().summary) |")
        add("| Footprint before | \(ByteFormat.megabytes(MemoryProbe.footprint())) MB |")
        let directory = PianissimoModel.directory
        do {
            let (manager, cold) = try await timedLoad(variant, directory: directory, label: "cold", add: add)
            add("| Core ML cache after first load | \(CoreMLCache.stats().summary) |")
            let silence = [Float](repeating: 0, count: 16_000)
            add("| First inference (1 s silence) | \(try await transcribeMs(silence, manager)) |")
            for clipName in ["sv-010s", "sv-030s"] {
                guard let clip = ClipLibrary.load().first(where: { $0.name == clipName }) else { continue }
                let samples = try AudioRecorder.resample(clip.samples, sampleRate: clip.sampleRate)
                // Resampling is outside the timing here; it is a few ms (see the benchmark reports).
                add("| Stop→text \(clipName), run 1 / run 2 | \(try await transcribeMs(samples, manager)) / \(try await transcribeMs(samples, manager)) |")
            }
            add("| Footprint loaded, idle | \(ByteFormat.megabytes(MemoryProbe.footprint())) MB (resident \(ByteFormat.megabytes(MemoryProbe.resident())) MB) |")
            await manager.cleanup()
            try? await Task.sleep(for: .seconds(1))
            add("| Footprint after cleanup | \(ByteFormat.megabytes(MemoryProbe.footprint())) MB |")
            let (again, _) = try await timedLoad(variant, directory: directory, label: "warm (same process)", add: add)
            await again.cleanup()
            _ = cold
        } catch {
            add("| Error | \(ErrorSummary.of(error)) |")
        }
        add("| Core ML cache at end | \(CoreMLCache.stats().summary) |")
        add("| Lifetime peak footprint | \(ByteFormat.megabytes(MemoryProbe.lifetimePeak())) MB |")
        ReportArchive.save(lines.joined(separator: "\n") + "\n", prefix: "loadprobe-\(variant.name)")
    }

    private static func timedLoad(
        _ variant: ProbeModelLoader.Variant, directory: URL, label: String, add: (String) -> Void
    ) async throws -> (AsrManager, Double) {
        let sampler = MemorySampler()
        sampler.start()
        let start = ContinuousClock.now
        let (models, timings) = try await ProbeModelLoader.load(variant, from: directory)
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        let seconds = (ContinuousClock.now - start) / .seconds(1)
        let peak = sampler.stop()
        let parts = timings.map { "\($0.0.replacingOccurrences(of: ".mlmodelc", with: "")) \(String(format: "%.2f", $0.1))" }
        add("| Load \(label) | \(String(format: "%.2f", seconds)) s (\(parts.joined(separator: ", "))), peak \(ByteFormat.megabytes(peak)) MB |")
        return (manager, seconds)
    }

    private static func transcribeMs(_ samples: [Float], _ manager: AsrManager) async throws -> String {
        let start = ContinuousClock.now
        var state = try TdtDecoderState(decoderLayers: await manager.decoderLayerCount)
        _ = try await manager.transcribe(samples, decoderState: &state)
        return String(format: "%.0f ms", (ContinuousClock.now - start) / .milliseconds(1))
    }
}

// Keeps the model loaded and logs memory and app state every 5 s (and on state changes), appending to one report,
// to see what an idle loaded model costs and whether iOS keeps the process in the background.
@MainActor
enum IdleProbe {
    static var manager: AsrManager?
    static var url: URL?

    static func run() async {
        try? FileManager.default.createDirectory(at: ReportArchive.folder, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        url = ReportArchive.folder.appendingPathComponent("idleprobe-\(stamp).md")
        append("### Idle probe\n\n| Uptime | State | Footprint MB | Resident MB | Available MB | Event |\n|---|---|---|---|---|---|")
        log("launched")
        do {
            let (models, _) = try await ProbeModelLoader.load(ProbeModelLoader.variant(named: "ane"), from: PianissimoModel.directory)
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            var state = try TdtDecoderState(decoderLayers: await manager.decoderLayerCount)
            _ = try await manager.transcribe([Float](repeating: 0, count: 16_000), decoderState: &state)
            self.manager = manager
            log("loaded + warmed")
        } catch {
            log("load failed: \(ErrorSummary.of(error))")
        }
        for name in [UIApplication.didEnterBackgroundNotification, UIApplication.willEnterForegroundNotification,
                     UIApplication.didReceiveMemoryWarningNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { note in
                MainActor.assumeIsolated { log(note.name.rawValue.replacingOccurrences(of: "UIApplication", with: "")) }
            }
        }
        Task { @MainActor in
            while true {
                try? await Task.sleep(for: .seconds(5))
                log("tick")
            }
        }
    }

    static func log(_ event: String) {
        let state: String
        switch UIApplication.shared.applicationState {
        case .active: state = "active"
        case .inactive: state = "inactive"
        case .background: state = "background"
        @unknown default: state = "?"
        }
        append("| \(DeviceProbes.uptime()) | \(state) | \(ByteFormat.megabytes(MemoryProbe.footprint())) | \(ByteFormat.megabytes(MemoryProbe.resident())) | \(ByteFormat.megabytes(MemoryProbe.available())) | \(event) |")
    }

    static func append(_ line: String) {
        guard let url, let data = (line + "\n").data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}

// One capture through the real recorder, right after a fresh launch, as the foreground-start path does.
@MainActor
enum MicProbe {
    static func run(seconds: Double, loadConcurrently: Bool) async {
        var lines = ["### Mic probe — \(loadConcurrently ? "with" : "without") concurrent model load", ""]
        let recorder = LiveDictationRecorder()
        recorder.onDiagnostic = { lines.append("- \(DeviceProbes.uptime()) \($0)") }
        let session = AVAudioSession.sharedInstance()
        lines.append("- \(DeviceProbes.uptime()) before start: state \(UIApplication.shared.applicationState.rawValue), "
            + "category \(session.category.rawValue), otherAudioPlaying \(session.isOtherAudioPlaying), "
            + "secondaryHint \(session.secondaryAudioShouldBeSilencedHint), inputAvailable \(session.isInputAvailable), "
            + "record permission \(AVAudioApplication.shared.recordPermission.rawValue)")
        var load: Task<Void, Never>?
        do {
            try recorder.start()
            lines.append("- \(DeviceProbes.uptime()) started")
            if loadConcurrently {
                load = Task.detached(priority: .userInitiated) {
                    _ = try? AsrModels.loadLocal(from: PianissimoModel.directory, version: .v3)
                }
            }
            try? await Task.sleep(for: .seconds(seconds))
            let samples = try recorder.stop()
            lines.append("- \(DeviceProbes.uptime()) stopped; \(DictationCoordinator.levels(of: samples))")
            lines.append("- per 0.5 s peak dBFS: " + halfSecondPeaks(samples))
        } catch {
            lines.append("- start/stop failed: \(ErrorSummary.of(error))")
        }
        if let load { await load.value }
        ReportArchive.save(lines.joined(separator: "\n") + "\n", prefix: "micprobe-\(loadConcurrently ? "load" : "noload")")
    }

    static func halfSecondPeaks(_ samples: [Float]) -> String {
        let chunk = 8_000
        return stride(from: 0, to: samples.count, by: chunk).map { start in
            let peak = samples[start..<min(samples.count, start + chunk)].reduce(Float(0)) { max($0, abs($1)) }
            return peak > 0 ? String(format: "%.0f", 20 * log10(peak)) : "-inf"
        }.joined(separator: " ")
    }
}
