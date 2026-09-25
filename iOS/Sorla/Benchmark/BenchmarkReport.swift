import Foundation

struct LoadMeasurement: Equatable, Sendable {
    var label: String
    var seconds: Double
    var footprintBefore: UInt64
    var footprintAfter: UInt64
    var peakFootprint: UInt64
    var availableAfter: UInt64
    var residentAfter: UInt64
}

struct TranscriptionRun: Equatable, Sendable {
    var clip: String
    var source: String
    var audioSeconds: Double
    var run: Int
    var stopToResultMs: Double
    var footprintBefore: UInt64
    var peakFootprint: UInt64
    var footprintAfter: UInt64
    var thermalState: String
    // Length only; the transcript itself is never recorded.
    var characters: Int

    var realTimeFactor: Double { stopToResultMs > 0 ? audioSeconds * 1000 / stopToResultMs : 0 }
}

struct ClipSummary: Equatable, Sendable {
    var clip: String
    var audioSeconds: Double
    var runs: Int
    var medianMs: Double
    var p90Ms: Double
    var maxMs: Double
    var maxPeakFootprint: UInt64
}

// The manifesto's budget: under 0.5 s from letting go to text, for 10 s of speech.
enum LatencyBudget {
    static let referenceAudioSeconds = 10.0
    static let limitMs = 500.0

    static func applies(to audioSeconds: Double) -> Bool {
        abs(audioSeconds - referenceAudioSeconds) <= 2
    }
}

enum Statistics {
    static func median(_ values: [Double]) -> Double {
        percentile(values, 0.5)
    }

    // Nearest-rank percentile, so every reported figure is one that was actually measured.
    static func percentile(_ values: [Double], _ fraction: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let rank = Int((fraction * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank, 1), sorted.count) - 1]
    }
}

struct BenchmarkReport: Equatable, Sendable {
    var date: Date
    var conditionsAtStart: DeviceConditions
    var conditionsAtEnd: DeviceConditions
    var model: ModelStorage.InstalledModel?
    var processUptimeAtStart: Double?
    var isFirstLoadInProcess: Bool
    var baselineFootprint: UInt64
    var loads: [LoadMeasurement]
    var runs: [TranscriptionRun]
    var footprintAfterCleanup: UInt64
    var lifetimePeakFootprint: UInt64

    var summaries: [ClipSummary] {
        var order: [String] = []
        var grouped: [String: [TranscriptionRun]] = [:]
        for run in runs {
            if grouped[run.clip] == nil { order.append(run.clip) }
            grouped[run.clip, default: []].append(run)
        }
        return order.compactMap { clip in
            guard let runs = grouped[clip], let first = runs.first else { return nil }
            let latencies = runs.map(\.stopToResultMs)
            return ClipSummary(
                clip: clip,
                audioSeconds: first.audioSeconds,
                runs: runs.count,
                medianMs: Statistics.median(latencies),
                p90Ms: Statistics.percentile(latencies, 0.9),
                maxMs: latencies.max() ?? 0,
                maxPeakFootprint: runs.map(\.peakFootprint).max() ?? 0
            )
        }
    }

    var markdown: String {
        let formatter = ISO8601DateFormatter()
        var lines = ["### Sorla iOS benchmark — \(formatter.string(from: date))", ""]
        if conditionsAtStart.isSimulator {
            lines += ["> **Simulator run — not evidence.** Core ML runs without the Neural Engine here; these numbers only show that the harness works.", ""]
        }
        lines.append(Self.conditionsTable(conditionsAtStart, end: conditionsAtEnd, model: model))
        let uptime = processUptimeAtStart.map { String(format: "%.1f s", $0) } ?? "unknown"
        lines += ["| Process | up \(uptime) at start; first model load in this process: \(isFirstLoadInProcess ? "yes" : "no") |", ""]

        lines += [
            "| Memory (phys_footprint) | MB |",
            "|---|---|",
            "| Baseline, model not loaded | \(ByteFormat.megabytes(baselineFootprint)) |",
        ]
        if let loaded = loads.first {
            lines.append("| Model loaded | \(ByteFormat.megabytes(loaded.footprintAfter)) |")
            lines.append("| Model loaded, resident incl. mapped weights (not phys_footprint) | \(ByteFormat.megabytes(loaded.residentAfter)) |")
            lines.append("| Peak during first load | \(ByteFormat.megabytes(loaded.peakFootprint)) |")
            if loaded.availableAfter > 0 {
                lines.append("| Headroom before the system limit, model loaded | \(ByteFormat.megabytes(loaded.availableAfter)) |")
            }
        }
        if let peak = runs.map(\.peakFootprint).max() {
            lines.append("| Peak during transcription | \(ByteFormat.megabytes(peak)) |")
        }
        lines += [
            "| After cleanup (model unloaded) | \(ByteFormat.megabytes(footprintAfterCleanup)) |",
            "| Process lifetime peak | \(ByteFormat.megabytes(lifetimePeakFootprint)) |",
            "",
            "| Model load | Time (s) | Footprint before → after (MB) | Peak (MB) |",
            "|---|---|---|---|",
        ]
        for load in loads {
            lines.append("| \(load.label) | \(String(format: "%.2f", load.seconds)) | \(ByteFormat.megabytes(load.footprintBefore)) → \(ByteFormat.megabytes(load.footprintAfter)) | \(ByteFormat.megabytes(load.peakFootprint)) |")
        }

        lines += [
            "",
            "| Clip | Audio (s) | Runs | Median stop→text (ms) | p90 (ms) | Max (ms) | Max peak (MB) | 10 s budget (< 500 ms) |",
            "|---|---|---|---|---|---|---|---|",
        ]
        for summary in summaries {
            let budget: String
            if LatencyBudget.applies(to: summary.audioSeconds) {
                budget = summary.maxMs < LatencyBudget.limitMs ? "met (every run)" : (summary.medianMs < LatencyBudget.limitMs ? "median met, slow runs miss" : "missed")
            } else {
                budget = "–"
            }
            lines.append("| \(summary.clip) | \(String(format: "%.1f", summary.audioSeconds)) | \(summary.runs) | \(Self.ms(summary.medianMs)) | \(Self.ms(summary.p90Ms)) | \(Self.ms(summary.maxMs)) | \(ByteFormat.megabytes(summary.maxPeakFootprint)) | \(budget) |")
        }

        lines += [
            "",
            "<details><summary>Every run</summary>",
            "",
            "| Clip | Source | Audio (s) | Run | Stop→text (ms) | × real time | Before → peak → after (MB) | Thermal | Characters |",
            "|---|---|---|---|---|---|---|---|---|",
        ]
        for run in runs {
            lines.append("| \(run.clip) | \(run.source) | \(String(format: "%.1f", run.audioSeconds)) | \(run.run) | \(Self.ms(run.stopToResultMs)) | \(String(format: "%.1f", run.realTimeFactor)) | \(ByteFormat.megabytes(run.footprintBefore)) → \(ByteFormat.megabytes(run.peakFootprint)) → \(ByteFormat.megabytes(run.footprintAfter)) | \(run.thermalState) | \(run.characters) |")
        }
        lines += ["", "</details>"]
        return lines.joined(separator: "\n")
    }

    private static func ms(_ value: Double) -> String {
        String(format: "%.0f", value)
    }

    static func conditionsTable(_ start: DeviceConditions, end: DeviceConditions? = nil, model: ModelStorage.InstalledModel? = nil) -> String {
        func change(_ keyPath: KeyPath<DeviceConditions, String>) -> String {
            guard let end, end[keyPath: keyPath] != start[keyPath: keyPath] else { return start[keyPath: keyPath] }
            return "\(start[keyPath: keyPath]) → \(end[keyPath: keyPath])"
        }
        var lines = [
            "| Field | Value |",
            "|---|---|",
            "| Device | \(start.deviceModel)\(start.isSimulator ? " (Simulator)" : " (physical)"), \(String(format: "%.1f", Double(start.physicalMemory) / 1_073_741_824)) GiB RAM |",
            "| OS | \(start.systemVersion) |",
            "| Build | Sorla iOS prototype \(start.appVersion), \(start.buildConfiguration) |",
        ]
        if let model {
            let source = [model.sourceRepository, model.sourceRevision.map { String($0.prefix(12)) }].compactMap { $0 }.joined(separator: "@")
            lines.append("| Model | pianissimo-sv \(model.version)\(source.isEmpty ? "" : " (source \(source))"), \(DeviceConditions.encoderPrecision) |")
        }
        lines += [
            "| Dependency | \(DeviceConditions.fluidAudio) |",
            "| Thermal state | \(change(\.thermalState)) |",
            "| Battery | \(change(\.batteryDescription)) |",
            "| Low Power Mode | \(start.isLowPowerMode ? "on" : "off") |",
            "| VoiceOver | \(start.isVoiceOverRunning ? "on" : "off") |",
            "| Network | \(start.network) |",
        ]
        return lines.joined(separator: "\n")
    }
}

enum ReportArchive {
    static var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Reports", isDirectory: true)
    }

    // Reports land in Documents/Reports, reachable through Finder or the Files app.
    @discardableResult
    static func save(_ markdown: String, prefix: String) -> URL? {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = folder.appendingPathComponent("\(prefix)-\(stamp).md")
        return (try? markdown.write(to: url, atomically: true, encoding: .utf8)) != nil ? url : nil
    }
}
