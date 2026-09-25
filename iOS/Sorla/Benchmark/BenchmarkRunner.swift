import AVFoundation
import FluidAudio
import Foundation

// Loads and runs the model through FluidAudio directly, the same calls as ParakeetTranscriptionEngine,
// so load and transcription can be timed separately. That small duplication goes away with #67.
@MainActor
final class BenchmarkRunner: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var status: String?
    @Published private(set) var report: BenchmarkReport?
    @Published private(set) var clips: [BenchmarkClip] = []
    @Published private(set) var isRecordingClip = false
    // Shown on screen to check the model hears Swedish; it is never exported or logged.
    @Published private(set) var lastTranscriptPreview: String?
    @Published var repetitions = 3
    @Published var reloadAfterCleanup = true

    private static var hasLoadedInProcess = false
    private var recordedClips: [BenchmarkClip] = []
    private let clipRecorder = AudioRecorder()

    init() {
        reloadClips()
    }

    func reloadClips() {
        clips = ClipLibrary.load() + recordedClips
    }

    // A tester's own speech, held in memory only and gone when the app quits.
    func toggleClipRecording() {
        if isRecordingClip {
            isRecordingClip = false
            let samples = (try? clipRecorder.stop()) ?? []
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            guard !samples.isEmpty else { return }
            let clip = BenchmarkClip(
                name: String(format: "recorded-%d-%.0fs", recordedClips.count + 1, Double(samples.count) / 16_000),
                source: .recorded,
                samples: samples,
                sampleRate: 16_000
            )
            recordedClips.append(clip)
            reloadClips()
        } else {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.record, mode: .default, options: [.allowBluetoothHFP])
                try session.setActive(true)
                try clipRecorder.start()
                isRecordingClip = true
            } catch {
                status = "Recording failed: \(ErrorSummary.of(error))"
            }
        }
    }

    func clearRecordedClips() {
        recordedClips = []
        reloadClips()
    }

    func run() async {
        guard !isRunning else { return }
        guard PianissimoModel.isInstalled else {
            status = "Install the model first."
            return
        }
        guard !clips.isEmpty else {
            status = "No clips. Run iOS/Benchmark/make-utterances.sh before building, add files to Documents/Utterances, or record one."
            return
        }
        isRunning = true
        defer { isRunning = false }
        do {
            let report = try await measure()
            self.report = report
            let saved = ReportArchive.save(report.markdown, prefix: "benchmark")
            status = saved.map { "Saved to Documents/Reports/\($0.lastPathComponent)" } ?? "Done"
        } catch {
            status = "Benchmark failed: \(ErrorSummary.of(error))"
        }
    }

    private func measure() async throws -> BenchmarkReport {
        let uptime = DeviceConditions.processUptime()
        let isFirstLoad = !Self.hasLoadedInProcess
        let network = await NetworkStatus.current()
        let start = DeviceConditions.capture(network: network)
        let baseline = MemoryProbe.footprint()

        status = "Loading model…"
        var loads: [LoadMeasurement] = []
        let (manager, firstLoad) = try await load(label: isFirstLoad ? "Load, first in this process" : "Load, again in this process")
        loads.append(firstLoad)
        Self.hasLoadedInProcess = true

        let silence = BenchmarkClip(name: "silence-1s", source: .bundled, samples: Array(repeating: 0, count: 16_000), sampleRate: 16_000)
        let warmUp = try await transcribe(silence, run: 1, with: manager, showsPreview: false)
        loads.append(LoadMeasurement(
            label: "First inference (1 s silence, as the app's warm-up)",
            seconds: warmUp.stopToResultMs / 1000,
            footprintBefore: warmUp.footprintBefore,
            footprintAfter: warmUp.footprintAfter,
            peakFootprint: warmUp.peakFootprint,
            availableAfter: MemoryProbe.available(),
            residentAfter: MemoryProbe.resident()
        ))

        var runs: [TranscriptionRun] = []
        for clip in clips {
            for run in 1...max(1, repetitions) {
                status = "Transcribing \(clip.name), run \(run) of \(repetitions)…"
                runs.append(try await transcribe(clip, run: run, with: manager))
            }
        }

        status = "Cleaning up…"
        await manager.cleanup()
        try? await Task.sleep(for: .seconds(1))
        let afterCleanup = MemoryProbe.footprint()

        if reloadAfterCleanup {
            status = "Reloading from the cache…"
            let (again, reload) = try await load(label: "Reload after cleanup, same process")
            loads.append(reload)
            await again.cleanup()
        }

        return BenchmarkReport(
            date: Date(),
            conditionsAtStart: start,
            conditionsAtEnd: DeviceConditions.capture(network: network),
            model: ModelStorage.installedModel(),
            processUptimeAtStart: uptime,
            isFirstLoadInProcess: isFirstLoad,
            baselineFootprint: baseline,
            loads: loads,
            runs: runs,
            footprintAfterCleanup: afterCleanup,
            lifetimePeakFootprint: MemoryProbe.lifetimePeak()
        )
    }

    private func load(label: String) async throws -> (AsrManager, LoadMeasurement) {
        let directory = PianissimoModel.directory
        let before = MemoryProbe.footprint()
        let sampler = MemorySampler()
        sampler.start()
        let start = ContinuousClock.now
        let manager: AsrManager
        do {
            let models = try await Task.detached(priority: .userInitiated) {
                try AsrModels.loadLocal(from: directory, version: .v3)
            }.value
            manager = AsrManager(config: .default)
            try await manager.loadModels(models)
        } catch {
            _ = sampler.stop()
            throw error
        }
        let seconds = (ContinuousClock.now - start) / .seconds(1)
        let peak = sampler.stop()
        return (manager, LoadMeasurement(
            label: label,
            seconds: seconds,
            footprintBefore: before,
            footprintAfter: MemoryProbe.footprint(),
            peakFootprint: peak,
            availableAfter: MemoryProbe.available(),
            residentAfter: MemoryProbe.resident()
        ))
    }

    // Timed from "audio in hand" to text: resampling to 16 kHz plus transcription, as after a stop.
    private func transcribe(_ clip: BenchmarkClip, run: Int, with manager: AsrManager, showsPreview: Bool = true) async throws -> TranscriptionRun {
        let before = MemoryProbe.footprint()
        let sampler = MemorySampler()
        sampler.start()
        let start = ContinuousClock.now
        let text: String
        do {
            let samples = clip.sampleRate == 16_000 ? clip.samples : try AudioRecorder.resample(clip.samples, sampleRate: clip.sampleRate)
            var decoderState = try TdtDecoderState(decoderLayers: await manager.decoderLayerCount)
            text = try await manager.transcribe(samples, decoderState: &decoderState).text
        } catch {
            _ = sampler.stop()
            throw error
        }
        let elapsed = (ContinuousClock.now - start) / .milliseconds(1)
        let peak = sampler.stop()
        if showsPreview {
            lastTranscriptPreview = String(text.prefix(200))
        }
        return TranscriptionRun(
            clip: clip.name,
            source: clip.source.rawValue,
            audioSeconds: clip.seconds,
            run: run,
            stopToResultMs: elapsed,
            footprintBefore: before,
            peakFootprint: peak,
            footprintAfter: MemoryProbe.footprint(),
            thermalState: DeviceConditions.describe(ProcessInfo.processInfo.thermalState),
            characters: text.count
        )
    }
}
