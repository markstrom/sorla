import Foundation
import os

// What installing the model cost: time, storage and memory, per step.
struct InstallReport: Equatable, Sendable {
    struct Step: Equatable, Sendable {
        var name: String
        var seconds: Double
        var peakFootprint: UInt64
    }

    var modelVersion: String
    var manifestTotalBytes: Int64
    var downloadedSize: DirectorySize.Size
    var installedSize: DirectorySize.Size
    var downloadSeconds: Double
    var downloadedFileCount: Int
    var steps: [Step]
    var footprintBefore: UInt64
    var footprintAfter: UInt64
    var conditions: DeviceConditions

    var markdown: String {
        var lines = [
            "### Model install — \(modelVersion)",
            "",
            BenchmarkReport.conditionsTable(conditions),
            "",
            "| Measure | Value |",
            "|---|---|",
            "| Published size (manifest total) | \(ByteFormat.megabytes(manifestTotalBytes)) MB |",
            "| Downloaded packages on disk (logical / allocated) | \(ByteFormat.megabytes(downloadedSize.logical)) / \(ByteFormat.megabytes(downloadedSize.allocated)) MB |",
            "| Installed compiled model (logical / allocated) | \(ByteFormat.megabytes(installedSize.logical)) / \(ByteFormat.megabytes(installedSize.allocated)) MB |",
            "| Download time (\(downloadedFileCount) files fetched) | \(String(format: "%.1f", downloadSeconds)) s |",
            "| Footprint before / after install | \(ByteFormat.megabytes(footprintBefore)) / \(ByteFormat.megabytes(footprintAfter)) MB |",
            "",
            "| Step | Time (s) | Peak footprint (MB) |",
            "|---|---|---|",
        ]
        for step in steps {
            lines.append("| \(step.name) | \(String(format: "%.2f", step.seconds)) | \(ByteFormat.megabytes(step.peakFootprint)) |")
        }
        return lines.joined(separator: "\n")
    }
}

// Times each compile and the post-install self-test (the model's first load and one second of silence).
struct MeasuringPreparer: ModelPreparer {
    let base = CoreMLModelPreparer()
    let steps: StepRecorder

    func compile(package: URL, into destination: URL) async throws {
        try await steps.measure("Compile \(package.deletingPathExtension().lastPathComponent)") {
            try await base.compile(package: package, into: destination)
        }
    }

    func selfTest(modelDirectory: URL) async throws {
        try await steps.measure("Self-test: first load + 1 s silence") {
            try await base.selfTest(modelDirectory: modelDirectory)
        }
    }
}

final class StepRecorder: Sendable {
    private let state = OSAllocatedUnfairLock<[InstallReport.Step]>(initialState: [])
    private let preparingAt = OSAllocatedUnfairLock<ContinuousClock.Instant?>(initialState: nil)

    var steps: [InstallReport.Step] { state.withLock { $0 } }
    var downloadsFinishedAt: ContinuousClock.Instant? { preparingAt.withLock { $0 } }

    func markDownloadsFinished() {
        preparingAt.withLock { if $0 == nil { $0 = .now } }
    }

    func measure(_ name: String, _ work: () async throws -> Void) async throws {
        let sampler = MemorySampler()
        sampler.start()
        let start = ContinuousClock.now
        defer {
            let seconds = (ContinuousClock.now - start) / .seconds(1)
            let peak = sampler.stop()
            state.withLock { $0.append(InstallReport.Step(name: name, seconds: seconds, peakFootprint: peak)) }
        }
        try await work()
    }
}

@MainActor
final class ModelSetup: ObservableObject {
    enum State: Equatable {
        case idle
        case downloading(Double)
        case preparing
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var report: InstallReport?
    @Published private(set) var installed: ModelStorage.InstalledModel?
    @Published private(set) var downloadedPackages: DirectorySize.Size?

    private var task: Task<Void, Never>?

    init() {
        refresh()
    }

    var isBusy: Bool {
        switch state {
        case .downloading, .preparing: return true
        case .idle, .failed: return false
        }
    }

    func refresh() {
        installed = PianissimoModel.isInstalled ? ModelStorage.installedModel() : nil
        let staging = DirectorySize.of(ModelStorage.stagingRoot)
        downloadedPackages = staging.logical > 0 ? staging : nil
    }

    // Downloaded packages are kept after install, so a reinstall re-measures a fresh compile without re-downloading.
    func install() {
        guard !isBusy else { return }
        task = Task { await runInstall() }
    }

    func removeDownloadedPackages() {
        guard !isBusy else { return }
        ModelStaging.removeEverything(in: ModelStorage.modelsDirectory)
        refresh()
    }

    func removeInstalledModel() async {
        guard !isBusy else { return }
        await DictationRuntime.shared.coordinator.unloadModelIfIdle()
        try? FileManager.default.removeItem(at: ModelStorage.installedDirectory)
        refresh()
    }

    func runInstall() async {
        state = .downloading(0)
        let footprintBefore = MemoryProbe.footprint()
        let steps = StepRecorder()
        let installer = ModelInstaller(
            modelsDirectory: ModelStorage.modelsDirectory,
            network: URLSessionModelNetwork(),
            preparer: MeasuringPreparer(steps: steps)
        )
        do {
            let published = try await installer.fetchLatest()
            let staging = ModelStaging(modelsDirectory: ModelStorage.modelsDirectory, version: published.release.version)
            let pendingFiles = staging.filesNeedingDownload(published.release.files).count
            let start = ContinuousClock.now
            let staged = try await installer.stage(published) { [weak self] progress in
                switch progress {
                case .downloading(let fraction):
                    Task { @MainActor in
                        if case .downloading = self?.state { self?.state = .downloading(fraction) }
                    }
                case .preparing:
                    steps.markDownloadsFinished()
                    Task { @MainActor in self?.state = .preparing }
                }
            }
            let downloadSeconds = ((steps.downloadsFinishedAt ?? .now) - start) / .seconds(1)
            let downloaded = DirectorySize.of(staging.downloadsDirectory)
            await DictationRuntime.shared.coordinator.unloadModelIfIdle()
            let swap = ModelSwap(modelsDirectory: ModelStorage.modelsDirectory)
            try swap.install(staged)
            try swap.commit()
            let network = await NetworkStatus.current()
            report = InstallReport(
                modelVersion: "pianissimo-sv \(published.release.version)",
                manifestTotalBytes: published.release.totalSize,
                downloadedSize: downloaded,
                installedSize: DirectorySize.of(ModelStorage.installedDirectory),
                downloadSeconds: downloadSeconds,
                downloadedFileCount: pendingFiles,
                steps: steps.steps,
                footprintBefore: footprintBefore,
                footprintAfter: MemoryProbe.footprint(),
                conditions: DeviceConditions.capture(network: network)
            )
            if let report { ReportArchive.save(report.markdown, prefix: "install") }
            state = .idle
        } catch {
            state = .failed((error as? ModelInstallError)?.reason ?? ErrorSummary.of(error))
        }
        refresh()
    }
}
