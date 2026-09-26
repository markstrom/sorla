import XCTest
@testable import Sorla

final class StatisticsTests: XCTestCase {
    func testTheMedianIsAMeasuredValue() {
        XCTAssertEqual(Statistics.median([300, 100, 200]), 200)
        XCTAssertEqual(Statistics.median([100, 200, 300, 400]), 200)
    }

    func testTheNinetiethPercentileIsTheSlowRun() {
        let values = (1...10).map(Double.init)
        XCTAssertEqual(Statistics.percentile(values, 0.9), 9)
        XCTAssertEqual(Statistics.percentile([5], 0.9), 5)
        XCTAssertEqual(Statistics.percentile([], 0.9), 0)
    }
}

final class BenchmarkReportTests: XCTestCase {
    private func conditions(simulator: Bool = false) -> DeviceConditions {
        DeviceConditions(
            deviceModel: "iPhone16,1",
            isSimulator: simulator,
            systemVersion: "iOS 27.0",
            buildConfiguration: "Release",
            physicalMemory: 8 * 1_073_741_824,
            thermalState: "nominal",
            batteryLevel: 0.8,
            batteryState: "unplugged",
            isLowPowerMode: false,
            isVoiceOverRunning: false,
            network: "offline",
            appVersion: "0.1.0 (1)"
        )
    }

    private func run(_ clip: String, seconds: Double, ms: Double, run: Int) -> TranscriptionRun {
        TranscriptionRun(
            clip: clip, source: "bundled", audioSeconds: seconds, run: run, stopToResultMs: ms,
            footprintBefore: 900_000_000, peakFootprint: 1_100_000_000, footprintAfter: 900_000_000,
            thermalState: "nominal", characters: 42
        )
    }

    private func report(runs: [TranscriptionRun], simulator: Bool = false) -> BenchmarkReport {
        var end = conditions(simulator: simulator)
        end.thermalState = "fair"
        return BenchmarkReport(
            date: Date(timeIntervalSince1970: 0),
            conditionsAtStart: conditions(simulator: simulator),
            conditionsAtEnd: end,
            model: ModelStorage.InstalledModel(version: "1.0.0", sourceRepository: "KlangAI/pianissimo-sv", sourceRevision: "8f1f6d8f8bd7482a5ea1d2bfaf6ef5be61597138"),
            processUptimeAtStart: 4.2,
            isFirstLoadInProcess: true,
            baselineFootprint: 40_000_000,
            loads: [LoadMeasurement(label: "Load, first in this process", seconds: 3.5, footprintBefore: 40_000_000, footprintAfter: 800_000_000, peakFootprint: 950_000_000, availableAfter: 2_000_000_000, residentAfter: 1_500_000_000)],
            runs: runs,
            footprintAfterCleanup: 60_000_000,
            lifetimePeakFootprint: 1_200_000_000
        )
    }

    func testRunsAreSummarisedPerClipInOrder() {
        let summaries = report(runs: [
            run("10s", seconds: 10, ms: 400, run: 1),
            run("5s", seconds: 5, ms: 200, run: 1),
            run("10s", seconds: 10, ms: 600, run: 2),
            run("10s", seconds: 10, ms: 450, run: 3),
        ]).summaries

        XCTAssertEqual(summaries.map(\.clip), ["10s", "5s"])
        XCTAssertEqual(summaries[0].runs, 3)
        XCTAssertEqual(summaries[0].medianMs, 450)
        XCTAssertEqual(summaries[0].maxMs, 600)
    }

    func testTheTenSecondBudgetShowsSlowRunsNotJustTheBest() {
        let markdown = report(runs: [
            run("10s", seconds: 10, ms: 400, run: 1),
            run("10s", seconds: 10, ms: 450, run: 2),
            run("10s", seconds: 10, ms: 700, run: 3),
        ]).markdown
        XCTAssertTrue(markdown.contains("median met, slow runs miss"))
    }

    func testTheReportRecordsModelDependencyDeviceAndConditions() {
        let markdown = report(runs: [run("5s", seconds: 5, ms: 200, run: 1)]).markdown
        XCTAssertTrue(markdown.contains("pianissimo-sv 1.0.0"))
        XCTAssertTrue(markdown.contains("8f1f6d8f8bd7"))
        XCTAssertTrue(markdown.contains("int8"))
        XCTAssertTrue(markdown.contains("FluidAudio 0.16.1"))
        XCTAssertTrue(markdown.contains("iPhone16,1 (physical)"))
        XCTAssertTrue(markdown.contains("iOS 27.0"))
        XCTAssertTrue(markdown.contains("Release"))
        XCTAssertTrue(markdown.contains("nominal → fair"))
        XCTAssertTrue(markdown.contains("| Network | offline |"))
        XCTAssertFalse(markdown.contains("not evidence"))
    }

    func testSimulatorRunsAreMarkedAsNotEvidence() {
        let markdown = report(runs: [], simulator: true).markdown
        XCTAssertTrue(markdown.contains("Simulator run — not evidence"))
        XCTAssertTrue(markdown.contains("(Simulator)"))
    }

    func testMemoryFiguresAreInDecimalMegabytes() {
        let markdown = report(runs: [run("5s", seconds: 5, ms: 200, run: 1)]).markdown
        XCTAssertTrue(markdown.contains("| Baseline, model not loaded | 40 |"))
        XCTAssertTrue(markdown.contains("| Model loaded | 800 |"))
        XCTAssertTrue(markdown.contains("mapped weights (not phys_footprint) | 1500 |"))
        XCTAssertTrue(markdown.contains("| After cleanup (model unloaded) | 60 |"))
    }
}

final class MemoryProbeTests: XCTestCase {
    func testTheFootprintIsReadable() {
        XCTAssertGreaterThan(MemoryProbe.footprint(), 0)
        XCTAssertGreaterThanOrEqual(MemoryProbe.lifetimePeak(), MemoryProbe.footprint() / 2)
    }

    func testTheSamplerSeesAnAllocationMadeWhileItRuns() {
        let sampler = MemorySampler()
        let before = MemoryProbe.footprint()
        sampler.start()
        let block = UnsafeMutableRawPointer.allocate(byteCount: 64_000_000, alignment: 16)
        block.initializeMemory(as: UInt8.self, repeating: 1, count: 64_000_000)
        let peak = sampler.stop()
        block.deallocate()
        XCTAssertGreaterThan(peak, before + 32_000_000)
    }

    func testDirectorySizeAddsUpFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("a"), withIntermediateDirectories: true)
        try Data(count: 1_000).write(to: folder.appendingPathComponent("one"))
        try Data(count: 2_500).write(to: folder.appendingPathComponent("a/two"))
        defer { try? FileManager.default.removeItem(at: folder) }

        let size = DirectorySize.of(folder)
        XCTAssertEqual(size.logical, 3_500)
        XCTAssertGreaterThanOrEqual(size.allocated, 3_500)
    }
}
